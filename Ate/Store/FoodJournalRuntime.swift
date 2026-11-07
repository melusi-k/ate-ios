import Foundation

/// One composition point for the diary, Insights and startup. Not activated until archive,
/// reset and all ordinary writer routes have been reviewed together.
@MainActor
final class FoodJournalRuntime {
    let journal: JournalStore
    let coordinator: FoodJournalCoordinator
    let repair: LegacyDiaryRepair
    let goalsRepository: NutritionGoalsRepository

    init(journal: JournalStore, goalsRepository: NutritionGoalsRepository, defaults: UserDefaults = .standard,
         migrationBackupDirectory: URL? = nil, repairBackupDirectory: URL? = nil,
         afterRestoreCommit: @escaping () throws -> Void = {}) {
        self.journal = journal
        self.goalsRepository = goalsRepository
        let legacy = NutritionDiaryRepository(defaults: defaults, backupDirectory: repairBackupDirectory)
        coordinator = FoodJournalCoordinator(journal: journal, legacy: legacy,
                                              markerDefaults: defaults,
                                              backupDirectory: migrationBackupDirectory,
                                              afterRestoreCommit: afterRestoreCommit)
        repair = LegacyDiaryRepair(repository: legacy, backupDirectory: legacy.backupDirectory)
    }

    /// All consumers retain failure as unavailable, never fabricate an empty diary.
    var openState: JournalOpenState { coordinator.openState }

    func readMeals() throws -> [NutritionDiaryEntry] { try coordinator.readMeals() }

    /// Timeline and meal consumers enter through the same migration barrier. A failed move
    /// cannot look like an empty unified history simply because the old diary still exists.
    func timelineItems(calendar: Calendar = .autoupdatingCurrent) throws -> [JournalTimelineItem] {
        try coordinator.timelineItems(calendar: calendar)
    }
}

/// Candidate graph refuses legacy archive fallback while its real archive/reset binding is absent.
enum CanonicalConsumerBindingError: LocalizedError {
    case archiveBindingRequired
    var errorDescription: String? {
        "The unified Journal archive is not ready. Your records have not been changed."
    }
}
