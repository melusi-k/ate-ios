import Foundation
import Darwin

/// Minimal owner/generation control, separate from eraseable personal SyncMeta.
/// Candidate only: central must supply the real shared control directory and serialize
/// every operation under the same cross-process gate. No default-directory fallback.
struct AccountGenerationReceiptStore {
    enum Error: Swift.Error { case unsafePath, corruptReceipt, writeFailed, durabilityUnverified }
    let directory: URL
    private var file: URL { directory.appendingPathComponent("account-generation-v1.json") }

    init(directory: URL) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              directory.standardizedFileURL == directory else { throw Error.unsafePath }
        self.directory = directory
    }

    /// The real gate owns immutable ancestor provisioning. This verifies the immediate
    /// parent before absence can mean a first-generation receipt.
    private func validateParent() throws {
        var metadata = stat()
        guard lstat(directory.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR else { throw Error.unsafePath }
    }

    func read() throws -> AccountGenerationPolicy.Receipt? {
        try validateParent()
        var metadata = stat()
        guard lstat(file.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw Error.corruptReceipt
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw Error.unsafePath }
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink == false, values.isRegularFile == true else { throw Error.unsafePath }
        guard let receipt = try? JSONDecoder().decode(AccountGenerationPolicy.Receipt.self,
                                                       from: Data(contentsOf: file)),
              !receipt.ownerID.isEmpty, receipt.generation >= 0 else { throw Error.corruptReceipt }
        return receipt
    }

    /// Caller holds the reset writer gate and still-retained reset control throughout.
    /// Strict file+directory sync and decoded readback, never UserDefaults try?-success.
    func save(_ receipt: AccountGenerationPolicy.Receipt) throws {
        guard !receipt.ownerID.isEmpty, receipt.generation >= 0 else { throw Error.corruptReceipt }
        // Never repair corrupt or symbolic-link control as a side effect of saving.
        // The real gate must stay held across this read and replacement.
        _ = try read()
        let fm = FileManager.default
        // The parent control directory is provisioned by the shared gate. Creating it
        // here without syncing its ancestors would overstate durable creation.
        let dirValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard dirValues.isDirectory == true, dirValues.isSymbolicLink == false else { throw Error.unsafePath }
        let bytes = try JSONEncoder().encode(receipt)
        let temp = directory.appendingPathComponent(".generation-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Error.writeFailed }
        var renamed = false
        defer { close(fd); if !renamed { try? fm.removeItem(at: temp) } }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Error.writeFailed }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Error.writeFailed }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw Error.durabilityUnverified }
        guard rename(temp.path, file.path) == 0 else { throw Error.writeFailed }
        renamed = true
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else { throw Error.durabilityUnverified }
        defer { close(dir) }
        guard fsync(dir) == 0 else { throw Error.durabilityUnverified }
        guard try read() == receipt else { throw Error.durabilityUnverified }
    }
}
