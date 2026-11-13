import Foundation
import Darwin

@_silgen_name("flock")
private func reset_flock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Candidate shared-file gate, NOT installed. All processes must use the SAME existing,
/// immutable app-group control directory and the SAME strict durable control reader.
/// No app-group-to-standard fallback. Every writer effect must use withWriterEffect;
/// validate alone is only a post-await stale-result check, never effect authorization.
@MainActor
final class AccountWriterGate: ClearAllWriterGating {
    enum Error: Swift.Error { case unsafePath, busy, corruptEpoch, persistenceUnverified, resetPending, staleLease }
    private let directory: URL
    private let resetControlExists: () throws -> Bool
    private var resetFD: Int32?
    private var resetEpoch: UUID?
    private var activeEffectLease: UUID?

    init(directory: URL, resetControlExists: @escaping () throws -> Bool) throws {
        guard directory.isFileURL, directory.standardizedFileURL == directory else { throw Error.unsafePath }
        self.directory = directory
        self.resetControlExists = resetControlExists
        try validateDirectory()
    }
    deinit {
        // Deinitialization performs only nonisolated OS fd cleanup. It must not leave
        // a reset lock owned until process exit when an active attempt is abandoned.
        if let fd = resetFD { _ = reset_flock(fd, LOCK_UN); close(fd) }
    }
    private var epochFile: URL { directory.appendingPathComponent("writer-epoch-v1") }
    private func validateDirectory() throws {
        var metadata = stat()
        guard lstat(directory.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR else { throw Error.unsafePath }
    }
    private func lock() throws -> Int32 {
        try validateDirectory()
        let file = directory.appendingPathComponent("writer-gate-v1.lock")
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Error.unsafePath }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else {
            close(fd); throw Error.unsafePath
        }
        guard reset_flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw Error.busy }
        return fd
    }
    private func unlock(_ fd: Int32) { _ = reset_flock(fd, LOCK_UN); close(fd) }
    private func readEpoch() throws -> UUID? {
        var metadata = stat()
        guard lstat(epochFile.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw Error.corruptEpoch
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              let text = String(data: try Data(contentsOf: epochFile), encoding: .utf8),
              let epoch = UUID(uuidString: text) else { throw Error.corruptEpoch }
        return epoch
    }
    private func saveEpoch(_ epoch: UUID) throws {
        _ = try readEpoch() // never silently repair corrupt control
        let file = directory.appendingPathComponent(".writer-epoch-\(UUID().uuidString).tmp")
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Error.persistenceUnverified }
        var renamed = false
        defer { close(fd); if !renamed { try? FileManager.default.removeItem(at: file) } }
        let bytes = Data(epoch.uuidString.utf8)
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Error.persistenceUnverified }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Error.persistenceUnverified }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(file.path, epochFile.path) == 0 else { throw Error.persistenceUnverified }
        renamed = true
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Error.persistenceUnverified }
        defer { close(parent) }
        guard fsync(parent) == 0, try readEpoch() == epoch else { throw Error.persistenceUnverified }
    }
    func captureWriter() throws -> UUID {
        guard resetFD == nil else { throw Error.resetPending }
        if let lease = activeEffectLease { return lease }
        let fd = try lock(); defer { unlock(fd) }
        guard try !resetControlExists() else { throw Error.resetPending }
        if let epoch = try readEpoch() { return epoch }
        let epoch = UUID()
        try saveEpoch(epoch)
        return epoch
    }
    func validateWriter(_ lease: UUID) throws {
        try withWriterEffect(lease) {}
    }
    /// No suspension inside effect. Actual disk/in-memory mutation executes while the
    /// same exclusive OS lock excludes reset, with its original captured epoch checked.
    func withWriterEffect<T>(_ lease: UUID, _ effect: () throws -> T) throws -> T {
        guard resetFD == nil else { throw Error.resetPending }
        // MainActor synchronous nesting only. No await/escaping work inside effect.
        if let activeEffectLease {
            guard activeEffectLease == lease else { throw Error.staleLease }
            return try effect()
        }
        let fd = try lock(); defer { unlock(fd) }
        guard try !resetControlExists() else { throw Error.resetPending }
        guard try readEpoch() == lease else { throw Error.staleLease }
        activeEffectLease = lease
        defer { activeEffectLease = nil }
        return try effect()
    }
    func usesControlDirectory(_ candidate: URL) -> Bool { candidate == directory }

    /// Raw startup recovery uses the SAME control root and held account flock.
    /// Ordinary archive admission deliberately refuses unresolved transactions, so
    /// recovery must run before constructing that ordinary boundary.
    func withArchiveRecoveryLease<T>(_ lease: UUID, _ work: (POSIXArchiveWriterLease) throws -> T) throws -> T {
        try withWriterEffect(lease) {
            let archive = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { archive.release() }
            return try work(archive)
        }
    }

    /// Explicit auth lifecycle binding must call this BEFORE a new session graph can
    /// publish. Invalidates same-owner logout/relogin work, not just account switches.
    func invalidateWriters() throws {
        guard resetFD == nil else { throw Error.resetPending }
        let fd = try lock(); defer { unlock(fd) }
        try saveEpoch(UUID())
    }
    func acquireResetGate() throws {
        guard resetFD == nil else { throw Error.busy }
        let fd = try lock()
        do {
            let epoch = UUID()
            try saveEpoch(epoch)
            resetFD = fd
            resetEpoch = epoch
        } catch { unlock(fd); throw error }
    }
    func validateResetGate() throws {
        guard let fd = resetFD, let epoch = resetEpoch,
              fcntl(fd, F_GETFD) >= 0, try readEpoch() == epoch else { throw Error.staleLease }
        try validateDirectory()
    }
    func releaseResetGate() {
        guard let fd = resetFD else { return }
        resetFD = nil; resetEpoch = nil
        unlock(fd)
    }
}
