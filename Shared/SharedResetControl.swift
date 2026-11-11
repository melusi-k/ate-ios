import Foundation
import Darwin

/// Errors from the shared strict reset-control reader. Mirrors the app-side
/// ClearAllControlError cases this reader can raise.
enum SharedResetControlError: Error, Equatable {
    case persistenceUnverified, corruptRecord
}

/// Strict reset-control existence reader for extension writers (#245, lane 2
/// Shared shim): SAME implementation as the app-side
/// FileResetControlPersistence.read, read-only. The directory and its ancestors
/// are provisioned immutable before startup; a missing file is absent, a present
/// but non-regular or unreadable record REFUSES (never treated as absent), and
/// there is no UserDefaults cache, missing-directory-as-nil, or app-group
/// fallback. Writes and removals stay app-side, serialized by the account gate.
enum SharedResetControl {
    /// Same file name as the app-side FileResetControlPersistence.
    static let fileName = "reset-control-v1.json"

    static func read(directory: URL) throws -> Data? {
        var metadata = stat()
        guard directory.isFileURL, directory.standardizedFileURL == directory,
              lstat(directory.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR else { throw SharedResetControlError.persistenceUnverified }
        let file = directory.appendingPathComponent(fileName)
        guard lstat(file.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw SharedResetControlError.corruptRecord
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw SharedResetControlError.corruptRecord }
        // Present but unreadable refuses: a failed read propagates, never absent.
        return try Data(contentsOf: file)
    }

    /// True only when a readable control record exists. Any doubt throws.
    static func exists(directory: URL) throws -> Bool {
        try read(directory: directory) != nil
    }
}
