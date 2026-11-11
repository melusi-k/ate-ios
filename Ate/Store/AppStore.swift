import Foundation
import SwiftData
import SwiftUI
import Observation

@Model
final class RecipeEntity {
    @Attribute(.unique) var id: String
    var createdAt: Double
    var position: Int
    var json: Data
    init(id: String, createdAt: Double, position: Int, json: Data) {
        self.id = id; self.createdAt = createdAt; self.position = position; self.json = json
    }
}

@Model
final class ShoppingEntity {
    @Attribute(.unique) var id: String
    var position: Int
    var json: Data
    init(id: String, position: Int, json: Data) { self.id = id; self.position = position; self.json = json }
}

struct CookTarget: Identifiable, Equatable { let id: String }

/// The last in-progress cooking session. Deliberately independent of timers: many recipe steps have no timer.
struct CookSession: Codable, Equatable {
    var sessionID: String
    var recipeID: String
    var stepIndex: Int
    /// Servings factor chosen for this cook (from the recipe detail picker); drives the ingredient checklist sheet.
    var factor: Double
    /// Positions of ingredients the cook has marked as gathered. Lives and dies with the session.
    var checked: [Int]
    /// Fingerprint of the recipe's ingredient list (RecipeLogic.ingredientSignature). Checks are
    /// positional, so an ingredient edit invalidates them; a mismatch resets checked to empty.
    var ingredientSignature: String

    init(recipeID: String, stepIndex: Int, factor: Double = 1, checked: [Int] = [], ingredientSignature: String = "", sessionID: String = UUID().uuidString) {
        self.sessionID = sessionID
        self.recipeID = recipeID
        self.stepIndex = stepIndex
        self.factor = factor
        self.checked = checked
        self.ingredientSignature = ingredientSignature
    }

    /// Sessions persisted by older builds carry only recipeID and stepIndex; decode them with defaults
    /// instead of dropping the session on app upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID) ?? UUID().uuidString
        recipeID = try c.decode(String.self, forKey: .recipeID)
        stepIndex = try c.decode(Int.self, forKey: .stepIndex)
        factor = try c.decodeIfPresent(Double.self, forKey: .factor) ?? 1
        checked = try c.decodeIfPresent([Int].self, forKey: .checked) ?? []
        ingredientSignature = try c.decodeIfPresent(String.self, forKey: .ingredientSignature) ?? ""
    }

    mutating func toggleChecked(_ index: Int) {
        if let i = checked.firstIndex(of: index) { checked.remove(at: i) } else { checked.append(index) }
    }
}

enum AuthMode: String, Identifiable { case signIn, signUp, newPassword; var id: String { rawValue } }

enum SignUpOutcome: Equatable { case signedIn, confirmationSent, failed(AuthError) }

enum SyncState: Equatable {
    case signedOut, idle, syncing, synced(Date), unavailable(String), failed(String)
    var label: String {
        switch self {
        case .signedOut: return "Signed out — recipes stay on this device."
        case .idle: return "Not synced yet"
        case .syncing: return "Syncing…"
        case .synced(let d): return "Synced " + (abs(d.timeIntervalSinceNow) < 60 ? "just now" : d.formatted(date: .omitted, time: .shortened))
        case .unavailable(let m): return m
        case .failed(let m): return "Sync failed: " + m
        }
    }
}

private struct SyncMeta: Codable {
    var recipeStamps: [String: Double] = [:]
    var recipeTombs: [String: Double] = [:]
    var shopStamps: [String: Double] = [:]
    var shopTombs: [String: Double] = [:]
    var userID: String?
}

struct AteDataArchive: Codable {
    static let formatName = "ate-user-data"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var recipes: [RecipeCard]
    var shoppingItems: [ShoppingItem]
    var nutritionDiaryEntries: [NutritionDiaryEntry]
    var nutritionGoals: DailyNutritionGoals
    var appSettings: AppSettings
    var timerPreferences: TimerPrefs

    init(exportedAt: Date = .now, appVersion: String = AppConfig.appVersion, recipes: [RecipeCard],
         shoppingItems: [ShoppingItem], nutritionDiaryEntries: [NutritionDiaryEntry],
         nutritionGoals: DailyNutritionGoals, appSettings: AppSettings, timerPreferences: TimerPrefs) {
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.recipes = recipes
        self.shoppingItems = shoppingItems
        self.nutritionDiaryEntries = nutritionDiaryEntries
        self.nutritionGoals = nutritionGoals
        self.appSettings = appSettings
        self.timerPreferences = timerPreferences
    }
}

enum AteDataArchiveError: LocalizedError {
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalidNutritionEntry
    case localDiaryUnreadable
    case localDiaryUnreadableOnExport

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "This file is not a supported ate data export."
        case .unsupportedVersion(let version): "This ate data export version (\(version)) is not supported."
        case .invalidNutritionEntry: "This export contains an invalid food diary entry. No data was imported."
        case .localDiaryUnreadable: "Your saved food diary couldn't be read safely. No data was imported. Back up and reset the diary, then import again."
        case .localDiaryUnreadableOnExport: "Your saved food diary couldn't be read safely. No export was created. Back up and reset the diary, then export again."
        }
    }
}

struct DataImportSummary {
    var recipesAdded = 0
    var shoppingItemsAdded = 0
    var nutritionEntriesAdded = 0

    var message: String {
        let counts = [
            (recipesAdded, "recipe", "recipes"),
            (nutritionEntriesAdded, "food diary entry", "food diary entries"),
            (shoppingItemsAdded, "shopping item", "shopping items")
        ].compactMap { item -> String? in
            let (count, singular, plural) = item
            guard count > 0 else { return nil }
            return "\(count) \(count == 1 ? singular : plural)"
        }
        return counts.isEmpty ? "Data up to date" : "Imported " + counts.joined(separator: ", ")
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
    var actionTitle: String? = nil
}

struct RecoveryInfo: Identifiable, Equatable {
    let id = UUID()
    var backupPath: String?
    var inMemory: Bool
    var restoredFromSync = false
    var restoredCount = 0
    var exportURL: URL?
    var error: String?
}

struct QuickAddRequest: Identifiable, Equatable { let id = UUID(); let mode: WidgetLinks.AddMode }

enum BottomAddContext {
    case recipe, food, shopping, journal

    var title: String {
        switch self {
        case .recipe: "Add recipe"
        case .food: "Log food"
        case .shopping: "Add item"
        case .journal: "New journal entry"
        }
    }
}

@Observable
@MainActor
final class AppStore {
    /// The live store, for App Intents that run in the app's process.
    static weak var current: AppStore?
    /// Set by the Quick add widget / control / intent: opens Add recipe on the matching tab.
    var quickAdd: QuickAddRequest?
    // Session-only manual Journal draft; survives portrait/sidebar tree replacement.
    var manualJournalHost: ManualJournalHost?
    var manualJournalDraft = ""
    var journalReflection = JournalReflectionDraft()
    var journalRevision = 0
    // Retain each optional cooked-reflection draft across sheet and portrait/sidebar replacement.
    var cookedReflectionSessions: [String: CookedJournalReflectionSession] = [:]
    var cookJournalViewVisible = false
    var cookJournalModalDismissing = false
    var cookedReflectionPendingID: String?
    var cookedReflectionPresentedID: String?

    func availableCookedReflections(queued: [CookCompletionEvent]) -> [CookCompletionEvent] {
        var events = Dictionary(uniqueKeysWithValues: queued.map { ($0.id, $0) })
        for (id, session) in cookedReflectionSessions where !session.isSaved { events[id] = session.event }
        return events.values.sorted { $0.completedAt == $1.completedAt ? $0.id < $1.id : $0.completedAt > $1.completedAt }
    }

    // Bind only the cooking reflection to the Journal already used by the app. This does not
    // activate the pending unified diary/archive/reset graph.
    var cookJournalDefaults: UserDefaults { foodJournalRuntime?.defaults ?? .standard }
    var cookJournalOutbox: CookCompletionOutbox { foodJournalRuntime?.cookOutbox ?? CookCompletionOutbox(defaults: cookJournalDefaults) }
    var cookJournalOfferPolicy: CookReflectionOfferPolicy { foodJournalRuntime?.cookOfferPolicy ?? CookReflectionOfferPolicy(defaults: cookJournalDefaults) }
    var cookJournalStore: JournalStore { journalStore }

    func requestCookedReflection(_ event: CookCompletionEvent) {
        do {
            if cookedReflectionSessions[event.id] == nil {
                guard try cookJournalOutbox.load().contains(event) else { throw CookedJournalReflectionError.invalidContext }
                cookedReflectionSessions[event.id] = CookedJournalReflectionSession(event: event,
                    reflections: CookedJournalReflectionStore(journal: cookJournalStore), outbox: cookJournalOutbox)
            }
            cookedReflectionPendingID = event.id
        } catch { show("Ate could not open the note for this cook. The saved cook list was not changed.", error: true) }
    }

    /// Called by the presentation owner only after Cook Mode has left its modal/navigation host.
    func presentPendingCookedReflection() {
        guard cookTarget == nil, !cookJournalViewVisible, !cookJournalModalDismissing,
              !path.contains(where: { if case .cook = $0 { return true }; return false }),
              manualJournalHost == nil, authSheet == nil, !showOnboarding, cookedReflectionPresentedID == nil,
              let id = cookedReflectionPendingID, cookedReflectionSessions[id] != nil else { return }
        cookedReflectionPresentedID = id
        cookedReflectionPendingID = nil
    }

    func beginManualJournal() { if manualJournalHost == nil { manualJournalHost = .root } }
    /// Controls the persistent bottom action for the destination currently in view.
    var bottomAddContext: BottomAddContext = .recipe
    /// Requests handled by the active Food diary and Shopping list screens.
    var showNutritionDiaryEntry = false
    /// Opens the Food diary destination from a contextual insight action.
    var showNutritionDiary = false
    var requestShoppingAdd = false
    /// Set by the system search intent ("Search ate for tripe"): Library adopts it as its query.
    var pendingSearch: String?
    func search(_ term: String) {
        select(.library); path = []
        pendingSearch = term.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Persisted independently from timers so exiting Cook Mode never loses an untimed step.
    @ObservationIgnored private var adoptingPersistedCookSession = false
    var cookSession: CookSession? = nil {
        didSet {
            guard !adoptingPersistedCookSession else { return }
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
                Self.saveCookSession(cookSession, defaults: foodJournalRuntime?.defaults ?? .standard)
            }
        }
    }
    private static let cookSessionDefaultsKey = "ate.cookSession.v1"
    private static func loadCookSession(defaults: UserDefaults = .standard) -> CookSession? {
        guard let data = defaults.data(forKey: cookSessionDefaultsKey) else { return nil }
        guard let session = try? JSONDecoder().decode(CookSession.self, from: data) else { return nil }
        // Persist an identity assigned to an older snapshot before it can be used by Finish.
        // Exact readback is rechecked by prepareCookCompletion; this is not an fsync claim.
        saveCookSession(session, defaults: defaults)
        return session
    }
    private static func saveCookSession(_ session: CookSession?, defaults: UserDefaults = .standard) {
        guard let session else {
            defaults.removeObject(forKey: cookSessionDefaultsKey); return
        }
        // Encoding failure never deletes the prior resumable session.
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: cookSessionDefaultsKey)
    }

    enum CookCompletionPreparationError: Error { case missingSession, invalidIdentity, persistenceFailed, sessionChanged }

    /// One actual session snapshot, persisted and verified before any completion queue/history change.
    /// Separate queue/store fsync and cross-process reset fencing remain integration gates.
    func prepareCookCompletion(recipeID: String) throws -> CookSession {
        try performOrdinaryWriteThrowing {
            let defaults = foodJournalRuntime?.defaults ?? .standard
            guard let session = cookSession, session.recipeID == recipeID else {
                throw CookCompletionPreparationError.missingSession
            }
            guard UUID(uuidString: session.sessionID) != nil else { throw CookCompletionPreparationError.invalidIdentity }
            let raw: Data
            do { raw = try JSONEncoder().encode(session) }
            catch { throw CookCompletionPreparationError.persistenceFailed }
            defaults.set(raw, forKey: Self.cookSessionDefaultsKey)
            guard defaults.data(forKey: Self.cookSessionDefaultsKey) == raw,
                  let verified = try? JSONDecoder().decode(CookSession.self, from: raw), verified == session else {
                throw CookCompletionPreparationError.persistenceFailed
            }
            return session
        }
    }

    /// Delayed completion cannot clear a replacement cook, even for the same recipe.
    func clearCompletedCookSession(sessionID: String) throws {
        try performOrdinaryWriteThrowing {
            let defaults = foodJournalRuntime?.defaults ?? .standard
            guard cookSession?.sessionID == sessionID else { throw CookCompletionPreparationError.sessionChanged }
            defaults.removeObject(forKey: Self.cookSessionDefaultsKey)
            guard defaults.object(forKey: Self.cookSessionDefaultsKey) == nil else {
                throw CookCompletionPreparationError.persistenceFailed
            }
            cookSession = nil
        }
    }
    func updateCookSession(recipeID: String, stepIndex: Int) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            // Moving between steps keeps the session's servings factor and gathered checks.
            if var s = cookSession, s.recipeID == recipeID {
                s.stepIndex = max(0, stepIndex)
                cookSession = s
            } else {
                cookSession = CookSession(recipeID: recipeID, stepIndex: max(0, stepIndex))
            }
        }
    }
    /// Opening Cook Mode from the recipe detail carries the chosen servings factor into the session.
    /// Re-entering the same recipe keeps gathered checks; a different recipe starts fresh.
    func beginCookSession(recipeID: String, factor: Double) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let sig = recipe(recipeID).map(RecipeLogic.ingredientSignature) ?? ""
            if var s = cookSession, s.recipeID == recipeID {
                // The active session owns its servings factor: re-entering the same recipe keeps
                // it; only a genuinely new session adopts the caller's detail selection.
                if s.ingredientSignature != sig { s.checked = []; s.ingredientSignature = sig }
                cookSession = s
            } else {
                cookSession = CookSession(recipeID: recipeID, stepIndex: 0, factor: factor, ingredientSignature: sig)
            }
        }
    }
    func setCookFactor(_ factor: Double) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard var s = cookSession else { return }
            s.factor = factor
            cookSession = s
        }
    }
    func toggleCookIngredientChecked(_ index: Int) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard var s = cookSession else { return }
            let sig = recipe(s.recipeID).map(RecipeLogic.ingredientSignature) ?? ""
            if s.ingredientSignature != sig { s.checked = []; s.ingredientSignature = sig }
            s.toggleChecked(index)
            cookSession = s
        }
    }
    func clearCookSession(recipeID: String? = nil) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard recipeID == nil || cookSession?.recipeID == recipeID else { return }
            cookSession = nil
        }
    }

    var recipes: [RecipeCard] = [] {
        didSet {
            // Gathered checks in an active cook session are positional: any write that changes
            // the session recipe's ingredient list (editor, add replace-by-id, sync merge) resets
            // them. Signature-equal writes (title-only edits, reorders) keep them.
            guard var session = cookSession,
                  let current = recipes.first(where: { $0.id == session.recipeID }) else { return }
            let signature = RecipeLogic.ingredientSignature(current)
            guard session.ingredientSignature != signature else { return }
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
                session.checked = []; session.ingredientSignature = signature; cookSession = session
            }
        }
    }
    var shopping: [ShoppingItem] = []
    /// Library tab's navigation stack (recipes, shared links, not-found).
    var path: [Route] = []
    var shoppingPath: [Route] = []
    /// Dedicated Cooking Tracker tab's navigation stack.
    var trackerPath: [Route] = []
    var settingsPath: [Route] = []
    var morePath: [Route] = []
    /// Set when the local store had to be repaired at launch (shows the recovery screen).
    var recovery: RecoveryInfo?
    /// iOS 26 search tab (Tab(role: .search)) has its own stack.
    var searchPath: [Route] = []
    /// True when the selected tab shows its root screen (banners that belong to tab roots hide on pushed screens).
    /// Primary action for the selected tab root. Search and Settings have none.
    var rootAddContext: BottomAddContext? {
        switch tab {
        case .library, .collection: return .recipe
        case .shopping: return .shopping
        case .tracker: return .journal
        case .settings, .more, .search: return nil
        }
    }
    /// The Food diary (pushed from any tab) keeps "Log food"; otherwise the tab root decides.
    var activeAddContext: BottomAddContext? { bottomAddContext == .food ? .food : rootAddContext }
    var isAtTabRoot: Bool {
        switch tab {
        case .library, .collection: return path.isEmpty
        case .shopping: return shoppingPath.isEmpty
        case .tracker: return trackerPath.isEmpty
        case .settings: return settingsPath.isEmpty
        case .more: return morePath.isEmpty
        case .search: return searchPath.isEmpty
        }
    }
    var tab: AppTab = .library
    /// Item handed over by the "Save to ate" share extension, waiting for the Add sheet.
    var pendingImport: SharedInbox.Item?
    var pendingShoppingCount: Int { shopping.filter { !$0.done }.count }
    /// Library chip-row / sidebar filter, persisted between launches (UI tests start clean).
    var filter: RecipeFilter = AppConfig.isUITesting ? RecipeFilter() : RecipeFilter.load() {
        didSet {
            if !AppConfig.isUITesting {
                performOrdinaryWrite(Self.ordinaryWriteFailureMessage) { filter.save() }
            }
        }
    }

    /// Sidebar/tab selection of a collection applies its filter; Library clears it.
    func select(_ t: AppTab) {
        switch t {
        case .collection(let c): filter.collection = c; tab = t
        case .library: filter.collection = nil; tab = t
        default: tab = t
        }
    }

    /// Delete with a 5-second Undo toast.
    func deleteWithUndo(_ id: String) {
        guard let r = recipe(id), let idx = recipes.firstIndex(where: { $0.id == id }) else { return }
        delete(id); Haptics.warning()
        show("Deleted “\(r.title)”", action: "Undo", perform: { [weak self] in
            guard let self else { return }
            self.performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
                self.recipes.insert(r, at: min(idx, self.recipes.count)); self.persistRecipes()
                BetaQA.shared.pass("A-EDIT-04", note: "Deleted “\(r.title)” and restored it with Undo")
                self.toast = nil
            }
        }, seconds: 5)
    }

    func runToastAction() { let a = toastAction; toastAction = nil; a?() }

    var layout: LibraryLayout = AppConfig.isUITesting ? LibraryLayout() : LibraryLayout.load() {
        didSet {
            if !AppConfig.isUITesting {
                performOrdinaryWrite(Self.ordinaryWriteFailureMessage) { layout.save() }
            }
        }
    }

    /// Reorder for "My order": `ordered` is the full current display order; moves `id` to `target`'s slot.
    func move(_ id: String, before target: String, in ordered: [RecipeCard]) {
        var ids = ordered.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from); ids.insert(id, at: to)
        applyOrder(ids)
    }
    func move(fromOffsets: IndexSet, toOffset: Int, in ordered: [RecipeCard]) {
        var ids = ordered.map(\.id)
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        applyOrder(ids)
    }
    private func applyOrder(_ ids: [String]) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            for (i, id) in ids.enumerated() {
                if let k = recipes.firstIndex(where: { $0.id == id }) { recipes[k].sortIndex = Double(i) }
            }
            persistRecipes()
            layout.sort = .myOrder
            Haptics.step()
        }
    }

    func toggleFavourite(_ id: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard var r = recipe(id) else { return }
            r.favorite.toggle(); update(r)
            show(r.favorite ? "Added to Favourites" : "Removed from Favourites")
            Haptics.toggle()
        }
    }

    /// The sheet's history claim is allowed only after the exact day/recipe payload reads back.
    /// Retry uses the retained event date and identity, not the current clock.
    func recordCompletedCook(_ event: CookCompletionEvent) throws {
        try performOrdinaryWriteThrowing {
            guard recipe(event.recipeID) != nil else { throw CookCompletionOutboxError.session }
            let history = foodJournalRuntime?.cookingHistory ?? CookingHistory.shared
            try history.recordVerified(recipeID: event.recipeID, date: event.completedAt, dayKey: event.cookedDayKey)
            markCooked(event.recipeID, at: event.completedAt)
        }
    }

    func markCooked(_ id: String, at date: Date = .now) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard var r = recipe(id) else { return }
            r.lastCookedAt = (date.timeIntervalSince1970 * 1000).rounded(); update(r)
            (foodJournalRuntime?.cookingHistory ?? CookingHistory.shared).record(recipeID: id, date: date)
        }
    }

    /// Picks up the next item queued by the share extension (called when the app becomes active).
    func checkInbox() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard pendingImport == nil, let item = SharedInbox.pop() else { return }
            tab = .library; path = []; pendingImport = item
        }
    }
    var toast: Toast?
    var settings: AppSettings {
        didSet {
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) { saveDefaults(settings, key: "ate.settings.v1") }
        }
    }
    var timerPrefs: TimerPrefs {
        didSet {
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) { saveDefaults(timerPrefs, key: "ate.timerprefs.v1") }
        }
    }

    var cookTarget: CookTarget?
    let timers = TimerCenter()

    // Onboarding & auth UI
    var showOnboarding = false
    var authSheet: AuthMode?
    var pendingConfirmation: String?   // email awaiting confirmation

    // Accounts & sync
    var session: AuthSession?
    /// Keep lifecycle ownership stable while signed out if local app data is retained.
    var insightLifecycleAccountID: String? { session?.userID ?? meta.userID }
    var syncState: SyncState = .signedOut
    let auth: AuthService?
    let sync: SyncService?
    private var meta = SyncMeta()
    private var recipeSnapshot: [String: RecipeCard] = [:]
    private var shopSnapshot: [String: ShoppingItem] = [:]
    private var syncTask: Task<Void, Never>?

    let backend: BackendService
    private let context: ModelContext?
    /// Nil until the complete canonical consumer graph is qualified for activation.
    let foodJournalRuntime: FoodJournalRuntime?
    /// All in-app Journal surfaces use the graph's actual owner, including isolated QA worlds.
    /// The legacy graph retains its existing app-lifetime owner until activation is qualified.
    var journalStore: JournalStore { foodJournalRuntime?.journal ?? JournalStore.shared }
    var journalGoalsRepository: NutritionGoalsRepository {
        foodJournalRuntime?.goalsRepository ?? nutritionGoalsRepository
    }

    /// Central's consumer binding point (#245): the runtime's cooking history while the
    /// unified graph is injected; the legacy app-lifetime singleton only before activation.
    var journalCookingHistory: CookingHistory { foodJournalRuntime?.cookingHistory ?? CookingHistory.shared }

    /// Central binds the composed writer boundary at activation (FoodJournalWriterBoundary
    /// via JournalWriterBoundaryComposition). While nil, unified account actions keep
    /// refusing - no ungated wipe or transfer of the unified Journal.
    @ObservationIgnored var journalWriterEffect: ((() throws -> Void) throws -> Void)?
    /// Non-mutating re-proof of the same boundary: gate.validateWriter only, NEVER a
    /// generation-committing empty effect through the archive's nested lease. Central
    /// binds JournalWriterBoundaryComposition.makeValidator. Required together with
    /// journalWriterEffect for any wipe.
    @ObservationIgnored var journalWriterValidator: (() throws -> Void)?
    /// Unified Settings export, backed by A's UnifiedArchiveCapture service
    /// (snapshot() plus finish(stillCurrent:) before the bytes are published). The
    /// archive format and capture discipline are A's; AppStore only routes. While nil,
    /// the canonical refusal stands.
    @ObservationIgnored var journalArchiveExport: (() async throws -> Data)?
    /// Unified Settings import, backed by A's standalone ArchiveStandaloneImportSession.
    /// While nil, the canonical refusal stands.
    @ObservationIgnored var journalArchiveImport: ((Data) throws -> DataImportSummary)?
    /// Central supplies the adoption-preservation directory at composition
    /// (JournalInstallReconciliation); it joins the unified wipe's erase inventory.
    @ObservationIgnored var journalResetPreservationDirectory: URL?

    // MARK: ordinary-writer boundary seam (#245, lane 1)

    /// Honest failure copy for ordinary writes refused by the bound writer boundary:
    /// names the failed action and never claims nothing changed or that a rollback ran.
    static let ordinaryWriteFailureMessage = "ate couldn't save this change safely. Try again in a moment."
    static let sessionWriteFailureMessage = "ate couldn't update your sign-in on this iPhone safely. Try again in a moment."
    static let syncInterruptedMessage = "Sync paused because this iPhone could not finish updating its data safely. Review your recipes, then sync again."
    static let syncPushedButInterruptedMessage = "Sync reached the server, but this iPhone's data changed before the app could finish. Review your recipes, then sync again."

    /// Action-based read-modify-writes enter the boundary before mutating. The public
    /// SwiftUI-bound settings, timerPrefs, filter, layout and cookSession properties are
    /// intentionally memory-first edits: didSet gates persistence only, after the value is
    /// visible in this process. Refused persistence leaves that in-memory edit visible and
    /// reports a save error; it does not promise rollback, durability or unchanged memory.
    /// A later edit can retry persistence; relaunch reads the last durable value.
    /// While the boundary is unbound (#245 dormant), work runs exactly as before.
    /// A refusal surfaces an honest failure; it never claims unchanged state or a rollback
    /// (the effect may have partially run before throwing). The boundary is
    /// reentrant (NSRecursiveLock + active effect), so callers nested inside an outer effect
    /// (didSet observers, persist helpers, B's account actions) do not re-lock or stamp a
    /// second archive generation.
    @discardableResult
    private func performOrdinaryWrite<T>(_ failureMessage: String, _ work: () -> T) -> T? {
        guard let effect = journalWriterEffect else { return work() }
        var performed = false
        var result: T?
        do {
            try effect { performed = true; result = work() }
        } catch {
            show(failureMessage, error: true)
            return nil
        }
        guard performed else { show(failureMessage, error: true); return nil }
        return result
    }

    /// Throwing form for writers that already report failure through `throws`
    /// (cook-completion prepare/clear, completed-cook recording, legacy import, sync publish).
    private func performOrdinaryWriteThrowing<T>(_ work: () throws -> T) throws -> T {
        guard let effect = journalWriterEffect else { return try work() }
        var performed = false
        var result: T?
        try effect { performed = true; result = try work() }
        guard performed, let result else { throw OrdinaryWriteSeamError.effectNotPerformed }
        return result
    }

    /// Post-await publish guard for async flows (sync, auth callbacks, sign-out,
    /// delete-account). The boundary is NEVER held across an await: the flow captures the
    /// session before suspending and, after the await, re-proves that the current session is
    /// still the captured one and that the bound boundary still validates
    /// (journalWriterValidator only - validation, never a generation-committing empty effect).
    /// Inert while the boundary is unbound, so the dormant legacy graph keeps today's behavior.
    private func validatePostAwaitPublish(capturedSession: AuthSession?) -> Bool {
        if journalWriterEffect == nil && journalWriterValidator == nil { return true }
        guard journalWriterEffect != nil, let validate = journalWriterValidator else { return false }
        guard session == capturedSession else { return false }
        do { try validate() } catch { return false }
        return true
    }

    /// The bound effect returned without performing the write and without throwing - a
    /// boundary contract violation surfaced as an ordinary failure, never a crash.
    private enum OrdinaryWriteSeamError: Error { case effectNotPerformed }

    /// Shortcuts must use the live app composition, not open a second singleton owner.
    /// Background execution without that composition fails visibly until the app is open.
    static func journalStoreForIntent() throws -> JournalStore {
        guard let current else { throw JournalIntentOwnerError.appNotOpen }
        let journal = current.journalStore
        switch journal.openState {
        case .ok, .recovered: return journal
        case .inMemoryFallback, .unavailable: throw JournalIntentOwnerError.notDurable
        }
    }


    func journalTimelineItems() throws -> [JournalTimelineItem] {
        if let runtime = foodJournalRuntime { return try runtime.timelineItems() }
        // The not-yet-activated legacy graph still has one explicit Journal owner.
        return try FoodJournalStore(container: journalStore.container).timelineItems()
    }
    private let nutritionDiaryRepository: NutritionDiaryRepository
    private let nutritionGoalsRepository: NutritionGoalsRepository

    init(context: ModelContext?, backend: BackendService = AppConfig.makeBackend(),
         nutritionDiaryRepository: NutritionDiaryRepository = NutritionDiaryRepository(),
         nutritionGoalsRepository: NutritionGoalsRepository = NutritionGoalsRepository(),
         foodJournalRuntime: FoodJournalRuntime? = nil,
         journalWriterEffect: ((() throws -> Void) throws -> Void)? = nil,
         journalWriterValidator: (() throws -> Void)? = nil,
         injectedAuth: AuthService? = nil, injectedSync: SyncService? = nil) {
        self.context = context
        self.foodJournalRuntime = foodJournalRuntime
        // The ordinary-writer boundary is bound BEFORE load() and any launch normalization
        // writes; setting it as a property only after construction would leave the first
        // writes ungated.
        self.journalWriterEffect = journalWriterEffect
        self.journalWriterValidator = journalWriterValidator
        self.backend = backend
        self.nutritionDiaryRepository = nutritionDiaryRepository
        self.nutritionGoalsRepository = nutritionGoalsRepository
        // UI tests opt into a clean local cooking timeline per test launch so one test's
        // completed recipe cannot make another test's empty-history assertions flaky.
        if ProcessInfo.processInfo.arguments.contains("-qaResetCookingHistory") {
            CookingHistory.shared.clear()
        }
        // Insight lifecycle is persisted across launches. Acceptance tests opt into an isolated
        // lifecycle so a prior run's resolved/seen weekly insight cannot hide this run's candidate.
        if AppConfig.isUITesting &&
            ProcessInfo.processInfo.arguments.contains("-qaResetInsightLifecycle") {
            InsightLifecycleStore.clearAll()
        }
        if let injectedAuth {
            // Test/focused-graph injection: an explicit auth service carries its sync service
            // with it and skips the environment-based construction below.
            auth = injectedAuth; sync = injectedSync
        } else if AppConfig.isUITesting {
            auth = MockAuth(); sync = MockSync()
        } else if let url = AppConfig.supabaseURL, !AppConfig.supabasePublishableKey.isEmpty {
            auth = SupabaseAuth(baseURL: url, key: AppConfig.supabasePublishableKey)
            sync = SupabaseSync(baseURL: url, key: AppConfig.supabasePublishableKey)
        } else { auth = nil; sync = nil }
        // UI tests opt into imperial presentation so checklist conversion is exercised end to end.
        // Mutate before assignment: settings.didSet persists and touches other stored properties
        // that are not initialized yet at this point in init.
        var loadedSettings = Self.loadDefaults(AppSettings.self, key: "ate.settings.v1") ?? AppSettings()
        if AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaImperialUnits") {
            loadedSettings.units = .imperial
        }
        settings = loadedSettings
        timerPrefs = Self.loadDefaults(TimerPrefs.self, key: "ate.timerprefs.v1") ?? TimerPrefs()
        if AppConfig.isUITesting { UserDefaults.standard.removeObject(forKey: "ate.sync.v1"); Keychain.save(nil, account: "session") }
        meta = Self.loadDefaults(SyncMeta.self, key: "ate.sync.v1") ?? SyncMeta()
        session = Keychain.load(account: "session").flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
        syncState = session == nil ? .signedOut : .idle
        showOnboarding = AppConfig.isUITesting ? ProcessInfo.processInfo.arguments.contains("-showOnboarding")
                                               : !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        // The launch cook-session load is gated like every other ordinary write (older
        // snapshots are re-saved with an assigned identity by the loader). It runs late in
        // init so the bound boundary and every stored property are fully initialized.
        if !AppConfig.isUITesting {
            loadPersistedCookSession()
        }
        load()
        // UI tests opt into an empty shopping list per test launch so one journey's items
        // cannot leak into the next test's assertions (same rationale as -qaResetCookingHistory).
        if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaResetShopping") {
            shopping = []
            persistShopping(stamp: false)
        }
        recipeSnapshot = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        shopSnapshot = Dictionary(shopping.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        timers.prefsProvider = { [weak self] in self?.timerPrefs ?? TimerPrefs() }
        // Shares are attributed to the signed-in user when the session is still valid; otherwise anonymous.
        SupabaseBackend.userAccessToken = {
            guard let d = Keychain.load(account: "session"),
                  let s = try? JSONDecoder().decode(AuthSession.self, from: d),
                  s.expiresAt > Date().timeIntervalSince1970 + 30 else { return nil }
            return s.accessToken
        }
        Self.current = self
        WidgetBridge.installRelays(self)
        WidgetBridge.publish(self, delay: 1)
        if !AppConfig.isUITesting { AteShortcuts.updateAppShortcutParameters() }
    }

    /// Launch load of the persisted cook session, gated like every other ordinary write
    /// (older snapshots are re-saved with an assigned identity by the loader).
    func loadPersistedCookSession(defaults suppliedDefaults: UserDefaults? = nil) {
        let defaults = suppliedDefaults ?? foodJournalRuntime?.defaults ?? .standard
        if journalWriterEffect == nil {
            // Preserve the dormant production graph's established load/save behavior.
            cookSession = Self.loadCookSession(defaults: defaults)
            return
        }
        guard let raw = defaults.data(forKey: Self.cookSessionDefaultsKey),
              let decoded = try? JSONDecoder().decode(CookSession.self, from: raw) else { return }
        let fields = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        if fields?["sessionID"] is String {
            // Existing identity: memory-only adoption is not a committed write.
            adoptingPersistedCookSession = true
            defer { adoptingPersistedCookSession = false }
            cookSession = decoded
        } else {
            // Persist the identity assigned by the legacy decoder exactly once.
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
                guard defaults.data(forKey: Self.cookSessionDefaultsKey) == raw else { return }
                Self.saveCookSession(decoded, defaults: defaults)
                adoptingPersistedCookSession = true
                defer { adoptingPersistedCookSession = false }
                cookSession = decoded
            }
        }
    }

    // MARK: persistence
    private func load() {
        guard let context else { return }
        let dec = JSONDecoder()
        let rows = (try? context.fetch(FetchDescriptor<RecipeEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        let loaded = rows.compactMap { try? dec.decode(RecipeCard.self, from: $0.json) }
        let repaired = RecipeLogic.dedupe(loaded.map(RecipeLogic.normalize))
        if repaired.cards == loaded {
            // No durable repair is needed. Read-only loading is not a committed unit.
            recipes = loaded
        } else {
            performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
                recipes = repaired.cards
                let stamp = nowMs()
                let before = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for card in recipes where before[card.id] != card { meta.recipeStamps[card.id] = stamp }
                for id in repaired.removedIDs where !recipes.contains(where: { $0.id == id }) {
                    meta.recipeTombs[id] = stamp; meta.recipeStamps[id] = nil
                }
                saveDefaults(meta, key: "ate.sync.v1")
                persistRecipes(stamp: false)
            }
        }
        let shoppingRows = (try? context.fetch(FetchDescriptor<ShoppingEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        shopping = shoppingRows.compactMap { try? dec.decode(ShoppingItem.self, from: $0.json) }
    }

    // Internal (not private) for AppStore+JournalAccountActions, the unified account-action binding.
    func persistRecipes(stamp: Bool = true) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            BetaQA.shared.recipeCountChanged(recipes.count)
            if stamp { stampChanges() }
            WidgetBridge.publish(self)
            // Recipe names/synonyms feed the "Cook <recipe> in ate" phrases.
            if !AppConfig.isUITesting { AteShortcuts.updateAppShortcutParameters() }
            guard let context else { return }
            try? context.delete(model: RecipeEntity.self)
            let enc = JSONEncoder()
            for (i, c) in recipes.enumerated() {
                if let d = try? enc.encode(c) { context.insert(RecipeEntity(id: c.id, createdAt: c.createdAt, position: i, json: d)) }
            }
            StoreSaver.save(context, what: "recipes")
        }
    }

    // Internal (not private) for AppStore+JournalAccountActions.
    func persistShopping(stamp: Bool = true) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            if stamp { stampChanges() }
            WidgetBridge.publish(self)
            guard let context else { return }
            try? context.delete(model: ShoppingEntity.self)
            let enc = JSONEncoder()
            for (i, it) in shopping.enumerated() {
                if let d = try? enc.encode(it) { context.insert(ShoppingEntity(id: it.id, position: i, json: d)) }
            }
            StoreSaver.save(context, what: "shopping list")
        }
    }

    private func saveDefaults<T: Encodable>(_ v: T, key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func loadDefaults<T: Decodable>(_ t: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: toasts
    /// Runs when the toast's action button (e.g. Undo) is tapped.
    @ObservationIgnored var toastAction: (() -> Void)?

    func show(_ message: String, error: Bool = false, action: String? = nil, perform: (() -> Void)? = nil, seconds: Double = 2.6) {
        let t = Toast(message: message, isError: error, actionTitle: action)
        toastAction = perform
        withAnimation(Motion.anim()) { toast = t }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if toast?.id == t.id { withAnimation(Motion.anim()) { toast = nil }; toastAction = nil }
        }
    }

    // MARK: recipes
    func recipe(_ id: String) -> RecipeCard? { recipes.first { $0.id == id } }

    /// Idempotent: saving the same draft id again (restored draft, double tap) replaces instead of copying.
    func add(_ card: RecipeCard) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let c = RecipeLogic.normalize(card)
            if let i = recipes.firstIndex(where: { $0.id == c.id }) { recipes[i] = c } else { recipes.insert(c, at: 0) }
            DraftStore.shared.clear()
            persistRecipes()
        }
    }

    func update(_ card: RecipeCard) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let i = recipes.firstIndex(where: { $0.id == card.id }) else { return }
            recipes[i] = RecipeLogic.normalize(card)
            persistRecipes()
            BetaQA.shared.pass("A-EDIT-03", note: "Edited “\(card.title)” without a crash")
        }
    }

    /// Cover changed (file and/or remote URL). Not an "edit" for QA purposes.
    func setCover(_ id: String, file: String?, imageURL: String?, keepURL: Bool = true) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let i = recipes.firstIndex(where: { $0.id == id }) else { return }
            recipes[i].coverImage = file
            if let imageURL { recipes[i].imageURL = imageURL } else if !keepURL { recipes[i].imageURL = nil }
            persistRecipes()
        }
    }

    func delete(_ id: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            CoverStore.shared.removeFiles(recipeID: id)
            recipes.removeAll { $0.id == id }
            persistRecipes()
        }
    }

    /// New cooking context and retained drafts must not survive an explicit local-data wipe.
    // Internal (not private) for AppStore+JournalAccountActions.
    func clearCookCompletionContext() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            for key in cookJournalDefaults.dictionaryRepresentation().keys
                where key == CookCompletionOutbox.defaultsKey || key.hasPrefix(CookCompletionOutbox.unreadableKeyPrefix) || key == CookReflectionOfferPolicy.defaultsKey {
                cookJournalDefaults.removeObject(forKey: key)
            }
            cookedReflectionSessions.removeAll()
            cookedReflectionPendingID = nil
            cookedReflectionPresentedID = nil
            clearCookSession()
        }
    }

    func clearLibrary() {
        // Unified graph: the bound action routes through the runtime's own stores.
        if foodJournalRuntime != nil { clearLibraryUnified(); return }
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            clearCookCompletionContext()
            recipes = []; CookingHistory.shared.clear()
            path = []; shoppingPath = []; settingsPath = []; morePath = []; searchPath = []
            persistRecipes()
        }
    }

    func importJSON(_ data: Data) throws -> DataImportSummary {
        // Unified graph: import routes whole-file to A's standalone import session.
        if foodJournalRuntime != nil { return try importJSONUnified(data) }
        return try performOrdinaryWriteThrowing {
            let decoder = JSONDecoder()
            if let legacyCards = try? decoder.decode([RecipeCard].self, from: data) {
                let result = importRecipesPreservingExisting(legacyCards)
                recipes = result.result.map(RecipeLogic.normalize)
                persistRecipes()
                return DataImportSummary(recipesAdded: result.added)
            }

            let archive = try decoder.decode(AteDataArchive.self, from: data)
            guard archive.format == AteDataArchive.formatName else { throw AteDataArchiveError.unsupportedFormat }
            guard archive.version == AteDataArchive.currentVersion else {
                throw AteDataArchiveError.unsupportedVersion(archive.version)
            }
            guard archive.nutritionDiaryEntries.allSatisfy(NutritionDiaryValidation.isValid) else {
                throw AteDataArchiveError.invalidNutritionEntry
            }
            // An unreadable local diary must never be overwritten by imported data:
            // refuse the whole import before any archive-backed store is written.
            if case .corrupt = nutritionDiaryRepository.loadState() { throw AteDataArchiveError.localDiaryUnreadable }

            let recipeResult = importRecipesPreservingExisting(archive.recipes)
            var shoppingIDs = Set(shopping.map(\.id))
            let newShoppingItems = archive.shoppingItems.filter { shoppingIDs.insert($0.id).inserted }
            var diaryIDs = Set(nutritionDiaryRepository.load().map(\.id))
            let newDiaryEntries = archive.nutritionDiaryEntries.filter { diaryIDs.insert($0.id).inserted }

            // Prepare the only encoding that can fail before writing either archive-backed store.
            // Goals storage is the fallible commit; diary data is committed only after it succeeds.
            let preparedDiary = try nutritionDiaryRepository.prepare(nutritionDiaryRepository.load() + newDiaryEntries)
            try nutritionGoalsRepository.save(archive.nutritionGoals)
            nutritionDiaryRepository.savePrepared(preparedDiary)
            recipes = recipeResult.result.map(RecipeLogic.normalize)
            shopping.append(contentsOf: newShoppingItems)
            settings = archive.appSettings
            timerPrefs = archive.timerPreferences
            persistRecipes()
            persistShopping()
            return DataImportSummary(recipesAdded: recipeResult.added, shoppingItemsAdded: newShoppingItems.count,
                                     nutritionEntriesAdded: newDiaryEntries.count)
        }
    }

    /// Imports are additive. A matching ID on this device wins so an older archive
    /// cannot silently replace a newer local recipe.
    // Internal (not private) for AppStore+JournalAccountActions.
    func importRecipesPreservingExisting(_ incoming: [RecipeCard]) -> (result: [RecipeCard], added: Int) {
        var seenIDs = Set(recipes.map(\.id))
        let newCards = incoming.filter { seenIDs.insert($0.id).inserted }
        return RecipeLogic.importCards(newCards, into: recipes)
    }

    func exportJSON() throws -> Data {
        // Unified graph: sync export refuses unconditionally; the canonical export is
        // the async exportUserData() through A's capture service - never a local v1 fallback.
        if foodJournalRuntime != nil { return try exportJSONUnified() }
        // An unreadable local diary must not be exported as an ordinary empty diary:
        // fail visibly instead of producing an archive that claims nothing was logged.
        if case .corrupt = nutritionDiaryRepository.loadState() { throw AteDataArchiveError.localDiaryUnreadableOnExport }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let archive = AteDataArchive(recipes: recipes, shoppingItems: shopping,
                                     nutritionDiaryEntries: nutritionDiaryRepository.load(),
                                     nutritionGoals: try nutritionGoalsRepository.load(),
                                     appSettings: settings, timerPreferences: timerPrefs)
        return try enc.encode(archive)
    }

    /// Insights uses nil for unavailable, never an empty diary on a read/migration failure.
    func nutritionEntriesForInsights() -> [NutritionDiaryEntry]? {
        if let foodJournalRuntime { return try? foodJournalRuntime.readMeals() }
        switch nutritionDiaryRepository.loadState() {
        case .loaded(let entries): return entries
        case .absent: return []
        case .corrupt: return nil
        }
    }

    // MARK: shopping
    func addToShopping(_ card: RecipeCard, factor: Double) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            shopping = ShoppingLogic.merge(RecipeLogic.scaled(card, factor: factor).ingredients, source: card.title, into: shopping)
            persistShopping()
        }
    }
    func addManual(_ name: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let n = name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            shopping.append(ShoppingItem(name: n, quantity: 0, unit: "", aisle: ShoppingLogic.guessAisle(n)))
            persistShopping()
        }
    }
    func toggle(_ id: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let i = shopping.firstIndex(where: { $0.id == id }) else { return }
            shopping[i].done.toggle(); persistShopping()
        }
    }
    /// Widget checkbox (idempotent: carries the wanted state, not a toggle).
    func setShoppingDone(_ id: String, _ done: Bool) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let i = shopping.firstIndex(where: { $0.id == id }), shopping[i].done != done else { return }
            shopping[i].done = done; persistShopping()
        }
    }
    /// Update in place so completion, recipe sources, notes, unit and the stable item identity survive.
    /// The aisle is re-derived only when the name actually changed; a quantity-only edit keeps it.
    /// Setting the quantity to 0 ("no amount") also clears the unit so no dangling unit renders.
    @discardableResult func editShoppingItem(_ id: String, name: String, quantity: Double) -> Bool {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let trimmed = ShoppingEdit.trimmedName(name), quantity.isFinite, quantity >= 0,
                  let index = shopping.firstIndex(where: { $0.id == id }) else { return false }
            if shopping[index].name != trimmed {
                shopping[index].name = trimmed
                shopping[index].aisle = ShoppingLogic.guessAisle(trimmed)
            }
            if quantity == 0 {
                // "No amount" keeps no dangling unit, or the row would render "l Milk".
                shopping[index].unit = ""
            }
            shopping[index].quantity = quantity
            persistShopping()
            return true
        } ?? false
    }

    private struct PendingShoppingRemoval {
        let item: ShoppingItem
        let index: Int
        let owner: String?
    }
    private var pendingShoppingRemovals: [PendingShoppingRemoval] = []
    private var shoppingUndoToken = 0
    /// Production window is 5s. UI tests can override via -qaShoppingUndoSeconds <n>: XCTest
    /// observation + screenshot + event synthesis (observed ~5.5s in the runner) does not fit
    /// inside 5s, so the batch-undo journey widens the window rather than racing it. The
    /// expiry journey keeps the default and owns window-expiry behaviour.
    static var shoppingUndoSeconds: Double {
        guard AppConfig.isUITesting else { return 5 }
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-qaShoppingUndoSeconds"), i + 1 < a.count,
              let v = Double(a[i + 1]), v.isFinite, v > 0, v <= 600 else { return 5 }
        return v
    }

    /// Removals the open Undo batch would restore (test seam).
    var pendingShoppingUndoCount: Int { pendingShoppingRemovals.count }

    /// Remove with a 5-second Undo toast. Removals made while the toast is open join the same
    /// batch: the toast says "Removed N items" and Undo restores all of them, each at its
    /// original position. When the toast expires the batch is finalized and stays removed.
    /// Known limitation: the app has a single toast slot, so an unrelated toast (e.g. "Copied
    /// as text") shown during the window replaces the Undo affordance; the batch still
    /// finalizes on schedule. Full recovery would need a toast queue - not claimed here.
    func removeShoppingItemWithUndo(_ id: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard let index = shopping.firstIndex(where: { $0.id == id }) else { return }
            let item = shopping[index]
            pendingShoppingRemovals.append(PendingShoppingRemoval(item: item, index: index, owner: insightLifecycleAccountID))
            removeItem(id)
            let count = pendingShoppingRemovals.count
            shoppingUndoToken &+= 1
            let token = shoppingUndoToken
            show(count == 1 ? "Removed “\(item.name)”" : "Removed \(count) items",
                 action: "Undo", perform: { [weak self] in self?.undoShoppingRemovals() },
                 seconds: Self.shoppingUndoSeconds)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.shoppingUndoSeconds * 1_000_000_000))
                guard let self, self.shoppingUndoToken == token else { return }
                self.finalizeShoppingUndo()
            }
        }
    }

    /// Restores the open batch without touching anything else on the list: an item that came
    /// back through sync or a re-add is never duplicated, and edits made after a removal survive.
    /// Items removed under a different account are never restored into the current one.
    /// Each recorded index is the item's position at the moment it was removed, so the batch is
    /// restored in reverse removal order, undoing the removals one at a time to rebuild the
    /// original positions exactly. (Ascending-index insertion misplaces items whose index had
    /// already shifted under earlier removals in the same batch.)
    func undoShoppingRemovals() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let batch = pendingShoppingRemovals
            pendingShoppingRemovals = []
            shoppingUndoToken &+= 1
            toast = nil
            guard !batch.isEmpty else { return }
            var blockedByAccountChange = false
            for pending in batch.reversed() {
                guard pending.owner == insightLifecycleAccountID else { blockedByAccountChange = true; continue }
                guard !shopping.contains(where: { $0.id == pending.item.id }) else { continue }
                shopping.insert(pending.item, at: min(pending.index, shopping.count))
            }
            persistShopping()
            if blockedByAccountChange {
                show("Couldn’t restore — your account changed since removal.", error: true)
            }
        }
    }

    /// The Undo window closed without Undo (toast timer, or a test): removals become permanent.
    func finalizeShoppingUndo() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            pendingShoppingRemovals = []
            shoppingUndoToken &+= 1
        }
    }

    func removeItem(_ id: String) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            shopping.removeAll { $0.id == id }; persistShopping()
        }
    }
    func clearTicked() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            shopping.removeAll { $0.done }; persistShopping()
        }
    }
    /// One tap puts every bought item back on the to-buy list. The toast offers Undo, which
    /// re-marks exactly the items that were moved and leaves anything added, edited or removed
    /// since untouched. Item ids can match across synced accounts, so Undo only acts for the
    /// account that moved them (same rule as the removal Undo). Returns how many items moved.
    @discardableResult func moveBoughtBackToList() -> Int {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let ids = shopping.filter(\.done).map(\.id)
            guard !ids.isEmpty else { return 0 }
            let owner = insightLifecycleAccountID
            for i in shopping.indices where shopping[i].done { shopping[i].done = false }
            persistShopping()
            show(ids.count == 1 ? "1 item back on the list" : "\(ids.count) items back on the list",
                 action: "Undo", perform: { [weak self] in self?.markBought(ids, owner: owner) },
                 seconds: Self.shoppingUndoSeconds)
            return ids.count
        } ?? 0
    }
    private func markBought(_ ids: [String], owner: String?) {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            guard owner == insightLifecycleAccountID else {
                show("Couldn't undo - your account changed since the items were moved back.", error: true)
                return
            }
            let wanted = Set(ids)
            var changed = false
            for i in shopping.indices where wanted.contains(shopping[i].id) && !shopping[i].done {
                shopping[i].done = true; changed = true
            }
            if changed { persistShopping() }
        }
    }
    func clearShopping() {
        // Clearing shopping data must not reset navigation in unrelated tabs.
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            shopping = []
            persistShopping()
        }
    }

    // MARK: sync bookkeeping (last-write-wins)
    private func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private func stampChanges() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            let t = nowMs()
            var changed = false
            let rNow = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, c) in rNow where recipeSnapshot[id] != c { meta.recipeStamps[id] = t; meta.recipeTombs[id] = nil; changed = true }
            for id in recipeSnapshot.keys where rNow[id] == nil { meta.recipeTombs[id] = t; meta.recipeStamps[id] = nil; changed = true }
            recipeSnapshot = rNow
            let sNow = Dictionary(shopping.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, it) in sNow where shopSnapshot[id] != it { meta.shopStamps[id] = t; meta.shopTombs[id] = nil; changed = true }
            for id in shopSnapshot.keys where sNow[id] == nil { meta.shopTombs[id] = t; meta.shopStamps[id] = nil; changed = true }
            shopSnapshot = sNow
            if changed { saveDefaults(meta, key: "ate.sync.v1"); scheduleSync() }
        }
    }

    func scheduleSync(delay: Double = 1.5) {
        guard session != nil else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await syncNow()
        }
    }

    /// After a store repair: pull everything back from Supabase (if signed in) and export what we have as JSON.
    func completeRecovery() async {
        guard var r = recovery else { return }
        if session != nil {
            meta = SyncMeta()                       // fresh store: treat the server as the source of truth
            await syncNow()
            r.restoredFromSync = true
        }
        r.restoredCount = recipes.count
        r.exportURL = StoreRecovery.exportRecovered(recipes)
        recovery = r
    }

    func syncNow() async {
        guard var s = session, let sync, let auth else { syncState = .signedOut; return }
        syncState = .syncing
        // Determine account ownership before any refresh or pull can fail. If this is a switch,
        // the previous account's local library must never remain visible under the new session.
        let switchingAccounts = SyncMerge.isAccountSwitch(lastSyncedUser: meta.userID, newUser: s.userID)
        var accountSwitchPullSucceeded = false
        // The writer boundary is never held across an await: capture the session before
        // suspending and re-prove session + epoch after each await, before publishing.
        var capturedSession = session
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 {
                do {
                    s = try await auth.refresh(s)
                    guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                        syncState = .failed(Self.syncInterruptedMessage); return
                    }
                    guard setSession(s) else {
                        syncState = .failed(Self.sessionWriteFailureMessage); return
                    }
                    capturedSession = session
                    BetaQA.shared.pass("A-AUTH-06", note: "Session refreshed before sync")
                }
                catch let e as AuthError where e.kind == .unauthorized { expireSession(); return }
            }
            // Persist ownership on first sign-in before network I/O. If the first pull fails, a
            // later sign-in after relaunch must not merge this user's local library into another.
            if meta.userID == nil {
                do {
                    try performOrdinaryWriteThrowing {
                        meta.userID = s.userID
                        saveDefaults(meta, key: "ate.sync.v1")
                    }
                } catch {
                    syncState = .failed(Self.syncInterruptedMessage); return
                }
            }
            let remote = try await sync.pull(session: s)
            accountSwitchPullSucceeded = true
            BetaQA.shared.syncPulled(rows: remote.count)
            // The pulled snapshot publishes only while the session and writer epoch captured
            // before the await are still current.
            guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                syncState = .failed(Self.syncInterruptedMessage); return
            }
            let out: [SyncRecord]
            do {
                out = try performOrdinaryWriteThrowing {
                    if switchingAccounts {
                        // Keep the previous account's local copy until the new account's pull succeeds.
                        // A failed request must not erase recipes or change their account ownership.
                        recipes = []; shopping = []; recipeSnapshot = [:]; shopSnapshot = [:]
                        persistRecipes(stamp: false); persistShopping(stamp: false)
                        meta = SyncMeta()
                        meta.userID = s.userID
                        BetaQA.shared.pass("A-SYNC-05", note: "Account switch detected; previous account's copy removed")
                        show("Switched accounts — the other account's recipes were removed from this iPhone (they're still in that account).")
                    }
                    meta.userID = s.userID
                    let enc = JSONEncoder()
                    let dec = JSONDecoder()

                    let r = SyncMerge.merge(local: .init(data: recipes.reduce(into: [:]) { $0[$1.id] = try? enc.encode($1) },
                                                         stamps: meta.recipeStamps, tombstones: meta.recipeTombs),
                                            remote: remote.filter { $0.kind == "recipe" })
                    let sh = SyncMerge.merge(local: .init(data: shopping.reduce(into: [:]) { $0[$1.id] = try? enc.encode($1) },
                                                          stamps: meta.shopStamps, tombstones: meta.shopTombs),
                                             remote: remote.filter { $0.kind == "shopping" })

                    recipes = r.data.values.compactMap { try? dec.decode(RecipeCard.self, from: $0) }.map(RecipeLogic.normalize).sorted { $0.createdAt > $1.createdAt }
                    let dd = RecipeLogic.dedupe(recipes); recipes = dd.cards
                    let newShop = sh.data.compactMapValues { try? dec.decode(ShoppingItem.self, from: $0) }
                    var ordered = shopping.compactMap { newShop[$0.id] }
                    for (id, it) in newShop where !ordered.contains(where: { $0.id == id }) { ordered.append(it) }
                    shopping = ordered
                    meta.recipeStamps = r.stamps; meta.recipeTombs = r.tombstones
                    for id in dd.removedIDs { meta.recipeTombs[id] = nowMs(); meta.recipeStamps[id] = nil }   // merged duplicates delete remotely too
                    meta.shopStamps = sh.stamps; meta.shopTombs = sh.tombstones
                    recipeSnapshot = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    shopSnapshot = Dictionary(shopping.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    persistRecipes(stamp: false); persistShopping(stamp: false)
                    saveDefaults(meta, key: "ate.sync.v1")

                    func rec(_ kind: String, _ id: String, _ data: Data?, _ stamp: Double, _ del: Bool) -> SyncRecord {
                        SyncRecord(user_id: s.userID, kind: kind, id: id, data: data.map { AnyJSON($0) }, stampMs: stamp, deleted: del)
                    }
                    var records: [SyncRecord] = []
                    records += r.push.map { rec("recipe", $0, r.data[$0], r.stamps[$0] ?? nowMs(), false) }
                    records += r.pushDeletes.map { rec("recipe", $0, nil, r.tombstones[$0] ?? nowMs(), true) }
                    records += sh.push.map { rec("shopping", $0, sh.data[$0], sh.stamps[$0] ?? nowMs(), false) }
                    records += sh.pushDeletes.map { rec("shopping", $0, nil, sh.tombstones[$0] ?? nowMs(), true) }
                    return records
                }
            } catch {
                // The boundary refused the merge publish: the local library kept its pre-sync
                // state and the remote rows stay on the server for the next sync.
                syncState = .failed(Self.syncInterruptedMessage)
                return
            }
            try await sync.push(out, session: s)
            // The push landed on the server; only the local completion publish is abandoned
            // when the session or epoch moved during it.
            guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                syncState = .failed(Self.syncPushedButInterruptedMessage)
                return
            }
            syncState = .synced(Date())
            BetaQA.shared.syncSucceeded(pushed: out.count)
        } catch SyncError.tableMissing {
            if switchingAccounts && !accountSwitchPullSucceeded {
                signOutAfterFailedAccountSwitch()
            } else {
                syncState = .unavailable(SyncError.tableMissing.errorDescription ?? "")
            }
        } catch SyncError.unauthorized {
            expireSession()
        } catch {
            if switchingAccounts && !accountSwitchPullSucceeded {
                signOutAfterFailedAccountSwitch()
            } else {
                syncState = .failed(error.localizedDescription)
            }
            BetaQA.shared.syncFailed(Net.friendly(error))
        }
    }

    /// A failed initial pull during an account switch must not leave account B active over
    /// account A's local library. Keep the local data intact and require a retry when online.
    private func signOutAfterFailedAccountSwitch() {
        guard setSession(nil) else {
            syncState = .failed(Self.sessionWriteFailureMessage); return
        }
        let message = "Account switch couldn't be completed. Your previous library is safe on this iPhone. Reconnect and sign in again."
        syncState = .failed(message)
        show(message, error: true, seconds: 5)
    }

    /// Session can't be refreshed: sign out locally (keep recipes) and say so plainly.
    var sessionExpired = false
    func expireSession() {
        guard setSession(nil) else {
            syncState = .failed(Self.sessionWriteFailureMessage); return
        }
        sessionExpired = true
        syncState = .failed(Self.sessionExpiredMessage)
        show(Self.sessionExpiredMessage, error: true)
    }
    static let sessionExpiredMessage = "Your session expired — sign in again to keep syncing. Your recipes are safe on this iPhone."

    /// True only when the whole bounded effect returns successfully. False does not
    /// imply rollback: the session/keychain/watch publish may already have partly run.
    private func setSession(_ s: AuthSession?) -> Bool {
        performOrdinaryWrite(Self.sessionWriteFailureMessage) {
            if s != nil { sessionExpired = false }
            session = s
            Keychain.save(s.flatMap { try? JSONEncoder().encode($0) }, account: "session")
            PhoneWatchBridge.shared.update(session: s)
            return true
        } == true
    }

    // MARK: onboarding
    static let onboardedKey = "ate.onboarded.v1"
    func finishOnboarding() {
        if !AppConfig.isUITesting { UserDefaults.standard.set(true, forKey: Self.onboardedKey) }
        showOnboarding = false
    }
    func replayOnboarding() { showOnboarding = true }

    // MARK: account
    var accountAvailable: Bool { auth != nil }

    /// Returns nil on success.
    func signIn(email: String, password: String) async -> AuthError? {
        guard let auth else { return AuthError(message: "Accounts aren't configured in this build.") }
        let email = email.trimmingCharacters(in: .whitespaces)
        let capturedSession = session
        do {
            let new = try await auth.signIn(email: email, password: password)
            // Post-await guard: a reset or account change while the request was in flight
            // abandons the publish instead of signing this iPhone in under a stale epoch.
            guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                return AuthError(message: "This iPhone's data changed while signing in. Sign in again.")
            }
            guard setSession(new) else { return AuthError(message: Self.sessionWriteFailureMessage) }
            pendingConfirmation = nil
            BetaQA.shared.pass("A-AUTH-03", note: "Signed in as \(new.email)")
            show("Signed in")
            Task { await syncNow() }
            return nil
        } catch {
            let e = AuthError.network(error)
            if e.kind == .emailNotConfirmed { pendingConfirmation = email }
            if e.kind != .invalidCredentials && e.kind != .emailNotConfirmed { BetaQA.shared.fail("A-AUTH-03", error: "Sign in: \(e.message)") }
            return e
        }
    }

    func signUp(email: String, password: String) async -> SignUpOutcome {
        guard let auth else { return .failed(AuthError(message: "Accounts aren't configured in this build.")) }
        let email = email.trimmingCharacters(in: .whitespaces)
        let capturedSession = session
        do {
            if let s = try await auth.signUp(email: email, password: password) {
                guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                    return .failed(AuthError(message: "This iPhone's data changed while creating your account. Sign in instead."))
                }
                guard setSession(s) else { return .failed(AuthError(message: Self.sessionWriteFailureMessage)) }
                show("Account created"); Task { await syncNow() }
                BetaQA.shared.pass("A-AUTH-01", note: "Signed up and signed in")
                return .signedIn
            }
            pendingConfirmation = email
            BetaQA.shared.set("A-AUTH-01", .untested, note: "Confirmation email sent — open the link to finish", auto: true)
            return .confirmationSent
        } catch {
            let e = AuthError.network(error)
            if e.kind == .weakPassword || e.kind == .userExists { BetaQA.shared.pass("A-AUTH-02", note: "Friendly error: \(e.message)") }
            else { BetaQA.shared.fail("A-AUTH-01", error: "Sign up: \(e.message)") }
            return .failed(e)
        }
    }

    func sendMagicLink(email: String) async -> AuthError? {
        guard let auth else { return nil }
        do { try await auth.sendMagicLink(email: email.trimmingCharacters(in: .whitespaces)); BetaQA.shared.magicLinkSent = true; return nil }
        catch { let e = AuthError.network(error); BetaQA.shared.fail("A-AUTH-04", error: "Send magic link: \(e.message)"); return e }
    }

    func resendConfirmation() async -> AuthError? {
        guard let auth, let email = pendingConfirmation else { return nil }
        do { try await auth.resendConfirmation(email: email); return nil } catch { return AuthError.network(error) }
    }

    func recoverPassword(email: String) async -> AuthError? {
        guard let auth else { return nil }
        do { try await auth.recoverPassword(email: email.trimmingCharacters(in: .whitespaces)); return nil }
        catch { let e = AuthError.network(error); BetaQA.shared.fail("A-AUTH-05", error: "Reset email: \(e.message)"); return e }
    }

    func setNewPassword(_ password: String) async -> AuthError? {
        guard let auth, let s = session else { return AuthError(.unauthorized, "Open the reset link again.") }
        do { try await auth.updatePassword(s, to: password); show("Password updated"); BetaQA.shared.pass("A-AUTH-05", note: "Reset link opened and new password set"); return nil }
        catch { let e = AuthError.network(error); BetaQA.shared.fail("A-AUTH-05", error: "Set new password: \(e.message)"); return e }
    }

    func signOut(removeLocalData: Bool = false) async {
        // Unified graph: refuse an unbound wipe exactly as before; bound wipes report
        // per-component partial failure honestly instead of claiming a clean wipe.
        if foodJournalRuntime != nil && removeLocalData && (journalWriterEffect == nil || journalWriterValidator == nil) {
            show("The unified Journal reset is not ready. Nothing was cleared.", error: true); return
        }
        let capturedSession = session
        if let s = session { await auth?.signOut(s) }
        // Post-await guard: a reset or account change during the server sign-out abandons the
        // local publish instead of wiping under a stale session or epoch.
        guard validatePostAwaitPublish(capturedSession: capturedSession) else {
            show("Signed out on the server, but this iPhone's data changed before the app could finish. Check Settings, then try again.", error: true)
            return
        }
        syncTask?.cancel()
        guard setSession(nil) else {
            show("Signed out on the server, but this iPhone couldn't finish updating its sign-in. Check Settings, then try again.", error: true)
            return
        }
        syncState = .signedOut
        var partial: [String] = []
        if removeLocalData {
            if foodJournalRuntime != nil {
                let report = wipeLocalDataUnified()
                partial = report.complete ? [] : report.failures.map(\.component)
            } else {
                wipeLocalData()
            }
        }
        BetaQA.shared.signedOut(removeLocalData: removeLocalData, remaining: recipes.count)
        if !partial.isEmpty {
            show("Signed out, but some data on this device could not be removed: \(partial.joined(separator: ", "))", error: true)
        } else {
            show(removeLocalData ? "Signed out and removed this iPhone's copy" : "Signed out — your recipes stay on this device")
        }
    }

    /// Permanently deletes the account on the server, then all local data, then shows onboarding.
    func deleteAccount() async -> AuthError? {
        // Unified graph: refuse only while the writer boundary is unbound. Once bound,
        // the account is deleted server-side first; a partial local wipe is reported
        // honestly and cannot resurrect the account.
        if foodJournalRuntime != nil && (journalWriterEffect == nil || journalWriterValidator == nil) {
            return AuthError(message: "The unified Journal reset is not ready. Your account has not been deleted.")
        }
        guard let auth, var s = session else { return AuthError(.unauthorized, "Sign in again to delete your account.") }
        let capturedSession = session
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 {
                s = try await auth.refresh(s)
                guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                    return AuthError(message: "This iPhone's data changed while your account was being deleted. Your account has not been deleted - try again.")
                }
            }
            try await auth.deleteAccount(s)
        } catch { let e = AuthError.network(error); BetaQA.shared.fail("A-AUTH-08", error: e.message); return e }
        // The account is gone on the server; the local wipe publishes only while the session
        // and epoch captured above are still current.
        guard validatePostAwaitPublish(capturedSession: capturedSession) else {
            return AuthError(message: "Your account was deleted on the server, but this iPhone's data changed before its local copy could be removed. Use Clear all in Settings to remove it.")
        }
        syncTask?.cancel()
        guard setSession(nil) else {
            return AuthError(message: "Your account was deleted on the server, but this iPhone couldn't finish updating its sign-in or removing its local copy. Check Settings and use Clear all.")
        }
        syncState = .signedOut
        var partial: [String] = []
        if foodJournalRuntime != nil {
            let report = wipeLocalDataUnified()
            partial = report.complete ? [] : report.failures.map(\.component)
        } else {
            wipeLocalData()
        }
        path.removeAll()
        if !AppConfig.isUITesting { UserDefaults.standard.removeObject(forKey: Self.onboardedKey) }
        showOnboarding = true
        if !partial.isEmpty {
            show("Your account was deleted, but some data on this device could not be removed: \(partial.joined(separator: ", "))", error: true)
        } else {
            BetaQA.shared.pass("A-AUTH-08", note: "Account deleted on the server and locally")
            show("Your account and data were deleted")
        }
        return nil
    }

    // Internal (not private) for AppStore+JournalAccountActions.
    func wipeLocalData() {
        performOrdinaryWrite(Self.ordinaryWriteFailureMessage) {
            InsightLifecycleStore.clearAll()
            clearCookCompletionContext()
            recipes = []; shopping = []
            nutritionDiaryRepository.clear()
            try? nutritionGoalsRepository.save(DailyNutritionGoals())
            CookingHistory.shared.clear()
            tab = .library; path = []; shoppingPath = []; settingsPath = []; morePath = []; searchPath = []
            persistRecipes(stamp: false); persistShopping(stamp: false)
            meta = SyncMeta(); saveDefaults(meta, key: "ate.sync.v1")
            recipeSnapshot = [:]; shopSnapshot = [:]
            for t in timers.timers { timers.stop(t.id) }
        }
    }

    // MARK: deep links
    func openJournalEntry(_ id: String) {
        // More is not a shipped tab. Keep journal deep links inside the visible Tracker navigation stack.
        select(.tracker)
        trackerPath = [.journalEntry(id)]   // Journal is the Journal tab root
    }

    /// The named "Insights & Cooking History" route, pushed above the Journal root of the Journal tab.
    func openInsightsHub() {
        select(.tracker)
        trackerPath = [.insights]
    }

    func handle(url: URL) {
        if url.scheme == "ate", url.host == "import" { checkInbox(); return }
        if url.scheme == "ate", url.host == "open", url.pathComponents.filter({ $0 != "/" }).isEmpty { return }   // "Open ate" placeholder
        if let target = WidgetLinks.parse(url) {
            switch target {
            case .recipe(let id):
                select(.library); cookTarget = nil
                path = [.recipe(id)]   // a deleted recipe shows "Recipe not found" with a working Back
                BetaQA.shared.pass("A-WIDGET-02", note: "Opened a recipe from a widget/Spotlight")
            case .cook(let id):
                guard recipe(id) != nil else { select(.library); return }   // quick timers have no recipe
                select(.library); cookTarget = CookTarget(id: id)
            case .add(let m):
                select(.library); path = []; cookTarget = nil
                quickAdd = QuickAddRequest(mode: m)
                BetaQA.shared.pass("A-WIDGET-04", note: "Quick add opened Add recipe (\(m.rawValue))")
            case .shopping: select(.shopping)
            case .timers: break
            }
            return
        }
        if url.scheme == "ate", url.host == "auth-callback" {
            tab = .settings
            let capturedSession = session
            Task {
                do {
                    switch try await auth?.session(fromCallback: url) {
                    case .signedIn(let s)?:
                        guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                            show("This iPhone's data changed while signing in. Open the link again.", error: true)
                            return
                        }
                        guard setSession(s) else { return }
                        pendingConfirmation = nil; authSheet = nil
                        BetaQA.shared.authLinkSignedIn(email: s.email)
                        if showOnboarding { finishOnboarding() }
                        show("Signed in"); await syncNow()
                    case .recovery(let s)?:
                        guard validatePostAwaitPublish(capturedSession: capturedSession) else {
                            show("This iPhone's data changed while opening the reset link. Open the link again.", error: true)
                            return
                        }
                        guard setSession(s) else { return }
                        if showOnboarding { finishOnboarding() }
                        authSheet = .newPassword
                    case .confirmedNeedsSignIn?:
                        pendingConfirmation = nil
                        show("Email confirmed — sign in with your password")
                        authSheet = .signIn
                    case nil: show("That sign-in link didn't work. Request a new one.", error: true)
                    }
                } catch {
                    let m = AuthError.network(error).message
                    BetaQA.shared.fail(BetaQA.shared.magicLinkSent ? "A-AUTH-04" : "A-AUTH-01", error: "Email link: \(m)")
                    show(m, error: true)
                }
            }
            return
        }
        let slug = ShareLinks.slug(from: url)   // ate://recipe|r/<slug>, <host>/r/<slug>, <host>/r/?s=<slug>
        tab = .library
        if let slug { path = [.shared(slug)]; BetaQA.shared.pass("A-SHARE-02", note: "Opened \(url.scheme ?? "")://… shared link \(slug)") }
        else { path = [.notFound] }
    }
}


/// Field validation for the shopping edit sheet: an empty quantity means "no amount",
/// otherwise it must be a finite, non-negative number; a name must survive trimming.
enum ShoppingEdit {
    /// Locale-independent: "." and "," both mean the decimal separator (the decimal pad offers
    /// only one of them per locale), grouping and exponents are not accepted. This avoids the
    /// locale-parser trap where de_DE reads "2.5" as 25 - a silent tenfold data change.
    static func parseQuantity(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Initial text for the quantity field: empty for "no amount", otherwise plain decimal
    /// (always ".", no grouping, no scientific notation), so parseQuantity(quantityText(q)) == q
    /// exactly in every locale for ordinary quantities. A locale formatter would re-display
    /// rounded digits and a re-save would silently change the stored value. Extreme legacy
    /// values print in plain decimal too, so the field is never seeded with text it rejects.
    static func quantityText(_ quantity: Double) -> String {
        if quantity == 0 { return "" }
        var s = String(quantity)
        if s.contains("e") || s.contains("E") {
            // String(Double) switches to scientific notation beyond ordinary magnitudes; the
            // field accepts plain decimal only.
            s = String(format: "%.10f", quantity)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s
    }

    /// The quantity to store from the editor: the original when the field is untouched, so a
    /// name-only edit is never trapped by an unparseable legacy value; otherwise the parsed
    /// text (nil while the edited text is invalid, which keeps Save disabled).
    static func effectiveQuantity(original: Double, originalText: String, editedText: String) -> Double? {
        if editedText == originalText { return original }
        return parseQuantity(editedText)
    }

    static func trimmedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


enum JournalIntentOwnerError: LocalizedError {
    case appNotOpen, notDurable, saveFailed
    var errorDescription: String? {
        switch self {
        case .appNotOpen: return "Open Ate before using this Journal shortcut."
        case .notDurable: return "The Journal is not available for a durable save. Open Ate to review storage recovery."
        case .saveFailed: return "The Journal entry could not be saved. Review the Journal before trying again."
        }
    }
}
