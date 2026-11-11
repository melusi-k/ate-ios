import Foundation

/// Codable before/after image payloads for the unified Journal archive recovery record
/// (#245 slice A). UnifiedArchiveImportBinding writes these into ArchiveRecoveryRecord.images
/// and journalAndMediaRecovery BEFORE any durable store mutation; UnifiedArchiveStartupRecovery
/// decodes them after a restart. No live store reference survives a process death, so every
/// recovery decision decodes from these exact byte values. Component names are stable
/// registered identifiers, never paths.

enum ArchiveComponentName {
    static let nutrition = "nutrition"
    static let defaults = "defaults"
    static let recipeShopping = "recipes-shopping"
}

/// Raw bytes of the nutrition components: the legacy diary UserDefaults key, the goals
/// storage file, and the legacy goals UserDefaults key. nil means absent, never empty.
struct ArchiveNutritionImage: Codable, Equatable {
    let diary: Data?
    let goalFile: Data?
    let legacyGoals: Data?
}

/// Raw bytes of the archive-owned UserDefaults keys. syncMeta is snapshot-guarded only:
/// the archive restore never writes it, so before and after images always agree on it.
struct ArchiveDefaultsImage: Codable, Equatable {
    let settings: Data?
    let timer: Data?
    let syncMeta: Data?
}

struct ArchiveRawRecipeImage: Codable, Equatable {
    let id: String
    let createdAt: Double
    let position: Int
    let json: Data
}

struct ArchiveRawShoppingImage: Codable, Equatable {
    let id: String
    let position: Int
    let json: Data
}

/// Raw recipe/shopping store triples in canonical order (position, then id). Existing
/// entity json bytes are preserved verbatim; they are never re-encoded.
struct ArchiveRecipeShoppingImage: Codable, Equatable {
    let recipes: [ArchiveRawRecipeImage]
    let shopping: [ArchiveRawShoppingImage]
}

/// The journalAndMediaRecovery payload: complete planned Journal insertions plus the
/// sha256 of every media file the transaction may publish. Media ownership at startup is
/// proven by content hash plus the exclusive-create publish semantics of
/// JournalArchiveFilesystemMedia (linkat never overwrites an existing destination).
struct JournalMediaRecoveryPayload: Codable, Equatable {
    let version: Int
    let entries: [JournalArchiveEntry]
    /// Media basename -> lowercase hex sha256 of the exact planned bytes.
    let media: [String: String]
}

/// Row-to-value mapping identical to JournalArchiveCapture/JournalArchiveRestore: every raw
/// field is copied verbatim, never normalized. Shared by capture and startup recovery so the
/// two sides can never disagree about what a stored row means.
@MainActor
enum ArchiveJournalRowMapping {
    static func value(_ row: JournalEntry, meal: NutritionDiaryEntry?) -> JournalArchiveEntry {
        JournalArchiveEntry(id: row.id, createdAt: row.createdAt, prompt: row.prompt, text: row.text,
            stateRaw: row.stateRaw, recipeIDs: row.recipeIDs,
            journalingSuggestionTitle: row.journalingSuggestionTitle, momentDate: row.momentDate,
            sourceRaw: row.sourceRaw, locationName: row.locationName, latitude: row.latitude,
            longitude: row.longitude, mediaFileNames: row.mediaFileNames, editedAt: row.editedAt,
            kindRaw: row.kindRaw, dayKey: row.dayKey, recipeSnapshotsRaw: row.recipeSnapshotsRaw, meal: meal)
    }
}
