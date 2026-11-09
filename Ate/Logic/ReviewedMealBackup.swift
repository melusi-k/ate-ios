import Foundation

/// Values shown for explicit review. Exact original bytes are retained for import/copy;
/// decoded fields are never re-encoded into a different backup behind the user's review.
struct ReviewedMealBackup: Identifiable {
    let id = UUID()
    let originalBytes: Data
    let entries: [NutritionDiaryEntry]
    static let maximumBytes = 20 * 1024 * 1024

    static func isPickerCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == CocoaError.userCancelled.rawValue
    }

    /// Bounded copy, never a mutable memory mapping or unbounded whole-file read.
    static func readBytes(from url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var result = Data()
        while result.count <= maximumBytes {
            let chunk = try file.read(upToCount: min(64 * 1024, maximumBytes + 1 - result.count)) ?? Data()
            if chunk.isEmpty { return result }
            result.append(chunk)
        }
        throw ReviewedMealBackupError.tooLarge
    }

    @MainActor init(_ raw: Data) throws {
        guard raw.count <= Self.maximumBytes else { throw ReviewedMealBackupError.tooLarge }
        guard let decoded = try? JSONDecoder().decode([NutritionDiaryEntry].self, from: raw),
              !decoded.isEmpty, decoded.allSatisfy(FoodJournalStore.validMeal),
              Set(decoded.map(\.id)).count == decoded.count else { throw ReviewedMealBackupError.invalid }
        originalBytes = raw
        entries = decoded
    }
}

enum ReviewedMealBackupError: LocalizedError {
    case tooLarge, invalid, restoreFailed(String)
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a meal backup smaller than 20 MB."
        case .invalid: return "This is not a valid meal backup. It must contain valid, unique meal records. Nothing was imported."
        case .restoreFailed(let message): return message
        }
    }
}
