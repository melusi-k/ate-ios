import Foundation
import Darwin

/// Local-store identity for interrupted archive ownership, not an account or email.
/// The caller holds the common writer gate over load/create and archive recovery.
/// This minimal control survives logout and personal-data cleanup.
struct JournalLocalOwnerIdentity {
    enum Failure: Error { case unsafePath, unreadableIdentity, durabilityUnverified }
    static let filename = "journal-local-owner-v1"

    static func loadOrCreate(in directory: URL) throws -> String {
        guard directory.isFileURL, directory.standardizedFileURL == directory else { throw Failure.unsafePath }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.unsafePath }
        defer { close(parent) }

        func read() throws -> String? {
            let fd = openat(parent, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else {
                if errno == ENOENT { return nil }
                throw Failure.unreadableIdentity
            }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_nlink == 1, info.st_size == 36 else { throw Failure.unreadableIdentity }
            var bytes = [UInt8](repeating: 0, count: 37)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard count == 36, let text = String(bytes: bytes.prefix(count), encoding: .utf8),
                  let uuid = UUID(uuidString: text), uuid.uuidString == text else { throw Failure.unreadableIdentity }
            return text
        }
        if let existing = try read() { return existing }
        let identity = UUID().uuidString
        let temporary = ".journal-local-owner-\(UUID().uuidString).tmp"
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.durabilityUnverified }
        var renamed = false
        defer {
            close(fd)
            if !renamed { unlinkat(parent, temporary, 0) }
        }
        let bytes = Data(identity.utf8)
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.durabilityUnverified }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              renameat(parent, temporary, parent, filename) == 0 else { throw Failure.durabilityUnverified }
        renamed = true
        guard fsync(parent) == 0, try read() == identity else { throw Failure.durabilityUnverified }
        return identity
    }
}
