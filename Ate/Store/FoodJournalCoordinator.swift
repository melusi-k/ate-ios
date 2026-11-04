import Foundation

/// No call sites are activated in this candidate. All diary consumers must move together.
/// The coordinator owns the binding between durable-open evidence and its actual container.
@MainActor
final class FoodJournalCoordinator {
    enum AccessError: Error, Equatable {
        case legacyCorrupt
        case migrationFailed(String)
    }

    private let journal: JournalStore
    private let meals: FoodJournalStore
    private let legacy: NutritionDiaryRepository
    private let markerDefaults: UserDefaults
    private let backupDirectory: URL?

    init(journal: JournalStore, legacy: NutritionDiaryRepository,
         markerDefaults: UserDefaults, backupDirectory: URL? = nil) {
        self.journal = journal
        self.meals = FoodJournalStore(container: journal.container)
        self.legacy = legacy
        self.markerDefaults = markerDefaults
        self.backupDirectory = backupDirectory
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

    // Archive import/clear are intentionally absent: coordinating their goals/media/reflection
    // transaction is a separate integrity contract, not an array replacement or legacy fallback.
}
