import Foundation
import Darwin

/// Shared strict reset-control bytes. The same AccountWriterGate must serialize all
/// writes/removals. Directory and ancestors are provisioned immutable before startup.
/// No UserDefaults cache, missing-directory-as-nil, rollback backup or app-group fallback.
struct FileResetControlPersistence: ResetControlPersistence {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("reset-control-v1.json") }
    private func parent() throws {
        var metadata = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              lstat(directory.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR else { throw ClearAllControlError.persistenceUnverified }
    }
    func read() throws -> Data? {
        try parent()
        var metadata = stat()
        guard lstat(file.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw ClearAllControlError.corruptRecord
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw ClearAllControlError.corruptRecord }
        return try Data(contentsOf: file)
    }
    private func syncParent() throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ClearAllControlError.persistenceUnverified }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw ClearAllControlError.persistenceUnverified }
    }
    func write(_ data: Data) throws {
        _ = try read() // rejects missing parent, symlink or inaccessible prior control
        let temp = directory.appendingPathComponent(".reset-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ClearAllControlError.persistenceUnverified }
        var renamed = false
        defer { close(fd); if !renamed { try? FileManager.default.removeItem(at: temp) } }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw ClearAllControlError.persistenceUnverified }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ClearAllControlError.persistenceUnverified }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(temp.path, file.path) == 0 else { throw ClearAllControlError.persistenceUnverified }
        renamed = true
        try syncParent()
        guard try read() == data else { throw ClearAllControlError.persistenceUnverified }
    }
    func remove() throws {
        guard try read() != nil else { return }
        guard unlink(file.path) == 0 else { throw ClearAllControlError.persistenceUnverified }
        try syncParent()
        guard try read() == nil else { throw ClearAllControlError.persistenceUnverified }
    }
}
