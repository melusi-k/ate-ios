import Foundation
import Darwin
import CryptoKit

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
            guard JournalArchiveValidation.safeMediaName(lockName) else { throw Failure.invalidDirectory }
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
}

struct ArchiveRecoveryImage: Codable, Equatable {
    /// Stable registered component name, NOT a file path or executable instruction.
    let component: String
    /// Exact raw before-image. nil means absent, not encoded empty.
    let before: Data?
    let after: Data?
}
struct ArchiveRecoveryRecord: Codable, Equatable {
    let version: Int
    let transactionID: UUID
    let ownerIdentity: String
    let storeGeneration: UInt64
    let images: [ArchiveRecoveryImage]
    /// Complete Journal insertion values, plus owned media receipts/bytes, supplied
    /// by composition BEFORE any durable store mutation. This is not a log message.
    let journalAndMediaRecovery: Data
}

enum ArchiveRecoveryPhase: String, Codable, CaseIterable {
    case prepared = "00-prepared"
    case applying = "01-applying"
    case committed = "02-committed"
    case compensating = "03-compensating"
    case rolledBack = "04-rolled-back"
}

/// Immutable record plus monotonic, exclusively created phase files. No in-place
/// phase replacement, so a torn marker cannot overwrite the only prior state.
final class DiskArchiveRecoveryJournal {
    enum Failure: Error { case invalidRecord, missingPrepared, invalidPhase, integrity, tooLarge, syscall(String, Int32) }
    private struct Envelope: Codable { let bytes: Data; let sha256: String }
    let lease: POSIXArchiveWriterLease
    private let maxBytes: Int
    init(lease: POSIXArchiveWriterLease, maximumRecordBytes: Int = 512 * 1024 * 1024) {
        self.lease = lease; maxBytes = maximumRecordBytes
    }

    func prepare(_ record: ArchiveRecoveryRecord) throws {
        try lease.validate()
        guard record.version == 1, !record.ownerIdentity.isEmpty, record.storeGeneration == lease.generation,
              !record.journalAndMediaRecovery.isEmpty,
              Set(record.images.map(\.component)).count == record.images.count,
              record.images.allSatisfy({ !$0.component.isEmpty }) else { throw Failure.invalidRecord }
        // An unresolved prior transaction blocks every new restore/write.
        guard try transactions().isEmpty else { throw Failure.invalidPhase }
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= maxBytes else { throw Failure.tooLarge }
        let envelope = try JSONEncoder().encode(Envelope(bytes: bytes, sha256: digest(bytes)))
        let name = "txn-" + record.transactionID.uuidString
        guard Darwin.mkdirat(lease.directoryDescriptor, name, mode_t(0o700)) == 0 else { throw Failure.syscall("create transaction", errno) }
        let dir = try openDirectory(name); defer { Darwin.close(dir) }
        // If any write/sync fails, directory is retained and startup blocks visibly.
        try writeExclusive(envelope, directory: dir, name: "record.json")
        try sync(dir)
        try writeExclusive(Data(record.transactionID.uuidString.utf8), directory: dir, name: ArchiveRecoveryPhase.prepared.rawValue)
        try sync(dir); try sync(lease.directoryDescriptor)
    }

    func transition(_ id: UUID, to next: ArchiveRecoveryPhase) throws {
        try lease.validate()
        let current = try phase(id)
        guard (current == .prepared && (next == .applying || next == .compensating)) ||
              (current == .applying && (next == .committed || next == .compensating)) ||
              (current == .committed && next == .compensating) ||
              (current == .compensating && next == .rolledBack) else { throw Failure.invalidPhase }
        let dir = try openDirectory("txn-" + id.uuidString); defer { Darwin.close(dir) }
        try writeExclusive(Data(id.uuidString.utf8), directory: dir, name: next.rawValue)
        try sync(dir); try sync(lease.directoryDescriptor)
    }

    func transactions() throws -> [UUID] {
        try lease.validate()
        return try names(directory: lease.directoryDescriptor).filter { $0.hasPrefix("txn-") }.map {
            let suffix = String($0.dropFirst(4))
            guard let id = UUID(uuidString: suffix), id.uuidString == suffix else { throw Failure.invalidRecord }
            return id
        }.sorted { $0.uuidString < $1.uuidString }
    }

    func read(_ id: UUID) throws -> ArchiveRecoveryRecord {
        let dir = try openDirectory("txn-" + id.uuidString); defer { Darwin.close(dir) }
        let data = try readFile(directory: dir, name: "record.json", limit: maxBytes * 2)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.bytes.count <= maxBytes, digest(envelope.bytes) == envelope.sha256 else { throw Failure.integrity }
        let record = try JSONDecoder().decode(ArchiveRecoveryRecord.self, from: envelope.bytes)
        guard record.transactionID == id, record.version == 1 else { throw Failure.invalidRecord }
        return record
    }

    struct ValidatedHistory {
        let phase: ArchiveRecoveryPhase
        /// Validated historical marker, even when compensating/rolledBack wins.
        let hasCommittedMarker: Bool
    }

    func phase(_ id: UUID) throws -> ArchiveRecoveryPhase { try history(id).phase }

    func history(_ id: UUID) throws -> ValidatedHistory {
        let dir = try openDirectory("txn-" + id.uuidString); defer { Darwin.close(dir) }
        let files = Set(try names(directory: dir))
        let allowed = Set(["record.json"] + ArchiveRecoveryPhase.allCases.map(\.rawValue))
        guard files.isSubset(of: allowed), files.contains("record.json"), files.contains(ArchiveRecoveryPhase.prepared.rawValue) else {
            throw Failure.missingPrepared
        }
        for phase in ArchiveRecoveryPhase.allCases where files.contains(phase.rawValue) {
            guard try readFile(directory: dir, name: phase.rawValue, limit: 36) == Data(id.uuidString.utf8) else { throw Failure.integrity }
        }
        let applying = files.contains(ArchiveRecoveryPhase.applying.rawValue)
        let committed = files.contains(ArchiveRecoveryPhase.committed.rawValue)
        let rolledBack = files.contains(ArchiveRecoveryPhase.rolledBack.rawValue)
        let compensating = files.contains(ArchiveRecoveryPhase.compensating.rawValue)
        guard !committed || applying, !rolledBack || compensating else { throw Failure.invalidPhase }
        let phase: ArchiveRecoveryPhase = rolledBack ? .rolledBack : compensating ? .compensating : committed ? .committed : applying ? .applying : .prepared
        return ValidatedHistory(phase: phase, hasCommittedMarker: committed)
    }

    /// Terminal evidence is deliberately RETAINED here. Destructive journal cleanup
    /// needs an atomic retirement protocol; no half-deleted journal is treated as safe.
    /// Integration may move completed records to a separately synced history directory.
    func retire(_ id: UUID) throws {
        let status = try phase(id)
        guard status == .committed || status == .rolledBack else { throw Failure.invalidPhase }
        // Atomic namespace retirement; retain immutable evidence, never half-delete.
        let destination = ".resolved-" + id.uuidString
        var info = stat()
        guard Darwin.fstatat(lease.directoryDescriptor, destination, &info, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw Failure.invalidPhase }
        try lease.validate()
        guard Darwin.renameat(lease.directoryDescriptor, "txn-" + id.uuidString, lease.directoryDescriptor, destination) == 0 else {
            throw Failure.syscall("retire recovery record", errno)
        }
        try sync(lease.directoryDescriptor)
    }
    func hasUnresolvedTransactions() throws -> Bool { !(try transactions()).isEmpty }

    private func openDirectory(_ name: String) throws -> Int32 {
        try lease.validate()
        let fd = Darwin.openat(lease.directoryDescriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.syscall("open transaction", errno) }
        return fd
    }
    private func names(directory: Int32) throws -> [String] {
        let duplicate = Darwin.dup(directory)
        guard duplicate >= 0 else { throw Failure.syscall("dup directory", errno) }
        guard let stream = Darwin.fdopendir(duplicate) else { Darwin.close(duplicate); throw Failure.syscall("list directory", errno) }
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
    private func writeExclusive(_ bytes: Data, directory: Int32, name: String) throws {
        let fd = Darwin.openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure.syscall("create recovery file", errno) }
        defer { Darwin.close(fd) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw Failure.syscall("write recovery", errno) }
                offset += n
            }
        }
        try sync(fd)
    }
    private func readFile(directory: Int32, name: String, limit: Int) throws -> Data {
        let fd = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.syscall("open recovery file", errno) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else { throw Failure.tooLarge }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n >= 0 else { throw Failure.syscall("read recovery", errno) }
            if n == 0 { return result }
            guard n <= limit - result.count else { throw Failure.tooLarge }
            result.append(contentsOf: buffer.prefix(n))
        }
    }
    private func sync(_ fd: Int32) throws {
        guard Darwin.fsync(fd) == 0 else { throw Failure.syscall("sync recovery", errno) }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
