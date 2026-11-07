import Foundation
import SwiftData

/// No call sites are activated in this candidate. All diary consumers must move together.
/// The coordinator owns the binding between durable-open evidence and its actual container.
@MainActor
final class FoodJournalCoordinator {
    enum AccessError: Error, Equatable {
        case legacyCorrupt
        case migrationFailed(String)
        case invalidBackup
        case backupVerificationFailed
        case restoreCommittedButUnverified
        case restoreOutcomeUncertain
    }

    private let journal: JournalStore
    private let meals: FoodJournalStore
    private let legacy: NutritionDiaryRepository
    private let markerDefaults: UserDefaults
    private let backupDirectory: URL?
    private let afterRestoreCommit: () throws -> Void

    init(journal: JournalStore, legacy: NutritionDiaryRepository,
         markerDefaults: UserDefaults, backupDirectory: URL? = nil,
         afterRestoreCommit: @escaping () throws -> Void = {},
         mealWriteContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.journal = journal
        self.meals = FoodJournalStore(container: journal.container, writeContext: mealWriteContext)
        self.legacy = legacy
        self.markerDefaults = markerDefaults
        self.backupDirectory = backupDirectory
        self.afterRestoreCommit = afterRestoreCommit
    }

    var openState: JournalOpenState { journal.openState }

    /// Rechecks legacy existence and actual open state on every boundary use. Do not cache
    /// readiness across external restore, account resets or corrupt-data recovery.
    private func prepare() throws {
        let outcome = FoodJournalMigration.migrateIfNeeded(
            legacy: legacy, store: meals, openState: journal.openState,
            backupDirectory: backupDirectory, markerDefaults: markerDefaults)
        switch outcome {
        case .migrated, .alreadyMigrated, .noLegacyData: return
        case .legacyCorrupt: throw AccessError.legacyCorrupt
        case .failed(let reason): throw AccessError.migrationFailed(reason)
        }
    }

    func readMeals() throws -> [NutritionDiaryEntry] {
        try prepare()
        return try meals.readMeals()
    }

    func timelineItems(calendar: Calendar = .autoupdatingCurrent) throws -> [JournalTimelineItem] {
        try prepare()
        return try meals.timelineItems(calendar: calendar)
    }

    func saveMeal(_ entry: NutritionDiaryEntry) throws {
        try prepare()
        try meals.saveMeal(entry)
    }

    func updateMeal(_ entry: NutritionDiaryEntry) throws {
        try prepare()
        try meals.updateMeal(entry)
    }

    func deleteMeal(id: UUID) throws {
        try prepare()
        try meals.deleteMealSafely(id: id)
    }

    /// Explicit user-reviewed legacy-backup import only, never called during startup.
    /// The selected original bytes get their own verified retained copy BEFORE this
    /// operation enters migration/import. No legacy key is restored or recreated.
    /// This is meal-backup recovery, not complete goals/media/reflection archive restore.
    @discardableResult
    func restoreReviewedLegacyBackup(_ raw: Data, preservedCopyDirectory: URL) throws -> Int {
        let incoming: [NutritionDiaryEntry]
        do { incoming = try JSONDecoder().decode([NutritionDiaryEntry].self, from: raw) }
        catch { throw AccessError.invalidBackup }
        guard incoming.allSatisfy(FoodJournalStore.validMeal),
              Set(incoming.map(\.id)).count == incoming.count else { throw AccessError.invalidBackup }
        switch journal.openState {
        case .ok, .recovered: break
        case .inMemoryFallback, .unavailable:
            throw AccessError.migrationFailed("journal is not durably available")
        }
        // Reject conflicts against BOTH canonical and still-legacy values before prepare()
        // can migrate/retire anything. Decode without historical-day normalization writes.
        let canonical = try meals.readMeals()
        guard let container = journal.container else { throw FoodJournalStoreError.unreadableStore }
        let allRows = try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
        let rowIDs = Set(allRows.map(\.id))
        let mealIDs = Set(canonical.map { $0.id.uuidString })
        guard incoming.allSatisfy({ !rowIDs.contains($0.id.uuidString) || mealIDs.contains($0.id.uuidString) }) else {
            throw FoodJournalStoreError.conflictingIdentity
        }
        var known = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        switch legacy.loadState(persistHistoricalDayKeys: false) {
        case .corrupt: throw AccessError.legacyCorrupt
        case .absent: break
        case .loaded(let old):
            guard old.allSatisfy(FoodJournalStore.validMeal),
                  Set(old.map(\.id)).count == old.count else {
                throw AccessError.migrationFailed("invalid or duplicate legacy records preserved; no meals imported")
            }
            for entry in old {
                guard known[entry.id] == nil || known[entry.id] == entry else {
                    throw FoodJournalStoreError.conflictingIdentity
                }
                known[entry.id] = entry
            }
        }
        guard incoming.allSatisfy({ known[$0.id] == nil || known[$0.id] == $0 }) else {
            throw FoodJournalStoreError.conflictingIdentity
        }
        try FileManager.default.createDirectory(at: preservedCopyDirectory, withIntermediateDirectories: true)
        let copy = preservedCopyDirectory.appendingPathComponent("reviewed-legacy-backup-\(UUID().uuidString).json")
        try raw.write(to: copy, options: .atomic)
        guard try Data(contentsOf: copy) == raw else { throw AccessError.backupVerificationFailed }
        // Existing legacy data, if any, must pass the same migration barrier first.
        // A failure here may have created a retained backup, never a new legacy key.
        try prepare()
        let before = try meals.readMeals()
        do { try meals.importMeals(incoming) }
        catch {
            // A save implementation can throw after a durable commit. Do not promise
            // rollback or silently retry from an uncertain outcome.
            throw AccessError.restoreOutcomeUncertain
        }
        do {
            try afterRestoreCommit()
            let after = try meals.readMeals()
            let indexed = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
            guard incoming.allSatisfy({ indexed[$0.id] == $0 }) else {
                throw AccessError.restoreCommittedButUnverified
            }
            return after.count - before.count
        } catch { throw AccessError.restoreCommittedButUnverified }
    }

    // Archive import/clear are intentionally absent: coordinating their goals/media/reflection
    // transaction is a separate integrity contract, not an array replacement or legacy fallback.
}
