import Foundation
import CryptoKit
import Darwin

/// Candidate POSIX adapter for Apple platforms. No production call sites.
/// Uses pinned directory descriptors and same-volume hard links, never rename-overwrite.
/// Serialized cooperative ownership is REQUIRED across app/extension writers.
/// It is not a security boundary against a hostile process running with this app's UID.
@MainActor
final class JournalArchiveFilesystemMedia: ArchiveMediaTransaction {
    enum Boundary: Equatable { case beforeWrite, afterWrite, beforeLink, afterLink, beforeReadback, beforeRemove }
    enum Failure: Error { case syscall(String, Int32), unsafeName, wrongType, changedFile, mismatch, invalidState }
    private struct Identity: Equatable, Codable { let device: UInt64; let inode: UInt64 }
    private struct Receipt: Codable { let version: Int; let names: [String]; let identities: [String: Identity] }
    private let root: Int32
    private var staging: Int32 = -1
    private var stageName: String?
    private var expected: [String: Data] = [:]
    private var owned: [String: Identity] = [:]
    private var published: Set<String> = []
    private let receiptName = ".receipt-" + UUID().uuidString + ".json"
    private var staged = false
    private var finished = false
    private let checkpoint: (Boundary, String) throws -> Void
    private let validateLease: () throws -> Void

    /// The destination directory must already exist. Walk every absolute-path component
    /// using O_NOFOLLOW; a symbolic-link ancestor or destination is a visible failure.
    init(directory: URL, validateLease: @escaping () throws -> Void = {}, checkpoint: @escaping (Boundary, String) throws -> Void = { _, _ in }) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw Failure.wrongType }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.syscall("open root", errno) }
        do {
            for part in directory.path.split(separator: "/") {
                guard part != ".", part != ".." else { throw Failure.unsafeName }
                let next = Darwin.openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard next >= 0 else { throw Failure.syscall("open directory", errno) }
                Darwin.close(fd); fd = next
            }
        } catch { Darwin.close(fd); throw error }
        root = fd
        self.checkpoint = checkpoint
        self.validateLease = validateLease
    }

    deinit {
        // Never silently erase recovery evidence during deinit.
        if staging >= 0 { Darwin.close(staging) }
        Darwin.close(root)
    }

    func stage(_ media: [String: Data]) throws {
        guard !staged, stageName == nil, !finished else { throw Failure.invalidState }
        guard media[receiptName] == nil, media.keys.allSatisfy(JournalArchiveValidation.safeMediaName) else { throw Failure.unsafeName }
        expected = media
        let name = ".ate-restore-" + UUID().uuidString
        try validateLease()
        guard Darwin.mkdirat(root, name, mode_t(0o700)) == 0 else { throw Failure.syscall("mkdir staging", errno) }
        stageName = name
        staging = Darwin.openat(root, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard staging >= 0 else { throw Failure.syscall("open staging", errno) }
        for name in media.keys.sorted() {
            try checkpoint(.beforeWrite, name)
            try validateLease()
            let fd = Darwin.openat(staging, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw Failure.syscall("create staged file", errno) }
            // Record identity before a possibly partial write so rollback owns the partial file.
            do {
                owned[name] = try identity(fd)
                try validateLease()
                try writeAll(media[name]!, fd: fd)
                guard Darwin.fsync(fd) == 0 else { throw Failure.syscall("sync staged file", errno) }
                Darwin.close(fd)
            } catch { Darwin.close(fd); throw error }
            try checkpoint(.afterWrite, name)
        }
        // Write receipt BEFORE publication. linkat preserves the recorded inode identity.
        let receipt = try JSONEncoder().encode(Receipt(version: 1, names: media.keys.sorted(), identities: owned))
        try validateLease()
        let fd = Darwin.openat(staging, receiptName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Failure.syscall("create receipt", errno) }
        do {
            try validateLease()
            try writeAll(receipt, fd: fd)
            guard Darwin.fsync(fd) == 0 else { throw Failure.syscall("sync receipt", errno) }
            Darwin.close(fd)
        } catch { Darwin.close(fd); throw error }
        try syncDirectories()
        staged = true
    }

    func publish() throws {
        guard staged, !finished else { throw Failure.invalidState }
        for name in expected.keys.sorted() {
            try checkpoint(.beforeLink, name)
            try requireIdentity(name, at: staging)
            // linkat fails EEXIST on ANY existing destination, including symlinks.
            // Never use rename(), replaceItemAt(), or remove a conflicting destination.
            try validateLease()
            guard Darwin.linkat(staging, name, root, name, 0) == 0 else { throw Failure.syscall("publish exclusive link", errno) }
            published.insert(name) // record before any later checkpoint can throw.
            try checkpoint(.afterLink, name)
        }
        try syncDirectories()
    }

    func verify() throws {
        try validateLease()
        guard staged, !finished else { throw Failure.invalidState }
        for name in expected.keys.sorted() {
            try checkpoint(.beforeReadback, name)
            let fd = Darwin.openat(root, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard fd >= 0 else { throw Failure.syscall("read published file", errno) }
            do {
                guard try identity(fd) == owned[name] else { throw Failure.changedFile }
                let actual = try readAll(fd, limit: expected[name]!.count)
                guard actual == expected[name],
                      SHA256.hash(data: actual) == SHA256.hash(data: expected[name]!) else { throw Failure.mismatch }
                Darwin.close(fd)
            } catch { Darwin.close(fd); throw error }
        }
    }

    func rollback() throws {
        var failures: [String] = []
        for name in published.sorted() {
            do { try removeOwned(name, at: root); published.remove(name) }
            catch { failures.append("destination \(name): \(error)") }
        }
        // Do not erase recovery receipts if any destination ownership/cleanup is unresolved.
        if failures.isEmpty {
            do { try cleanStage() } catch { failures.append("staging: \(error)") }
        }
        if !failures.isEmpty { throw ArchiveRestoreFailure.recoveryRequired(original: "media rollback", compensationFailures: failures) }
        try syncDirectories()
    }

    func finish() throws {
        guard staged, !finished else { throw Failure.invalidState }
        try verify()
        try cleanStage()
        guard Darwin.fsync(root) == 0 else { throw Failure.syscall("sync completed directory", errno) }
        finished = true
    }

    private func cleanStage() throws {
        guard let name = stageName else { return }
        guard staging >= 0 else { throw Failure.invalidState }
        for file in owned.keys.sorted() { try removeOwned(file, at: staging) }
        // Receipt is exclusively created inside the private pinned staging directory.
        try validateLease()
        if Darwin.unlinkat(staging, receiptName, 0) != 0, errno != ENOENT {
            throw Failure.syscall("remove receipt", errno)
        }
        guard Darwin.fsync(staging) == 0 else { throw Failure.syscall("sync emptied staging", errno) }
        try validateLease()
        guard Darwin.unlinkat(root, name, AT_REMOVEDIR) == 0 else { throw Failure.syscall("remove staging directory", errno) }
        Darwin.close(staging); staging = -1; stageName = nil
    }

    private func removeOwned(_ name: String, at directory: Int32) throws {
        try validateLease()
        try checkpoint(.beforeRemove, name)
        var info = stat()
        if Darwin.fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw Failure.syscall("stat owned file", errno)
        }
        guard info.st_mode & S_IFMT == S_IFREG,
              Identity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(truncatingIfNeeded: info.st_ino)) == owned[name] else { throw Failure.changedFile }
        // POSIX has no unlink-if-inode-matches. The serialized app/extension writer
        // lease must cover this check+unlink interval. Do not claim hostile-UID safety.
        try validateLease()
        guard Darwin.unlinkat(directory, name, 0) == 0 else { throw Failure.syscall("remove owned file", errno) }
    }

    private func requireIdentity(_ name: String, at directory: Int32) throws {
        let fd = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.syscall("open owned file", errno) }
        defer { Darwin.close(fd) }
        guard try identity(fd) == owned[name] else { throw Failure.changedFile }
    }

    private func identity(_ fd: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else { throw Failure.syscall("fstat", errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.wrongType }
        return Identity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(truncatingIfNeeded: info.st_ino))
    }

    private func syncDirectories() throws {
        if staging >= 0, Darwin.fsync(staging) != 0 { throw Failure.syscall("sync staging directory", errno) }
        guard Darwin.fsync(root) == 0 else { throw Failure.syscall("sync media directory", errno) }
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try validateLease()
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Failure.syscall("write bytes", errno) }
                offset += count
            }
        }
    }

    private func readAll(_ fd: Int32, limit: Int) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(fd, raw.baseAddress!, raw.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw Failure.syscall("read bytes", errno) }
            if count == 0 { return result }
            guard count <= limit - result.count else { throw Failure.mismatch }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
