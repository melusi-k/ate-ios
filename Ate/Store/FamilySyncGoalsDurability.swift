import Foundation
import Darwin

protocol FamilySyncGoalsFileStorage: NutritionGoalsStorage {
    var fileURL: URL { get }
}

extension FileNutritionGoalsStorage: FamilySyncGoalsFileStorage {}

/// Seals the repository's goals target before a family intent can retire. Atomic
/// replacement alone is not a durability guarantee. This step writes and syncs a
/// fresh file, renames it, syncs the parent, and checks the exact resulting target.
/// Empty goals are a deletion, including a synced parent-directory entry.
struct FamilySyncGoalsDurability {
    enum Step { case beforeWrite, beforeReadback, beforeDirectorySync }
    enum Failure: Error { case unsafePath, targetChanged, durabilityUnverified }
    let fileURL: URL
    var checkpoint: (Step) throws -> Void = { _ in }

    func seal(_ target: DailyNutritionGoals) throws {
        let parent = fileURL.deletingLastPathComponent()
        var st = stat()
        guard fileURL.isFileURL, fileURL.standardizedFileURL == fileURL,
              lstat(parent.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            throw Failure.unsafePath
        }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw Failure.unsafePath }
        defer { close(parentFD) }
        func readTarget() throws -> Data? {
            var info = stat()
            guard lstat(fileURL.path, &info) == 0 else {
                if errno == ENOENT { return nil }
                throw Failure.durabilityUnverified
            }
            guard (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.unsafePath }
            return try Data(contentsOf: fileURL)
        }
        let existing = try readTarget()
        if target.isEmpty {
            guard existing == nil else { throw Failure.targetChanged }
        } else {
            guard let existing,
                  try JSONDecoder().decode(DailyNutritionGoals.self, from: existing) == target else {
                throw Failure.targetChanged
            }
        }
        try checkpoint(.beforeWrite)
        if target.isEmpty {
            // Idempotent delete under the same writer boundary as repository.save.
            guard unlink(fileURL.path) == 0 || errno == ENOENT else {
                throw Failure.durabilityUnverified
            }
        } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(target)
            let temp = parent.appendingPathComponent(".family-goals-\(UUID().uuidString).tmp")
            let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw Failure.durabilityUnverified }
            defer { close(fd) }
            try bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { throw Failure.durabilityUnverified }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw Failure.durabilityUnverified }
                    offset += count
                }
            }
            guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
                  rename(temp.path, fileURL.path) == 0 else { throw Failure.durabilityUnverified }
        }
        // The repository already removed an empty target. Syncing this directory is
        // mandatory even when there is no file left to open or sync.
        try checkpoint(.beforeDirectorySync)
        guard fsync(parentFD) == 0 else { throw Failure.durabilityUnverified }
        try checkpoint(.beforeReadback)
        let actual = try readTarget()
        if target.isEmpty {
            guard actual == nil else { throw Failure.targetChanged }
        } else {
            guard let actual,
                  try JSONDecoder().decode(DailyNutritionGoals.self, from: actual) == target else {
                throw Failure.targetChanged
            }
        }
    }
}
