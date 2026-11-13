import Foundation

/// Local-only collaborators for standalone recipe/shopping. Does NOT construct a
/// FoodJournalRuntime, migrate diary data or activate archive/meal routes.
@MainActor
final class RecipeShoppingLocalServices {
    let defaults: UserDefaults
    let sharedDefaults: UserDefaults
    let boundary: FoodJournalWriterBoundary
    let drafts: DraftStore
    let timers: TimerCenter
    let history: CookingHistory
    let outbox: CookCompletionOutbox
    let offerPolicy: CookReflectionOfferPolicy
    let journal: JournalStore
    private let owner: RecipeShoppingSyncOwner?

    private init(defaults: UserDefaults, sharedDefaults: UserDefaults, boundary: FoodJournalWriterBoundary,
                 journal: JournalStore, owner: RecipeShoppingSyncOwner?, readOnly: Bool) {
        self.defaults = defaults; self.sharedDefaults = sharedDefaults; self.boundary = boundary
        self.owner = owner; self.journal = journal
        drafts = DraftStore(defaults: defaults, enabled: true, writerBoundary: boundary, resetOnLaunch: false)
        timers = TimerCenter(writerBoundary: boundary, readOnlyObserver: readOnly,
            snapshotDefaults: sharedDefaults, resetForUITesting: false)
        history = CookingHistory(defaults: defaults, writerBoundary: boundary)
        outbox = CookCompletionOutbox(defaults: defaults, writerBoundary: boundary)
        offerPolicy = CookReflectionOfferPolicy(defaults: defaults, writerBoundary: boundary)
    }
    /// Safe constructor fallback, not a usable production graph. Private collaborators,
    /// no singleton initialization or launch QA resets before complete inventory proof.
    static func refusing(defaults: UserDefaults) -> RecipeShoppingLocalServices {
        let boundary = FoodJournalWriterBoundary { _ in throw FoodJournalWriterBoundary.Failure.effectNotPerformed }
        return .init(defaults: defaults, sharedDefaults: defaults, boundary: boundary,
            journal: JournalStore(container: nil, openState: .unavailable(error: "Local services need verified admission."), writerBoundary: boundary),
            owner: nil, readOnly: true)
    }
    /// Caller supplies an explicit existing Journal owner, not its shared initializer.
    /// Journal must already have been strictly opened without repair/maintenance.
    /// The shared boundary must be this owner's freshly produced readiness adapter.
    static func admitted(resources: RecipeShoppingAdmittedResources, sharedDefaults: UserDefaults,
                         makeJournal: (FoodJournalWriterBoundary) throws -> JournalStore) throws -> RecipeShoppingLocalServices {
        let owner = resources.binding.owner
        let shared = try owner.makeSharedWriterBoundary(resources: resources)
        let boundary = FoodJournalWriterBoundary { work in try shared.withEffect(work) }
        do {
            return try boundary.withEffect {
                let journal = try makeJournal(boundary)
                guard journal.container != nil else { throw JournalReadError.storeUnavailable }
                switch journal.openState {
                case .ok: break
                default: throw JournalReadError.storeUnavailable
                }
                return .init(defaults: resources.binding.defaults, sharedDefaults: sharedDefaults,
                    boundary: boundary, journal: journal, owner: owner, readOnly: false)
            }
        } catch {
            try shared.retire()
            try owner.retireForSessionTransition()
            throw error
        }
    }
    func validates(_ binding: RecipeShoppingAuthorityBinding) -> Bool {
        guard owner === binding.owner, defaults === binding.defaults else { return false }
        do { try boundary.withEffect {}; return true } catch { return false }
    }
}
