import Foundation
import Darwin

/// Strict persistence primitives shared by the app and its extensions (#245,
/// lane 2 Shared shim), so extension writers can fail closed. MOVED, unchanged,
/// from Ate/Logic/ArchiveRecoveryJournal.swift (worker A owns the archive
/// invariants): the POSIX writer lease with its append-only UInt64 generation
/// chain, including the NO-FLOCK nested mode (lock order "Shape A": account
/// gate OUTER holding the shared writer-gate-v1.lock flock, archive INNER).
/// Extensions must use the nested mode only; standalone flock mode stays for
/// the app-side import/startup-recovery sessions.


// Swift's Darwin module also exposes struct flock. Bind the C symbol explicitly
// with its exact int/int -> int ABI rather than resolving the struct initializer.
@_silgen_name("flock")
private func archive_flock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Apple-platform prep candidate. Shared directory must be the SAME trusted container
/// for app and every extension. Caller must not substitute an account-selected path.
/// All functions are synchronous; no lease is to be held across an unbounded await.
final class POSIXArchiveWriterLease {
    enum Failure: Error { case busy, invalidDirectory, syscall(String, Int32), unsafeFile }
    let directoryDescriptor: Int32
    private let lockDescriptor: Int32
    private var active = true
    private(set) var generation: UInt64 = 0

    /// Standalone mode: lifetime exclusive flock on `.ate-writer.lock` in the directory.
    convenience init(directory: URL) throws {
        try self.init(directory: directory, lockName: ".ate-writer.lock", flockLockFile: true)
    }

    /// NESTED mode (approved cross-slice lock order: account gate OUTER, archive INNER).
    /// The caller already holds the shared account-gate flock on writer-gate-v1.lock, so this
    /// opens and flocks NO lock file; it only reads/validates/advances the append-only
    /// generation record. Intended to be acquired and released per effect, never held for an
    /// app lifetime or across an await.
    convenience init(nestedDirectory: URL) throws {
        try self.init(directory: nestedDirectory, lockName: "", flockLockFile: false)
    }

    /// lockName must be one safe file component inside the directory. The lock file is NEVER
    /// unlinked: unlinking would allow a second inode and a parallel lock. When flockLockFile
    /// is false (nested mode) the lock file is not even opened.
    init(directory: URL, lockName: String, flockLockFile: Bool = true) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw Failure.invalidDirectory }
        if flockLockFile {
            // Same rule as the app-side JournalArchiveValidation.safeMediaName (one
            // safe file component); kept local so Shared/ never imports app-target types.
            guard Self.safeComponentName(lockName) else { throw Failure.invalidDirectory }
        }
        var dir = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw Failure.syscall("root", errno) }
        do {
            for part in directory.path.split(separator: "/") {
                guard part != ".", part != ".." else { throw Failure.invalidDirectory }
                let next = Darwin.openat(dir, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw Failure.syscall("directory", errno) }
                Darwin.close(dir); dir = next
            }
            if flockLockFile {
                let fd = Darwin.openat(dir, lockName, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
                guard fd >= 0 else { throw Failure.syscall("lock file", errno) }
                var info = stat()
                guard Darwin.fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
                    Darwin.close(fd); throw Failure.unsafeFile
                }
                guard archive_flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                    let code = errno; Darwin.close(fd)
                    if code == EWOULDBLOCK || code == EAGAIN { throw Failure.busy }
                    throw Failure.syscall("lock", code)
                }
                directoryDescriptor = dir; lockDescriptor = fd
                do { generation = try readGeneration() }
                catch { archive_flock(fd, LOCK_UN); Darwin.close(fd); throw error }
            } else {
                // No lock file opened; the outer catch closes dir on any throw.
                directoryDescriptor = dir; lockDescriptor = -1
                generation = try readGeneration()
            }
        } catch { Darwin.close(dir); throw error }
    }

    func requireActive() throws { guard active else { throw Failure.unsafeFile } }
    func validate() throws {
        try requireActive()
        guard try readGeneration() == generation else { throw Failure.unsafeFile }
    }
    /// Append-only durable generation record, never rewrite a counter in place.
    /// Must be called after every covered committed write by EVERY cooperative writer.
    func commitGeneration(_ next: UInt64) throws {
        try validate()
        guard generation < UInt64.max, next == generation + 1 else { throw Failure.unsafeFile }
        let name = String(format: ".generation-%020llu", next)
        let fd = Darwin.openat(directoryDescriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure.syscall("create generation", errno) }
        defer { Darwin.close(fd) }
        let data = Data(name.utf8)
        let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
        guard count == data.count, Darwin.fsync(fd) == 0, Darwin.fsync(directoryDescriptor) == 0 else {
            throw Failure.syscall("persist generation", errno)
        }
        generation = next
    }
    private func readGeneration() throws -> UInt64 {
        let duplicate = Darwin.dup(directoryDescriptor)
        guard duplicate >= 0 else { throw Failure.syscall("duplicate lease directory", errno) }
        guard let stream = Darwin.fdopendir(duplicate) else { Darwin.close(duplicate); throw Failure.unsafeFile }
        defer { Darwin.closedir(stream) }
        Darwin.rewinddir(stream)
        var values: [UInt64] = []
        errno = 0
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name.hasPrefix(".generation-") {
                guard let number = UInt64(name.dropFirst(12)), number > 0,
                      name == String(format: ".generation-%020llu", number) else { throw Failure.unsafeFile }
                let fd = Darwin.openat(directoryDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard fd >= 0 else { throw Failure.unsafeFile }
                var info = stat(); var bytes = [UInt8](repeating: 0, count: name.utf8.count + 1)
                let n = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
                let status = Darwin.fstat(fd, &info); Darwin.close(fd)
                guard status == 0, info.st_mode & S_IFMT == S_IFREG,
                      n == name.utf8.count, Data(bytes.prefix(n)) == Data(name.utf8) else { throw Failure.unsafeFile }
                values.append(number)
            }
            errno = 0
        }
        guard errno == 0 else { throw Failure.syscall("list generation", errno) }
        let sorted = values.sorted()
        for (offset, value) in sorted.enumerated() {
            guard value == UInt64(offset) + 1 else { throw Failure.unsafeFile }
        }
        return sorted.last ?? 0
    }
    func release() {
        guard active else { return }
        active = false
        if lockDescriptor >= 0 {
            _ = archive_flock(lockDescriptor, LOCK_UN)
            Darwin.close(lockDescriptor)
        }
        Darwin.close(directoryDescriptor)
    }
    deinit { release() }
    // NEVER unlink the lock file: that would allow a second inode/parallel lock.

    private static func safeComponentName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    /// Strict unresolved-recovery-transaction admission (#245 lane 2 shim), the SAME
    /// rule as the app-side DiskArchiveRecoveryJournal.transactions(): every "txn-"
    /// entry must be exactly "txn-<canonical UUID>", any malformed name refuses the
    /// whole check, and the admitted ids come back sorted. Runs under the caller's
    /// held shared-gate flock (nested mode); the lease itself flocks nothing.
    func unresolvedTransactionIDs() throws -> [UUID] {
        try validate()
        return try listNames().filter { $0.hasPrefix("txn-") }.map {
            let suffix = String($0.dropFirst(4))
            guard let id = UUID(uuidString: suffix), id.uuidString == suffix else { throw Failure.unsafeFile }
            return id
        }.sorted { $0.uuidString < $1.uuidString }
    }

    func hasUnresolvedTransactions() throws -> Bool { try !unresolvedTransactionIDs().isEmpty }

    /// Same POSIX directory walk as the generation-chain read (dup + fdopendir +
    /// readdir over the lease's directory descriptor).
    private func listNames() throws -> [String] {
        let duplicate = Darwin.dup(directoryDescriptor)
        guard duplicate >= 0 else { throw Failure.syscall("dup directory", errno) }
        guard let stream = Darwin.fdopendir(duplicate) else { Darwin.close(duplicate); throw Failure.unsafeFile }
        defer { Darwin.closedir(stream) }
        Darwin.rewinddir(stream)
        var result: [String] = []
        errno = 0
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw Failure.syscall("read directory", errno) }
        return result
    }
}

/// Thrown when a covered write is refused because an archive recovery transaction
/// is still unresolved. Mirrors the app-side ArchiveNestedLeaseFailure.
enum SharedArchiveAdmissionError: LocalizedError {
    /// An unresolved archive recovery transaction exists: startup recovery must
    /// complete it before any further covered writer effect may run.
    case unresolvedRecoveryTransaction

    var errorDescription: String? {
        switch self {
        case .unresolvedRecoveryTransaction: "A previous archive operation is still being recovered. New changes are paused until startup recovery finishes."
        }
    }
}

/// Per-effect nested archive unit for extension writers: SAME implementation as the
/// app-side ArchiveNestedGenerationBoundary.withNestedLease, without the app-only
/// MainActor tie. Acquires a nested (no-flock) lease, validates the generation
/// chain, refuses while any recovery transaction is unresolved, runs the covered
/// unit, commits exactly one generation on success, and releases. The caller's
/// held shared writer-gate flock is the mutual exclusion; this never opens or
/// flocks any lock file. A throwing work commits nothing.
enum SharedArchiveNestedUnit {
    static func run<T>(directory: URL, _ work: () throws -> T) throws -> T {
        let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
        defer { lease.release() }
        try lease.validate()
        // An unresolved recovery transaction blocks every covered writer effect until
        // startup recovery completes it: writing over it would fork the generation chain
        // and corrupt the record's storeGeneration evidence.
        guard try !lease.hasUnresolvedTransactions() else {
            throw SharedArchiveAdmissionError.unresolvedRecoveryTransaction
        }
        let result = try work()
        try lease.commitGeneration(lease.generation + 1)
        return result
    }
}
