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

@Observable
@MainActor
final class AppStore {
    /// The live store, for App Intents that run in the app's process.
    static weak var current: AppStore?
    /// Set by the Quick add widget / control / intent: opens Add recipe on the matching tab.
    var quickAdd: QuickAddRequest?
    /// Set by the system search intent ("Search ate for tripe"): Library adopts it as its query.
    var pendingSearch: String?
    func search(_ term: String) {
        select(.library); path = []
        pendingSearch = term.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var recipes: [RecipeCard] = []
    var shopping: [ShoppingItem] = []
    /// Library tab's navigation stack (recipes, shared links, not-found).
    var path: [Route] = []
    var shoppingPath: [Route] = []
    var settingsPath: [Route] = []
    var morePath: [Route] = []
    /// Set when the local store had to be repaired at launch (shows the recovery screen).
    var recovery: RecoveryInfo?
    /// iOS 26 search tab (Tab(role: .search)) has its own stack.
    var searchPath: [Route] = []
    /// True when the selected tab shows its root screen (banners that belong to tab roots hide on pushed screens).
    var isAtTabRoot: Bool {
        switch tab {
        case .library, .collection: return path.isEmpty
        case .shopping: return shoppingPath.isEmpty
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
        didSet { if !AppConfig.isUITesting { filter.save() } }
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
            self.recipes.insert(r, at: min(idx, self.recipes.count)); self.persistRecipes()
            BetaQA.shared.pass("A-EDIT-04", note: "Deleted “\(r.title)” and restored it with Undo")
            self.toast = nil
        }, seconds: 5)
    }

    func runToastAction() { let a = toastAction; toastAction = nil; a?() }

    var layout: LibraryLayout = AppConfig.isUITesting ? LibraryLayout() : LibraryLayout.load() {
        didSet { if !AppConfig.isUITesting { layout.save() } }
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
        for (i, id) in ids.enumerated() {
            if let k = recipes.firstIndex(where: { $0.id == id }) { recipes[k].sortIndex = Double(i) }
        }
        persistRecipes()
        layout.sort = .myOrder
        Haptics.step()
    }

    func toggleFavourite(_ id: String) {
        guard var r = recipe(id) else { return }
        r.favorite.toggle(); update(r)
        show(r.favorite ? "Added to Favourites" : "Removed from Favourites")
        Haptics.toggle()
    }

    func markCooked(_ id: String) {
        guard var r = recipe(id) else { return }
        r.lastCookedAt = (Date().timeIntervalSince1970 * 1000).rounded(); update(r)
        CookingHistory.shared.record(recipeID: id)
    }

    /// Picks up the next item queued by the share extension (called when the app becomes active).
    func checkInbox() {
        guard pendingImport == nil, let item = SharedInbox.pop() else { return }
        tab = .library; path = []; pendingImport = item
    }
    var toast: Toast?
    var settings: AppSettings { didSet { saveDefaults(settings, key: "ate.settings.v1") } }
    var timerPrefs: TimerPrefs { didSet { saveDefaults(timerPrefs, key: "ate.timerprefs.v1") } }

    var cookTarget: CookTarget?
    let timers = TimerCenter()

    // Onboarding & auth UI
    var showOnboarding = false
    var authSheet: AuthMode?
    var pendingConfirmation: String?   // email awaiting confirmation

    // Accounts & sync
    var session: AuthSession?
    var syncState: SyncState = .signedOut
    let auth: AuthService?
    let sync: SyncService?
    private var meta = SyncMeta()
    private var recipeSnapshot: [String: RecipeCard] = [:]
    private var shopSnapshot: [String: ShoppingItem] = [:]
    private var syncTask: Task<Void, Never>?

    let backend: BackendService
    private let context: ModelContext?

    init(context: ModelContext?, backend: BackendService = AppConfig.makeBackend()) {
        self.context = context
        self.backend = backend
        if AppConfig.isUITesting {
            auth = MockAuth(); sync = MockSync()
        } else if let url = AppConfig.supabaseURL, !AppConfig.supabasePublishableKey.isEmpty {
            auth = SupabaseAuth(baseURL: url, key: AppConfig.supabasePublishableKey)
            sync = SupabaseSync(baseURL: url, key: AppConfig.supabasePublishableKey)
        } else { auth = nil; sync = nil }
        settings = Self.loadDefaults(AppSettings.self, key: "ate.settings.v1") ?? AppSettings()
        timerPrefs = Self.loadDefaults(TimerPrefs.self, key: "ate.timerprefs.v1") ?? TimerPrefs()
        if AppConfig.isUITesting { UserDefaults.standard.removeObject(forKey: "ate.sync.v1"); Keychain.save(nil, account: "session") }
        meta = Self.loadDefaults(SyncMeta.self, key: "ate.sync.v1") ?? SyncMeta()
        session = Keychain.load(account: "session").flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
        syncState = session == nil ? .signedOut : .idle
        showOnboarding = AppConfig.isUITesting ? ProcessInfo.processInfo.arguments.contains("-showOnboarding")
                                               : !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        load()
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

    // MARK: persistence
    private func load() {
        guard let context else { return }
        let dec = JSONDecoder()
        let r = (try? context.fetch(FetchDescriptor<RecipeEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        let loaded = r.compactMap { try? dec.decode(RecipeCard.self, from: $0.json) }
        // Repairs saved recipes: blank steps, implausible times (flagged), duplicate saves (P0, build 81).
        let dd = RecipeLogic.dedupe(loaded.map(RecipeLogic.normalize))
        recipes = dd.cards
        if recipes != loaded {
            let t = nowMs(), before = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for c in recipes where before[c.id] != c { meta.recipeStamps[c.id] = t }          // repaired copies sync up
            for id in dd.removedIDs where !recipes.contains(where: { $0.id == id }) { meta.recipeTombs[id] = t; meta.recipeStamps[id] = nil }
            saveDefaults(meta, key: "ate.sync.v1")
            persistRecipes(stamp: false)
        }
        let s = (try? context.fetch(FetchDescriptor<ShoppingEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        shopping = s.compactMap { try? dec.decode(ShoppingItem.self, from: $0.json) }
    }

    private func persistRecipes(stamp: Bool = true) {
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

    private func persistShopping(stamp: Bool = true) {
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
        let c = RecipeLogic.normalize(card)
        if let i = recipes.firstIndex(where: { $0.id == c.id }) { recipes[i] = c } else { recipes.insert(c, at: 0) }
        DraftStore.shared.clear()
        persistRecipes()
    }

    func update(_ card: RecipeCard) {
        guard let i = recipes.firstIndex(where: { $0.id == card.id }) else { return }
        recipes[i] = RecipeLogic.normalize(card)
        persistRecipes()
        BetaQA.shared.pass("A-EDIT-03", note: "Edited “\(card.title)” without a crash")
    }

    /// Cover changed (file and/or remote URL). Not an "edit" for QA purposes.
    func setCover(_ id: String, file: String?, imageURL: String?, keepURL: Bool = true) {
        guard let i = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[i].coverImage = file
        if let imageURL { recipes[i].imageURL = imageURL } else if !keepURL { recipes[i].imageURL = nil }
        persistRecipes()
    }

    func delete(_ id: String) {
        CoverStore.shared.removeFiles(recipeID: id)
        recipes.removeAll { $0.id == id }
        persistRecipes()
    }

    func clearLibrary() { recipes = []; CookingHistory.shared.clear(); path = []; persistRecipes() }

    func importJSON(_ data: Data) throws -> Int {
        let cards = try JSONDecoder().decode([RecipeCard].self, from: data)
        let res = RecipeLogic.importCards(cards, into: recipes)
        recipes = res.result.map(RecipeLogic.normalize)
        persistRecipes()
        return res.added
    }

    func exportJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(recipes)) ?? Data("[]".utf8)
    }

    // MARK: shopping
    func addToShopping(_ card: RecipeCard, factor: Double) {
        shopping = ShoppingLogic.merge(RecipeLogic.scaled(card, factor: factor).ingredients, source: card.title, into: shopping)
        persistShopping()
    }
    func addManual(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        shopping.append(ShoppingItem(name: n, quantity: 0, unit: "", aisle: ShoppingLogic.guessAisle(n)))
        persistShopping()
    }
    func toggle(_ id: String) {
        guard let i = shopping.firstIndex(where: { $0.id == id }) else { return }
        shopping[i].done.toggle(); persistShopping()
    }
    /// Widget checkbox (idempotent: carries the wanted state, not a toggle).
    func setShoppingDone(_ id: String, _ done: Bool) {
        guard let i = shopping.firstIndex(where: { $0.id == id }), shopping[i].done != done else { return }
        shopping[i].done = done; persistShopping()
    }
    func removeItem(_ id: String) { shopping.removeAll { $0.id == id }; persistShopping() }
    func clearTicked() { shopping.removeAll { $0.done }; persistShopping() }
    func clearShopping() { shopping = []; shoppingPath = []; persistShopping() }

    // MARK: sync bookkeeping (last-write-wins)
    private func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private func stampChanges() {
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
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 {
                do { s = try await auth.refresh(s); setSession(s); BetaQA.shared.pass("A-AUTH-06", note: "Session refreshed before sync") }
                catch let e as AuthError where e.kind == .unauthorized { expireSession(); return }
            }
            if SyncMerge.isAccountSwitch(lastSyncedUser: meta.userID, newUser: s.userID) {
                // The previous account's copy is safe on the server; don't leak it into this one.
                recipes = []; shopping = []; recipeSnapshot = [:]; shopSnapshot = [:]
                persistRecipes(stamp: false); persistShopping(stamp: false)
                meta = SyncMeta()
                BetaQA.shared.pass("A-SYNC-05", note: "Account switch detected; previous account's copy removed")
                show("Switched accounts — the other account's recipes were removed from this iPhone (they're still in that account).")
            }
            meta.userID = s.userID
            let remote = try await sync.pull(session: s)
            BetaQA.shared.syncPulled(rows: remote.count)
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
            var out: [SyncRecord] = []
            out += r.push.map { rec("recipe", $0, r.data[$0], r.stamps[$0] ?? nowMs(), false) }
            out += r.pushDeletes.map { rec("recipe", $0, nil, r.tombstones[$0] ?? nowMs(), true) }
            out += sh.push.map { rec("shopping", $0, sh.data[$0], sh.stamps[$0] ?? nowMs(), false) }
            out += sh.pushDeletes.map { rec("shopping", $0, nil, sh.tombstones[$0] ?? nowMs(), true) }
            try await sync.push(out, session: s)
            syncState = .synced(Date())
            BetaQA.shared.syncSucceeded(pushed: out.count)
        } catch SyncError.tableMissing {
            syncState = .unavailable(SyncError.tableMissing.errorDescription ?? "")
        } catch SyncError.unauthorized {
            expireSession()
        } catch {
            syncState = .failed(error.localizedDescription)
            BetaQA.shared.syncFailed(Net.friendly(error))
        }
    }

    /// Session can't be refreshed: sign out locally (keep recipes) and say so plainly.
    var sessionExpired = false
    func expireSession() {
        setSession(nil)
        sessionExpired = true
        syncState = .failed(Self.sessionExpiredMessage)
        show(Self.sessionExpiredMessage, error: true)
    }
    static let sessionExpiredMessage = "Your session expired — sign in again to keep syncing. Your recipes are safe on this iPhone."

    private func setSession(_ s: AuthSession?) {
        if s != nil { sessionExpired = false }
        session = s
        Keychain.save(s.flatMap { try? JSONEncoder().encode($0) }, account: "session")
        PhoneWatchBridge.shared.update(session: s)
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
        do {
            let new = try await auth.signIn(email: email, password: password)
            setSession(new)
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
        do {
            if let s = try await auth.signUp(email: email, password: password) {
                setSession(s); show("Account created"); Task { await syncNow() }
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
        if let s = session { await auth?.signOut(s) }
        syncTask?.cancel()
        setSession(nil)
        syncState = .signedOut
        if removeLocalData { wipeLocalData() }
        BetaQA.shared.signedOut(removeLocalData: removeLocalData, remaining: recipes.count)
        show(removeLocalData ? "Signed out and removed this iPhone's copy" : "Signed out — your recipes stay on this device")
    }

    /// Permanently deletes the account on the server, then all local data, then shows onboarding.
    func deleteAccount() async -> AuthError? {
        guard let auth, var s = session else { return AuthError(.unauthorized, "Sign in again to delete your account.") }
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 { s = try await auth.refresh(s) }
            try await auth.deleteAccount(s)
        } catch { let e = AuthError.network(error); BetaQA.shared.fail("A-AUTH-08", error: e.message); return e }
        BetaQA.shared.pass("A-AUTH-08", note: "Account deleted on the server and locally")
        syncTask?.cancel()
        setSession(nil)
        syncState = .signedOut
        wipeLocalData()
        path.removeAll()
        if !AppConfig.isUITesting { UserDefaults.standard.removeObject(forKey: Self.onboardedKey) }
        showOnboarding = true
        show("Your account and data were deleted")
        return nil
    }

    private func wipeLocalData() {
        recipes = []; shopping = []
        CookingHistory.shared.clear()
        tab = .library; path = []; shoppingPath = []; settingsPath = []; morePath = []; searchPath = []
        persistRecipes(stamp: false); persistShopping(stamp: false)
        meta = SyncMeta(); saveDefaults(meta, key: "ate.sync.v1")
        recipeSnapshot = [:]; shopSnapshot = [:]
        for t in timers.timers { timers.stop(t.id) }
    }

    // MARK: deep links
    func openJournalEntry(_ id: String) {
        select(.more); morePath = [.journal, .journalEntry(id)]
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
            Task {
                do {
                    switch try await auth?.session(fromCallback: url) {
                    case .signedIn(let s)?:
                        setSession(s); pendingConfirmation = nil; authSheet = nil
                        BetaQA.shared.authLinkSignedIn(email: s.email)
                        if showOnboarding { finishOnboarding() }
                        show("Signed in"); await syncNow()
                    case .recovery(let s)?:
                        setSession(s); if showOnboarding { finishOnboarding() }
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
