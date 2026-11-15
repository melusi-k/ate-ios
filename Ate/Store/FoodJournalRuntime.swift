import Foundation

/// One composition point for the diary, Insights and startup. Not activated until archive,
/// reset and all ordinary writer routes have been reviewed together.
@MainActor
final class FoodJournalRuntime {
    let writerBoundary: FoodJournalWriterBoundary
    let defaults: UserDefaults
    let cookingHistory: CookingHistory
    let journal: JournalStore
    let cookOfferPolicy: CookReflectionOfferPolicy
    let cookOutbox: CookCompletionOutbox
    let coordinator: FoodJournalCoordinator
    let repair: LegacyDiaryRepair
    let goalsRepository: NutritionGoalsRepository

    init(journal: JournalStore, goalsRepository: NutritionGoalsRepository, defaults: UserDefaults = .standard,
         writerBoundary: FoodJournalWriterBoundary = .legacy,
         migrationBackupDirectory: URL? = nil, repairBackupDirectory: URL? = nil,
         afterRestoreCommit: @escaping () throws -> Void = {}) {
        self.writerBoundary = writerBoundary
        self.journal = journal
        self.defaults = defaults
        self.cookingHistory = CookingHistory(defaults: defaults, writerBoundary: writerBoundary)
        self.cookOfferPolicy = CookReflectionOfferPolicy(defaults: defaults, writerBoundary: writerBoundary)
        self.cookOutbox = CookCompletionOutbox(defaults: defaults, writerBoundary: writerBoundary)
        self.goalsRepository = NutritionGoalsRepository(defaults: goalsRepository.defaults,
            storage: goalsRepository.storage, writerBoundary: writerBoundary)
        let legacy = NutritionDiaryRepository(defaults: defaults, backupDirectory: repairBackupDirectory)
        coordinator = FoodJournalCoordinator(journal: journal, legacy: legacy, writerBoundary: writerBoundary,
                                              markerDefaults: defaults,
                                              backupDirectory: migrationBackupDirectory,
                                              afterRestoreCommit: afterRestoreCommit)
        repair = LegacyDiaryRepair(repository: legacy, backupDirectory: legacy.backupDirectory, writerBoundary: writerBoundary)
    }

    /// Explicit host query. Never acknowledges a pending cook just because it was read or offered.
    func pendingCookReflections() throws -> [CookCompletionEvent] { try cookOutbox.load() }

    /// Require the retained event from this runtime's own queue, not a reconstructed current recipe.
    func reflectionSession(for eventID: String, existingDraft: String = "") throws -> CookedJournalReflectionSession {
        guard let event = try cookOutbox.load().first(where: { $0.id == eventID }) else {
            throw CookedJournalReflectionError.invalidContext
        }
        return CookedJournalReflectionSession(event: event, reflections: CookedJournalReflectionStore(journal: journal, writerBoundary: writerBoundary),
                                              outbox: cookOutbox, existingDraft: existingDraft)
    }

    /// All consumers retain failure as unavailable, never fabricate an empty diary.
    var openState: JournalOpenState { coordinator.openState }

    func readReflections() throws -> [JournalEntry] { try journal.readReflections() }

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
