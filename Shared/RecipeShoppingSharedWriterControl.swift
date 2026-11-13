import Foundation
import Darwin

/// Dormant standalone shared-write fence. Every method requires the caller's SAME
/// control-directory writer flock. Contains only an epoch, never owner/personal data.
/// Marker publication is app-only after snapshot admission, replay and raw validation.
struct RecipeShoppingSharedWriterControl {
    enum Refusal: Error { case unsafePath, notReady, unresolvedCommit, durabilityUnverified }
    static let commitDirectoryName = "RecipeShoppingSyncCommit"
    private let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        try validateDirectory(directory)
    }
    var commitDirectory: URL { directory.appendingPathComponent(Self.commitDirectoryName) }
    private var readyFile: URL { directory.appendingPathComponent("recipe-shopping-ready-v1") }
    private var tempFile: URL { readyFile.appendingPathExtension("tmp") }
    private func validateDirectory(_ url: URL) throws {
        var st = stat()
        guard url.isFileURL, url.standardizedFileURL == url,
              url.resolvingSymlinksInPath().standardizedFileURL == url,
              lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { throw Refusal.unsafePath }
    }
    private func read(_ url: URL) throws -> Data? {
        try validateDirectory(directory)
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            if errno == ENOENT { return nil }
            throw Refusal.unsafePath
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw Refusal.unsafePath }
        return try Data(contentsOf: url)
    }
    private func epoch(_ url: URL) throws -> UUID? {
        guard let bytes = try read(url) else { return nil }
        guard let text = String(data: bytes, encoding: .utf8), let value = UUID(uuidString: text) else { throw Refusal.notReady }
        return value
    }
    func requireNoPendingCommit() throws {
        try validateDirectory(commitDirectory)
        for name in ["pending-v1.json", "pending-v1.json.tmp", "metadata-v1.json.tmp"] {
            var st = stat()
            let path = commitDirectory.appendingPathComponent(name).path
            guard lstat(path, &st) != 0 else { throw Refusal.unresolvedCommit }
            guard errno == ENOENT else { throw Refusal.unresolvedCommit }
        }
    }
    func requireReady(epoch expected: UUID) throws {
        guard try epoch(directory.appendingPathComponent(SharedWriterControl.epochFileName)) == expected,
              try epoch(readyFile) == expected, try read(tempFile) == nil else { throw Refusal.notReady }
        try requireNoPendingCommit()
    }
    /// Caller must have verified admission/replay/raw inventory under this flock.
    /// Old valid marker can be replaced for a new epoch. Unknown/corrupt/temp
    /// evidence refuses. Failures retain evidence and never fall back to legacy.
    func publishReady(epoch expected: UUID) throws {
        guard try epoch(directory.appendingPathComponent(SharedWriterControl.epochFileName)) == expected,
              try read(tempFile) == nil else { throw Refusal.notReady }
        _ = try epoch(readyFile)
        try requireNoPendingCommit()
        let bytes = Data(expected.uuidString.utf8)
        let fd = open(tempFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Refusal.durabilityUnverified }
        defer { close(fd) }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Refusal.durabilityUnverified }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Refusal.durabilityUnverified }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(tempFile.path, readyFile.path) == 0 else { throw Refusal.durabilityUnverified }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Refusal.durabilityUnverified }
        defer { close(parent) }
        guard fsync(parent) == 0, try read(readyFile) == bytes else { throw Refusal.durabilityUnverified }
    }

    /// Explicit standalone extension route. No Food Journal/archive activation.
    /// Same strict reset reader/flock/epoch as the app; ready and redo checks run
    /// inside EACH effect, never only once at construction. No marker creation.
    static func makeExtensionBoundary(directory: URL) throws -> SharedWriterBoundary {
        let control = try Self(directory: directory)
        let gate = try SharedFileWriterGate(directory: directory,
            resetPending: { try SharedResetControl.exists(directory: directory) }, archive: .none)
        let lease = try gate.captureEpoch()
        // Admission can still be pending at construction: refuse effects until it
        // is ready. A caller cannot silently refresh this retained lease later.
        return SharedWriterBoundary { work in
            try gate.withWriterEffect(lease) {
                try control.requireReady(epoch: lease)
                try work()
            }
        }
    }
}
