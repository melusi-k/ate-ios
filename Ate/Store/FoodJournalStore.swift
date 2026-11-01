import Foundation
import SwiftData

enum FoodJournalStoreError: Error, Equatable {
    case invalidEntry
    case duplicateEntry
    case missingEntry
    case saveFailed
}

/// Unified local store for Food Journal meal entries (#245).
///
/// Meals live in the same local SwiftData journal container as reflections: one identity per
/// meal (the diary UUID), structured typed nutrition on `JournalMealPayload`, local-only -
/// nothing here is ever synced, matching the journal's existing privacy promise and the
/// contract in docs/product/FOOD_JOURNAL.md. Existing diary behavior is preserved by
/// reconstructing `NutritionDiaryEntry` values verbatim from the stored payloads, so #179
/// calculations, totals and views keep operating on the same fields they use today.
@MainActor
final class FoodJournalStore {
    static let shared = FoodJournalStore(container: JournalStore.shared.container)

    let container: ModelContainer?

    init(container: ModelContainer?) {
        self.container = container
    }

    private var context: ModelContext? { container?.mainContext }

    /// Every meal entry as a diary value, sorted exactly like the legacy diary repository
    /// (day descending, then time descending within a day).
    func mealEntries() -> [NutritionDiaryEntry] {
        guard let ctx = context else { return [] }
        let entries = (try? ctx.fetch(FetchDescriptor<JournalEntry>())) ?? []
        let payloads = (try? ctx.fetch(FetchDescriptor<JournalMealPayload>())) ?? []
        let payloadByEntry = Dictionary(payloads.map { ($0.entryID, $0) }, uniquingKeysWith: { a, _ in a })
        return entries.compactMap { entry in
            guard entry.kind == .meal, let dayKey = entry.dayKey,
                  let id = UUID(uuidString: entry.id),
                  let payload = payloadByEntry[entry.id] else { return nil }
            return payload.diaryEntry(id: id, date: entry.createdAt, dayKey: dayKey)
        }.sorted { $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey }
    }

    func mealEntryIDs() -> Set<String> {
        Set(mealEntries().map { $0.id.uuidString })
    }

    /// Inserts a meal entry. Identity is the diary UUID; saving the same identity twice fails
    /// rather than duplicating (timeline contract: a saved meal appears exactly once).
    func saveMeal(_ entry: NutritionDiaryEntry) throws {
        guard NutritionDiaryValidation.isValid(entry) else { throw FoodJournalStoreError.invalidEntry }
        guard let ctx = context else { throw FoodJournalStoreError.saveFailed }
        let entryID = entry.id.uuidString
        let duplicates = (try? ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == entryID }))) ?? []
        guard duplicates.isEmpty else { throw FoodJournalStoreError.duplicateEntry }
        insert(entry, into: ctx)
        guard (try? ctx.save()) != nil else { ctx.rollback(); throw FoodJournalStoreError.saveFailed }
    }

    /// Updates the stored values for an existing meal identity. Editing never creates a second
    /// entry and never changes the identity; the original day is preserved unless the caller
    /// explicitly moves the entry to another day.
    func updateMeal(_ entry: NutritionDiaryEntry) throws {
        guard NutritionDiaryValidation.isValid(entry) else { throw FoodJournalStoreError.invalidEntry }
        guard let ctx = context else { throw FoodJournalStoreError.saveFailed }
        let entryID = entry.id.uuidString
        guard let payload = try ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == entryID })).first,
              let journalEntry = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == entryID })).first else {
            throw FoodJournalStoreError.missingEntry
        }
        payload.mealRaw = entry.meal.rawValue
        payload.foodName = entry.foodName
        payload.quantity = entry.quantity
        payload.quantityUnit = entry.quantityUnit
        payload.servings = entry.servings
        payload.sourceRaw = entry.source.rawValue
        payload.sourceName = entry.sourceName
        payload.sourceIdentifier = entry.sourceIdentifier
        payload.verificationNote = entry.verificationNote
        payload.energyKcal = entry.nutrientsPerServing.energyKcal
        payload.proteinGrams = entry.nutrientsPerServing.proteinGrams
        payload.carbohydratesGrams = entry.nutrientsPerServing.carbohydratesGrams
        payload.fatGrams = entry.nutrientsPerServing.fatGrams
        payload.fibreGrams = entry.nutrientsPerServing.fibreGrams
        journalEntry.createdAt = entry.date
        journalEntry.dayKey = entry.dayKey
        journalEntry.editedAt = .now
        guard (try? ctx.save()) != nil else { ctx.rollback(); throw FoodJournalStoreError.saveFailed }
    }

    /// Deletes a meal entry and its payload together; the timeline never keeps one without the other.
    func deleteMeal(id: UUID) {
        guard let ctx = context else { return }
        let entryID = id.uuidString
        if let payload = try? ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == entryID })).first {
            ctx.delete(payload)
        }
        if let entry = try? ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == entryID })).first {
            for file in entry.mediaFileNames { try? FileManager.default.removeItem(at: JournalStore.mediaURL(file)) }
            ctx.delete(entry)
        }
        try? ctx.save()
    }

    /// Bulk insert for migration: all entries in one save so a failed migration commits nothing.
    /// An invalid entry aborts the entire import; migration never silently discards records.
    func importMeals(_ entries: [NutritionDiaryEntry]) throws {
        guard let ctx = context else { throw FoodJournalStoreError.saveFailed }
        for entry in entries {
            guard NutritionDiaryValidation.isValid(entry) else { throw FoodJournalStoreError.invalidEntry }
            insert(entry, into: ctx)
        }
        guard (try? ctx.save()) != nil else { ctx.rollback(); throw FoodJournalStoreError.saveFailed }
    }

    private func insert(_ entry: NutritionDiaryEntry, into ctx: ModelContext) {
        // Meal entries carry no reflection text and no inferred state: `.balanced` is a neutral
        // placeholder, never shown as a health reading (contract: do not infer states).
        let journalEntry = JournalEntry(id: entry.id.uuidString, createdAt: entry.date, prompt: "",
                                        text: "", state: .balanced)
        journalEntry.kindRaw = JournalEntryKind.meal.rawValue
        journalEntry.dayKey = entry.dayKey
        ctx.insert(journalEntry)
        ctx.insert(JournalMealPayload(entryID: entry.id.uuidString, meal: entry.meal, foodName: entry.foodName,
                                      quantity: entry.quantity, quantityUnit: entry.quantityUnit,
                                      servings: entry.servings, source: entry.source,
                                      sourceName: entry.sourceName, sourceIdentifier: entry.sourceIdentifier,
                                      verificationNote: entry.verificationNote, nutrients: entry.nutrientsPerServing))
    }
}

/// Outcome of migrating the legacy UserDefaults food diary into the unified journal store.
enum FoodJournalMigrationResult: Equatable {
    /// Imported N entries, verified them, backed the legacy payload up to a file and retired the key.
    case migrated(Int)
    /// A previous migration already retired the legacy key.
    case alreadyMigrated
    /// No legacy diary exists; nothing to do.
    case noLegacyData
    /// The legacy payload is unreadable. Nothing was touched: the diary's existing backup/reset
    /// recovery remains in charge, and migration retries after the user recovers.
    case legacyCorrupt
    /// Import, verification or backup failed; the legacy payload and key are untouched.
    case failed(String)
}

/// One-time, idempotent move of the UserDefaults food diary (`ate.nutritionDiary.v1`) into the
/// unified journal store (#245 phase 2, contract section 10.3).
enum FoodJournalMigration {
    static let markerKey = "ate.foodJournal.diaryMigration.v1"
    static let legacyBackupDirectoryName = "NutritionDiaryLegacyBackups"

    @MainActor
    static func migrateIfNeeded(legacy: NutritionDiaryRepository, store: FoodJournalStore,
                                backupDirectory: URL? = nil, markerDefaults: UserDefaults = .standard,
                                fileManager: FileManager = .default) -> FoodJournalMigrationResult {
        let state = legacy.loadState()
        if case .corrupt = state {
            // Never touch an unreadable payload: it is the only copy, and the existing diary
            // recovery (backup then reset) stays in charge until it is readable or removed.
            return .legacyCorrupt
        }
        if case .absent = state {
            return markerDefaults.bool(forKey: markerKey) ? .alreadyMigrated : .noLegacyData
        }
        guard case .loaded(let entries) = state else { return .failed("legacy diary state changed during migration") }

        // Malformed records are never silently discarded: valid entries import, malformed ones stay
        // in the legacy store, the key is not retired, and the failure is reported honestly.
        let valid = entries.filter { NutritionDiaryValidation.isValid($0) }
        let malformed = entries.count - valid.count

        // Idempotence is by identity, not by the marker: entries already in the store are skipped,
        // so a retried or post-recovery run can never duplicate a meal.
        let existing = store.mealEntryIDs()
        let newEntries = valid.filter { !existing.contains($0.id.uuidString) }
        do {
            try store.importMeals(newEntries)
        } catch {
            return .failed("import failed: \(error)")
        }

        // Verification before any retirement: every valid legacy identity must now exist in the store.
        let stored = store.mealEntryIDs()
        guard valid.allSatisfy({ stored.contains($0.id.uuidString) }) else {
            return .failed("verification failed: not every legacy entry is present in the journal store")
        }

        if malformed > 0 {
            return .failed("\(malformed) malformed legacy record(s) preserved in the diary store for recovery")
        }

        // Preserve a backup before retiring the legacy key: write the original payload to a file
        // first, and only retire the key once the backup is proven written. If the backup cannot
        // be written, nothing is retired and the next run retries.
        guard let raw = legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey) else {
            return .failed("could not re-read the legacy payload for backup")
        }
        let dir = backupDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacyBackupDirectoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try raw.write(to: dir.appendingPathComponent("nutrition-diary-legacy-\(stamp).json"), options: .atomic)
        } catch {
            return .failed("backup failed: \(error)")
        }
        legacy.clear()
        markerDefaults.set(true, forKey: markerKey)
        return .migrated(newEntries.count)
    }
}
