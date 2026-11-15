import Foundation
import SwiftData
import CryptoKit

/// Lossless local Journal section for a future versioned Ate archive. Not wired into export/import.
struct JournalArchive: Codable, Equatable {
    static let currentVersion = 1
    var version = Self.currentVersion
    var entries: [JournalArchiveEntry]
    /// Keys are safe existing media basenames, values are the actual file contents, not paths.
    var media: [String: Data]
    var mediaSHA256: [String: String] = [:]
}

struct JournalArchiveEntry: Codable, Equatable {
    var id: String
    var createdAt: Date
    var prompt: String
    var text: String
    var stateRaw: String
    var recipeIDs: [String]
    var journalingSuggestionTitle: String?
    var momentDate: Date?
    var sourceRaw: String
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var mediaFileNames: [String]
    var editedAt: Date?
    var kindRaw: String
    var dayKey: String?
    var recipeSnapshotsRaw: String?
    var meal: NutritionDiaryEntry?
}

enum JournalArchiveError: Error, Equatable {
    case unavailable
    case unsupportedVersion
    case duplicateIdentity
    case invalidMediaName
    case missingMedia
    case invalidMealLink
    case invalidCoordinates
    case archiveTooLarge
    case mediaIntegrity
}

@MainActor
enum JournalArchiveCapture {
    /// Refuse a recovered or fallback store: a fresh replacement isn't the user's complete history.
    /// A later recovery export may explicitly include the moved-aside store under a separate contract.
    private static func capture(journal: JournalStore) throws -> JournalArchive {
        try requireCompleteStore(journal.openState)
        guard let container = journal.container else {
            throw JournalArchiveError.unavailable
        }
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<JournalEntry>())
        let meals = try FoodJournalStore(container: container).readMeals()
        let mealByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id.uuidString, $0) })
        var result = JournalArchive(entries: [], media: [:])
        for row in rows {
            result.entries.append(JournalArchiveEntry(
                id: row.id, createdAt: row.createdAt, prompt: row.prompt, text: row.text,
                stateRaw: row.stateRaw, recipeIDs: row.recipeIDs,
                journalingSuggestionTitle: row.journalingSuggestionTitle, momentDate: row.momentDate,
                sourceRaw: row.sourceRaw, locationName: row.locationName,
                latitude: row.latitude, longitude: row.longitude, mediaFileNames: row.mediaFileNames,
                editedAt: row.editedAt, kindRaw: row.kindRaw, dayKey: row.dayKey,
                recipeSnapshotsRaw: row.recipeSnapshotsRaw, meal: mealByID[row.id]))
        }
        // Sort immutable values after copying managed rows. SortDescriptor key paths
        // are not Sendable under complete concurrency checking in this toolchain.
        result.entries.sort { $0.createdAt < $1.createdAt }
        return result
    }

    static func requireCompleteStore(_ state: JournalOpenState) throws {
        guard case .ok = state else { throw JournalArchiveError.unavailable }
    }

    /// Managed rows are copied on MainActor above; only immutable value data and file URLs
    /// cross to the utility queue. Never block UI while reading a large JournalMedia folder.
    static func captureWithMedia(journal: JournalStore, mediaDirectory: URL? = nil,
                                 maximumMediaBytes: Int = 100 * 1024 * 1024) async throws -> JournalArchive {
        let mediaDirectory = mediaDirectory ?? journal.mediaDirectory
        let snapshot = try capture(journal: journal)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try JournalArchiveMedia.load(snapshot,
                    directory: mediaDirectory, maximumBytes: maximumMediaBytes)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

}

enum JournalArchiveValidation {
    static func safeMediaName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    static func validate(_ archive: JournalArchive, maximumMediaBytes: Int = 100 * 1024 * 1024) throws {
        guard maximumMediaBytes >= 0 else { throw JournalArchiveError.archiveTooLarge }
        guard archive.version == JournalArchive.currentVersion else { throw JournalArchiveError.unsupportedVersion }
        guard Set(archive.entries.map(\.id)).count == archive.entries.count else { throw JournalArchiveError.duplicateIdentity }
        var total = 0
        for (name, data) in archive.media {
            guard safeMediaName(name) else { throw JournalArchiveError.invalidMediaName }
            guard data.count <= maximumMediaBytes - total else { throw JournalArchiveError.archiveTooLarge }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard archive.mediaSHA256[name] == digest else { throw JournalArchiveError.mediaIntegrity }
            total += data.count
        }
        for entry in archive.entries {
            guard !entry.id.isEmpty else { throw JournalArchiveError.duplicateIdentity }
            let coordinates = [entry.latitude, entry.longitude].compactMap { $0 }
            guard coordinates.allSatisfy(\.isFinite),
                  entry.latitude.map({ (-90...90).contains($0) }) ?? true,
                  entry.longitude.map({ (-180...180).contains($0) }) ?? true else { throw JournalArchiveError.invalidCoordinates }
            for name in entry.mediaFileNames {
                guard safeMediaName(name) else { throw JournalArchiveError.invalidMediaName }
                guard archive.media[name] != nil else { throw JournalArchiveError.missingMedia }
            }
            if entry.kindRaw == JournalEntryKind.meal.rawValue {
                guard let meal = entry.meal, meal.id.uuidString == entry.id,
                      meal.date == entry.createdAt, meal.dayKey == entry.dayKey,
                      NutritionDiaryValidation.isValid(meal) else { throw JournalArchiveError.invalidMealLink }
            } else if entry.meal != nil {
                throw JournalArchiveError.invalidMealLink
            }
            // Unknown raw state/source/kind and undecodable snapshot strings are intentionally
            // retained verbatim; validation must not silently normalize future data versions.
        }
    }
}

/// File I/O only; never touches SwiftData managed rows or actor-owned state.
enum JournalArchiveMedia {
    static func load(_ snapshot: JournalArchive, directory: URL, maximumBytes: Int) throws -> JournalArchive {
        guard maximumBytes >= 0 else { throw JournalArchiveError.archiveTooLarge }
        var result = snapshot
        var bytes = 0
        for entry in result.entries {
            for name in entry.mediaFileNames where result.media[name] == nil {
                guard JournalArchiveValidation.safeMediaName(name) else { throw JournalArchiveError.invalidMediaName }
                let url = directory.appendingPathComponent(name)
                let values: URLResourceValues
                do { values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) }
                catch { throw JournalArchiveError.missingMedia }
                guard values.isSymbolicLink == false, values.isRegularFile == true else { throw JournalArchiveError.missingMedia }
                let size = values.fileSize ?? maximumBytes + 1
                guard size >= 0, size <= maximumBytes - bytes else { throw JournalArchiveError.archiveTooLarge }
                let data: Data
                do { data = try Data(contentsOf: url) } catch { throw JournalArchiveError.missingMedia }
                guard data.count <= maximumBytes - bytes else { throw JournalArchiveError.archiveTooLarge }
                bytes += data.count
                result.media[name] = data
                result.mediaSHA256[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }
        try JournalArchiveValidation.validate(result, maximumMediaBytes: maximumBytes)
        return result
    }
}
