import Foundation

/// One composition point for the diary, Insights and startup. Not activated until archive,
/// reset and all ordinary writer routes have been reviewed together.
@MainActor
final class FoodJournalRuntime {
    let defaults: UserDefaults
    let cookingHistory: CookingHistory
    let journal: JournalStore
    let cookOfferPolicy: CookReflectionOfferPolicy
    let cookOutbox: CookCompletionOutbox
    let coordinator: FoodJournalCoordinator
    let repair: LegacyDiaryRepair
    let goalsRepository: NutritionGoalsRepository

    init(journal: JournalStore, goalsRepository: NutritionGoalsRepository, defaults: UserDefaults = .standard,
         migrationBackupDirectory: URL? = nil, repairBackupDirectory: URL? = nil) {
        self.defaults = defaults
        self.cookingHistory = CookingHistory(defaults: defaults)
        self.journal = journal
        self.cookOfferPolicy = CookReflectionOfferPolicy(defaults: defaults)
        self.cookOutbox = CookCompletionOutbox(defaults: defaults)
        self.goalsRepository = goalsRepository
        let legacy = NutritionDiaryRepository(defaults: defaults, backupDirectory: repairBackupDirectory)
        coordinator = FoodJournalCoordinator(journal: journal, legacy: legacy,
                                              markerDefaults: defaults,
                                              backupDirectory: migrationBackupDirectory)
        repair = LegacyDiaryRepair(repository: legacy, backupDirectory: legacy.backupDirectory)
    }

    /// Explicit host query. Never acknowledges a pending cook just because it was read or offered.
    func pendingCookReflections() throws -> [CookCompletionEvent] { try cookOutbox.load() }

    /// Require the retained event from this runtime's own queue, not a reconstructed current recipe.
    func reflectionSession(for eventID: String, existingDraft: String = "") throws -> CookedJournalReflectionSession {
        guard let event = try cookOutbox.load().first(where: { $0.id == eventID }) else {
            throw CookedJournalReflectionError.invalidContext
        }
        return CookedJournalReflectionSession(event: event, reflections: CookedJournalReflectionStore(journal: journal),
                                              outbox: cookOutbox, existingDraft: existingDraft)
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
