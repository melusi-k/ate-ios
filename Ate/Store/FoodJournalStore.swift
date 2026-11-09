import Foundation
import SwiftData

enum FoodJournalStoreError: Error, Equatable {
    case invalidEntry
    case duplicateEntry
    case missingEntry
    case saveFailed
    case unreadableStore
    case conflictingIdentity
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
    let container: ModelContainer?
    private let writeContext: (ModelContext) throws -> Void

    init(container: ModelContainer?, writeContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.container = container
        self.writeContext = writeContext
    }

    /// Every meal entry as a diary value, sorted exactly like the legacy diary repository
    /// (day descending, then time descending within a day).
    /// Canonical readers must use the throwing API: unreadable is never an empty diary.
    func readMeals() throws -> [NutritionDiaryEntry] {
        guard let container else { throw FoodJournalStoreError.unreadableStore }
        let ctx = ModelContext(container)
        let entries = try ctx.fetch(FetchDescriptor<JournalEntry>())
        let payloads = try ctx.fetch(FetchDescriptor<JournalMealPayload>())
        let meals = entries.filter { $0.kindRaw == JournalEntryKind.meal.rawValue }
        let mealIDs = Set(meals.map(\.id))
        guard mealIDs.count == meals.count,
              Set(payloads.map(\.entryID)).count == payloads.count,
              payloads.allSatisfy({ mealIDs.contains($0.entryID) }),
              meals.count == payloads.count else { throw FoodJournalStoreError.unreadableStore }
        let payloadByEntry = Dictionary(uniqueKeysWithValues: payloads.map { ($0.entryID, $0) })
        let result = try meals.map { entry -> NutritionDiaryEntry in
            guard let dayKey = entry.dayKey, let id = UUID(uuidString: entry.id),
                  NutritionDiaryDayKey.date(for: dayKey) != nil,
                  let payload = payloadByEntry[entry.id],
                  NutritionMeal(rawValue: payload.mealRaw) != nil,
                  NutritionEntrySource(rawValue: payload.sourceRaw) != nil else { throw FoodJournalStoreError.unreadableStore }
            let meal = payload.diaryEntry(id: id, date: entry.createdAt, dayKey: dayKey)
            guard FoodJournalStore.validMeal(meal) else { throw FoodJournalStoreError.invalidEntry }
            return meal
        }
        return result.sorted { $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey }
    }

    /// Compatibility helper only. Production integration must never use this lossy boundary.
    func mealEntries() -> [NutritionDiaryEntry] { (try? readMeals()) ?? [] }

    /// Same validity on every write and read. Gregorian day keys are literal calendar dates,
    /// not permissively normalized DateComponents (for example February 30 must fail).
    static func validMeal(_ entry: NutritionDiaryEntry) -> Bool {
        NutritionDiaryValidation.isValid(entry) && validDayKey(entry.dayKey)
    }

    static func validDayKey(_ key: String) -> Bool {
        guard key.utf8.count == 10,
              key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return false }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requested = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: requested) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }

    private func transaction(_ write: (ModelContext) throws -> Void) throws {
        guard let container else { throw FoodJournalStoreError.saveFailed }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do { try write(context); try writeContext(context) }
        catch { context.rollback(); throw error }
    }

    func mealEntryIDs() -> Set<String> {
        Set(mealEntries().map { $0.id.uuidString })
    }

    /// Inserts a meal entry. Identity is the diary UUID; saving the same identity twice fails
    /// rather than duplicating (timeline contract: a saved meal appears exactly once).
    func saveMeal(_ entry: NutritionDiaryEntry) throws {
        guard FoodJournalStore.validMeal(entry) else { throw FoodJournalStoreError.invalidEntry }
        try transaction { ctx in
            let id = entry.id.uuidString
            guard try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).isEmpty,
                  try ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == id })).isEmpty else { throw FoodJournalStoreError.duplicateEntry }
            insert(entry, into: ctx)
        }
    }

    func updateMeal(_ entry: NutritionDiaryEntry) throws {
        guard FoodJournalStore.validMeal(entry) else { throw FoodJournalStoreError.invalidEntry }
        try transaction { ctx in
            let id = entry.id.uuidString
            guard let row = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).first,
                  row.kindRaw == JournalEntryKind.meal.rawValue,
                  let payload = try ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == id })).first else { throw FoodJournalStoreError.missingEntry }
            // Update only meal fields. Recipe snapshots, media and provenance stay attached.
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
            row.createdAt = entry.date; row.dayKey = entry.dayKey; row.editedAt = .now
        }
    }

    func deleteMealSafely(id: UUID) throws {
        try transaction { ctx in
            let id = id.uuidString
            guard let row = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).first,
                  row.kindRaw == JournalEntryKind.meal.rawValue,
                  let payload = try ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == id })).first else { throw FoodJournalStoreError.missingEntry }
            // Do not delete filesystem bytes before the database commit succeeds.
            ctx.delete(payload); ctx.delete(row)
        }
    }
    func deleteMeal(id: UUID) { try? deleteMealSafely(id: id) }

    /// Validate the complete input before making changes. Existing identical IDs are no-ops;
    /// any conflict fails the whole batch rather than silently changing either record.
    func importMeals(_ entries: [NutritionDiaryEntry]) throws {
        guard entries.allSatisfy(FoodJournalStore.validMeal),
              Set(entries.map(\.id)).count == entries.count else { throw FoodJournalStoreError.invalidEntry }
        let existing = Dictionary(uniqueKeysWithValues: try readMeals().map { ($0.id, $0) })
        guard entries.allSatisfy({ existing[$0.id] == nil || existing[$0.id] == $0 }) else { throw FoodJournalStoreError.conflictingIdentity }
        try transaction { ctx in
            let allIDs = Set(try ctx.fetch(FetchDescriptor<JournalEntry>()).map(\.id))
            for entry in entries where existing[entry.id] == nil {
                guard !allIDs.contains(entry.id.uuidString) else { throw FoodJournalStoreError.conflictingIdentity }
                insert(entry, into: ctx)
            }
        }
    }

    private func insert(_ entry: NutritionDiaryEntry, into ctx: ModelContext) {
        // Meal entries carry no reflection text and no inferred Health state.
        let journalEntry = JournalEntry(id: entry.id.uuidString, createdAt: entry.date, prompt: "",
                                        text: "", state: .balanced)
        journalEntry.stateRaw = ""
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
                                openState: JournalOpenState,
                                backupDirectory: URL? = nil, markerDefaults: UserDefaults = .standard,
                                fileManager: FileManager = .default) -> FoodJournalMigrationResult {
        // The retirement authority itself refuses nondurable containers. Callers cannot
        // accidentally clear durable legacy data after an in-memory verification.
        switch openState {
        case .ok, .recovered: break
        case .inMemoryFallback, .unavailable: return .failed("journal is not durably available")
        }
        // Capture the original bytes before decoding. Legacy reads may otherwise persist a
        // normalized day key and erase the only exact copy before backup.
        let originalBytes = legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey)
        let state = legacy.loadState(persistHistoricalDayKeys: false)
        if case .corrupt = state {
            // Never touch an unreadable payload: it is the only copy, and the existing diary
            // recovery (backup then reset) stays in charge until it is readable or removed.
            return .legacyCorrupt
        }
        if case .absent = state {
            return markerDefaults.bool(forKey: markerKey) ? .alreadyMigrated : .noLegacyData
        }
        guard case .loaded(let entries) = state else { return .failed("legacy diary state changed during migration") }

        // All-or-nothing validation: a partially imported legacy diary must not stay
        // editable and then conflict with the earlier partial canonical copy.
        guard entries.allSatisfy(FoodJournalStore.validMeal),
              Set(entries.map(\.id)).count == entries.count else {
            return .failed("invalid or duplicate legacy records preserved; no meals imported")
        }
        let valid = entries

        // Idempotence is by identity, not by the marker: entries already in the store are skipped,
        // so a retried or post-recovery run can never duplicate a meal.
        let existing: [NutritionDiaryEntry]
        do { existing = try store.readMeals() }
        catch { return .failed("journal read failed: \(error)") }
        let newEntries = valid.filter { entry in !existing.contains(where: { $0.id == entry.id }) }
        // A backup failure must precede all canonical mutation, not leave a partial move.
        guard let raw = originalBytes,
              legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey) == raw else {
            return .failed("legacy payload changed before backup")
        }
        let dir = backupDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacyBackupDirectoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = dir.appendingPathComponent("nutrition-diary-legacy-\(stamp)-\(UUID().uuidString).json")
            try raw.write(to: backup, options: .atomic)
            guard try Data(contentsOf: backup) == raw else { return .failed("backup verification failed") }
        } catch {
            return .failed("backup failed: \(error)")
        }
        // Recheck the exact snapshot after disk IO and immediately before importing it.
        guard legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey) == raw else {
            return .failed("legacy payload changed during backup")
        }
        do { try store.importMeals(valid) }
        catch { return .failed("import failed: \(error)") }
        guard let stored = try? store.readMeals(), valid.allSatisfy({ stored.contains($0) }) else {
            return .failed("verification failed: legacy payloads do not match the journal store")
        }
        // Never retire a payload written by another consumer while this move was running.
        guard legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey) == raw else {
            return .failed("legacy payload changed before retirement")
        }
        legacy.clear()
        guard legacy.defaults.data(forKey: NutritionDiaryRepository.storageKey) == nil else {
            return .failed("legacy retirement could not be verified")
        }
        markerDefaults.set(true, forKey: markerKey)
        return .migrated(newEntries.count)
    }
}
