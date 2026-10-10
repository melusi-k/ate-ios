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
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@Observable
@MainActor
final class AppStore {
    var recipes: [RecipeCard] = []
    var shopping: [ShoppingItem] = []
    /// Library tab's navigation stack (recipes, shared links, not-found).
    var path: [Route] = []
    var shoppingPath: [Route] = []
    var settingsPath: [Route] = []
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

    func toggleFavourite(_ id: String) {
        guard var r = recipe(id) else { return }
        r.favorite.toggle(); update(r)
        show(r.favorite ? "Added to Favourites" : "Removed from Favourites")
        Haptics.toggle()
    }

    func markCooked(_ id: String) {
        guard var r = recipe(id) else { return }
        r.lastCookedAt = (Date().timeIntervalSince1970 * 1000).rounded(); update(r)
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
    }

    // MARK: persistence
    private func load() {
        guard let context else { return }
        let dec = JSONDecoder()
        let r = (try? context.fetch(FetchDescriptor<RecipeEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        recipes = r.compactMap { try? dec.decode(RecipeCard.self, from: $0.json) }
        let s = (try? context.fetch(FetchDescriptor<ShoppingEntity>(sortBy: [SortDescriptor(\.position)]))) ?? []
        shopping = s.compactMap { try? dec.decode(ShoppingItem.self, from: $0.json) }
    }

    private func persistRecipes(stamp: Bool = true) {
        if stamp { stampChanges() }
        guard let context else { return }
        try? context.delete(model: RecipeEntity.self)
        let enc = JSONEncoder()
        for (i, c) in recipes.enumerated() {
            if let d = try? enc.encode(c) { context.insert(RecipeEntity(id: c.id, createdAt: c.createdAt, position: i, json: d)) }
        }
        try? context.save()
    }

    private func persistShopping(stamp: Bool = true) {
        if stamp { stampChanges() }
        guard let context else { return }
        try? context.delete(model: ShoppingEntity.self)
        let enc = JSONEncoder()
        for (i, it) in shopping.enumerated() {
            if let d = try? enc.encode(it) { context.insert(ShoppingEntity(id: it.id, position: i, json: d)) }
        }
        try? context.save()
    }

    private func saveDefaults<T: Encodable>(_ v: T, key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func loadDefaults<T: Decodable>(_ t: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: toasts
    func show(_ message: String, error: Bool = false) {
        let t = Toast(message: message, isError: error)
        withAnimation { toast = t }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast?.id == t.id { withAnimation { toast = nil } }
        }
    }

    // MARK: recipes
    func recipe(_ id: String) -> RecipeCard? { recipes.first { $0.id == id } }

    func add(_ card: RecipeCard) {
        recipes.insert(RecipeLogic.normalize(card), at: 0)
        persistRecipes()
    }

    func update(_ card: RecipeCard) {
        guard let i = recipes.firstIndex(where: { $0.id == card.id }) else { return }
        recipes[i] = card
        persistRecipes()
    }

    func delete(_ id: String) {
        recipes.removeAll { $0.id == id }
        persistRecipes()
    }

    func clearLibrary() { recipes = []; persistRecipes() }

    func importJSON(_ data: Data) throws -> Int {
        let cards = try JSONDecoder().decode([RecipeCard].self, from: data)
        let res = RecipeLogic.importCards(cards, into: recipes)
        recipes = res.result
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
    func removeItem(_ id: String) { shopping.removeAll { $0.id == id }; persistShopping() }
    func clearTicked() { shopping.removeAll { $0.done }; persistShopping() }
    func clearShopping() { shopping = []; persistShopping() }

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

    func syncNow() async {
        guard var s = session, let sync, let auth else { syncState = .signedOut; return }
        syncState = .syncing
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 { s = try await auth.refresh(s); setSession(s) }
            let remote = try await sync.pull(session: s)
            let enc = JSONEncoder()
            let dec = JSONDecoder()

            let r = SyncMerge.merge(local: .init(data: recipes.reduce(into: [:]) { $0[$1.id] = try? enc.encode($1) },
                                                 stamps: meta.recipeStamps, tombstones: meta.recipeTombs),
                                    remote: remote.filter { $0.kind == "recipe" })
            let sh = SyncMerge.merge(local: .init(data: shopping.reduce(into: [:]) { $0[$1.id] = try? enc.encode($1) },
                                                  stamps: meta.shopStamps, tombstones: meta.shopTombs),
                                     remote: remote.filter { $0.kind == "shopping" })

            recipes = r.data.values.compactMap { try? dec.decode(RecipeCard.self, from: $0) }.sorted { $0.createdAt > $1.createdAt }
            let newShop = sh.data.compactMapValues { try? dec.decode(ShoppingItem.self, from: $0) }
            var ordered = shopping.compactMap { newShop[$0.id] }
            for (id, it) in newShop where !ordered.contains(where: { $0.id == id }) { ordered.append(it) }
            shopping = ordered
            meta.recipeStamps = r.stamps; meta.recipeTombs = r.tombstones
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
        } catch SyncError.tableMissing {
            syncState = .unavailable(SyncError.tableMissing.errorDescription ?? "")
        } catch SyncError.unauthorized {
            syncState = .failed("session expired — sign in again")
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    private func setSession(_ s: AuthSession?) {
        session = s
        Keychain.save(s.flatMap { try? JSONEncoder().encode($0) }, account: "session")
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
            setSession(try await auth.signIn(email: email, password: password))
            pendingConfirmation = nil
            show("Signed in")
            Task { await syncNow() }
            return nil
        } catch {
            let e = AuthError.network(error)
            if e.kind == .emailNotConfirmed { pendingConfirmation = email }
            return e
        }
    }

    func signUp(email: String, password: String) async -> SignUpOutcome {
        guard let auth else { return .failed(AuthError(message: "Accounts aren't configured in this build.")) }
        let email = email.trimmingCharacters(in: .whitespaces)
        do {
            if let s = try await auth.signUp(email: email, password: password) {
                setSession(s); show("Account created"); Task { await syncNow() }
                return .signedIn
            }
            pendingConfirmation = email
            return .confirmationSent
        } catch { return .failed(AuthError.network(error)) }
    }

    func sendMagicLink(email: String) async -> AuthError? {
        guard let auth else { return nil }
        do { try await auth.sendMagicLink(email: email.trimmingCharacters(in: .whitespaces)); return nil }
        catch { return AuthError.network(error) }
    }

    func resendConfirmation() async -> AuthError? {
        guard let auth, let email = pendingConfirmation else { return nil }
        do { try await auth.resendConfirmation(email: email); return nil } catch { return AuthError.network(error) }
    }

    func recoverPassword(email: String) async -> AuthError? {
        guard let auth else { return nil }
        do { try await auth.recoverPassword(email: email.trimmingCharacters(in: .whitespaces)); return nil }
        catch { return AuthError.network(error) }
    }

    func setNewPassword(_ password: String) async -> AuthError? {
        guard let auth, let s = session else { return AuthError(.unauthorized, "Open the reset link again.") }
        do { try await auth.updatePassword(s, to: password); show("Password updated"); return nil }
        catch { return AuthError.network(error) }
    }

    func signOut(removeLocalData: Bool = false) async {
        if let s = session { await auth?.signOut(s) }
        syncTask?.cancel()
        setSession(nil)
        syncState = .signedOut
        if removeLocalData { wipeLocalData() }
        show(removeLocalData ? "Signed out and removed this iPhone's copy" : "Signed out — your recipes stay on this device")
    }

    /// Permanently deletes the account on the server, then all local data, then shows onboarding.
    func deleteAccount() async -> AuthError? {
        guard let auth, var s = session else { return AuthError(.unauthorized, "Sign in again to delete your account.") }
        do {
            if s.expiresAt < Date().timeIntervalSince1970 + 60 { s = try await auth.refresh(s) }
            try await auth.deleteAccount(s)
        } catch { return AuthError.network(error) }
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
        tab = .library; path = []; shoppingPath = []; settingsPath = []
        persistRecipes(stamp: false); persistShopping(stamp: false)
        meta = SyncMeta(); saveDefaults(meta, key: "ate.sync.v1")
        recipeSnapshot = [:]; shopSnapshot = [:]
        for t in timers.timers { timers.stop(t.id) }
    }

    // MARK: deep links
    func handle(url: URL) {
        if url.scheme == "ate", url.host == "import" { checkInbox(); return }
        if url.scheme == "ate", url.host == "auth-callback" {
            tab = .settings
            Task {
                do {
                    switch try await auth?.session(fromCallback: url) {
                    case .signedIn(let s)?:
                        setSession(s); pendingConfirmation = nil; authSheet = nil
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
                } catch { show(AuthError.network(error).message, error: true) }
            }
            return
        }
        if url.scheme == "ate", url.host == "cook", let id = url.pathComponents.last, recipe(id) != nil {
            tab = .library; cookTarget = CookTarget(id: id); return
        }
        var slug: String?
        if url.scheme == "ate" {
            let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
            // ate://recipe/<slug> (canonical) and ate://r/<slug> (alias)
            if let f = parts.first, f == "recipe" || f == "r", parts.count > 1 { slug = parts[1] }
        } else if url.pathComponents.count >= 3, url.pathComponents[1] == "r" || url.pathComponents[1] == "recipe" {
            slug = url.pathComponents[2]
        }
        tab = .library
        if let slug { path = [.shared(slug)] } else { path = [.notFound] }
    }
}
