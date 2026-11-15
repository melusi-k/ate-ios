import Foundation
import Darwin

/// Nonpersonal cross-process ledger for OS submissions which can outlive a writer
/// effect. Begin while holding the writer flock, then release it before awaiting
/// the OS. Account reset refuses while ANY token exists. A crashed process leaves
/// an honest unresolved submission, never a falsely successful account erase.
enum SharedNotificationSubmission {
    enum Failure: Error { case unsafePath, unresolved }
    static let prefix = "os-notification-inflight-"
    struct Token {
        let directory: URL
        let file: URL
        func finish() throws {
            try validateDirectory(directory)
            var metadata = stat()
            guard lstat(file.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else { throw Failure.unsafePath }
            try FileManager.default.removeItem(at: file)
        }
    }
    private static func validateDirectory(_ directory: URL) throws {
        var metadata = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              directory.resolvingSymlinksInPath() == directory,
              lstat(directory.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR else { throw Failure.unsafePath }
    }
    /// Must be called under the original writer's held effect.
    static func begin(directory: URL) throws -> Token {
        try requireDrained(directory: directory)
        let file = directory.appendingPathComponent(prefix + UUID().uuidString)
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.unsafePath }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw Failure.unsafePath }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.unsafePath }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw Failure.unsafePath }
        return Token(directory: directory, file: file)
    }
    /// Caller holds the reset flock, so no new token can appear before cleanup.
    static func requireDrained(directory: URL) throws {
        try validateDirectory(directory)
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy({ !$0.hasPrefix(prefix) }) else { throw Failure.unresolved }
    }
}
