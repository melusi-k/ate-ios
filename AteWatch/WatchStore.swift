import Foundation
import Observation
import WatchConnectivity
import WatchKit
import WidgetKit

/// Watch-side state: Supabase session, offline cache, REST sync and the phone bridge.
@Observable
@MainActor
final class WatchStore: NSObject {
    var session: WatchBridgePayload.Session?
    var recipes: [WatchRecipe] = []
    var shopping: [WatchShoppingItem] = []
    var phoneCook: [WatchBridgePayload.CookMirror] = []
    var status: String?
    var loading = false
    var pendingEmail: String?

    private let base: URL? = (Bundle.main.object(forInfoDictionaryKey: "AteSupabaseURL") as? String).flatMap(URL.init(string:))
    private let key = (Bundle.main.object(forInfoDictionaryKey: "AteSupabasePublishableKey") as? String) ?? ""
    private let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-cache.json")
    private struct Cache: Codable { var recipes: [WatchRecipe]; var shopping: [WatchShoppingItem] }

    /// Writer seam (#245, lane 3): production watch wiring injects the real boundary
    /// before ordinary use; `.legacy` preserves today's behavior exactly.
    @ObservationIgnored var writerBoundary: WatchWriterBoundary = .legacy

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: "ate.watch.session") { session = try? JSONDecoder().decode(WatchBridgePayload.Session.self, from: d) }
        if let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: d) { recipes = c.recipes; shopping = c.shopping }
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    var signedIn: Bool { session != nil }

    private func setSession(_ s: WatchBridgePayload.Session?) {
        try? writerBoundary.withEffect {
            // A session change invalidates every in-flight network result (epoch fence).
            writerBoundary.invalidateEpoch()
            session = s
            UserDefaults.standard.set(s.flatMap { try? JSONEncoder().encode($0) }, forKey: "ate.watch.session")
        }
    }
    private func saveCache() {
        try? writerBoundary.withEffect {
            if let d = try? JSONEncoder().encode(Cache(recipes: recipes, shopping: shopping)) { try? d.write(to: cacheURL, options: .atomic) }
        }
    }

    // MARK: HTTP
    private func send(_ url: URL, method: String = "POST", body: Any?, bearer: String? = nil, prefer: String? = nil) async throws -> Data {
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "apikey")
        if let bearer { r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (d, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            throw NSError(domain: "ate", code: code, userInfo: [NSLocalizedDescriptionKey:
                (j?["msg"] as? String) ?? (j?["error_description"] as? String) ?? (j?["message"] as? String) ?? "Request failed (\(code))"])
        }
        return d
    }
    private func parseSession(_ d: Data) -> WatchBridgePayload.Session? {
        guard let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let at = j["access_token"] as? String, let rt = j["refresh_token"] as? String,
              let u = j["user"] as? [String: Any], let id = u["id"] as? String else { return nil }
        let exp = (j["expires_at"] as? Double) ?? Date().timeIntervalSince1970 + ((j["expires_in"] as? Double) ?? 3600)
        return .init(accessToken: at, refreshToken: rt, expiresAt: exp, userID: id, email: (u["email"] as? String) ?? "")
    }

    // MARK: Sign-in (email code)
    func requestCode(email: String) async {
        guard let base else { status = "Cloud isn't configured in this build."; return }
        let (url, body) = WatchAuthRequests.otp(base: base, email: email)
        do { _ = try await send(url, body: body); pendingEmail = email; status = "Code sent to \(email)" }
        catch { status = error.localizedDescription }
    }
    func verify(code: String) async {
        guard let base, let email = pendingEmail else { return }
        let (url, body) = WatchAuthRequests.verify(base: base, email: email, code: code)
        let epoch = writerBoundary.captureEpoch()
        do {
            let d = try await send(url, body: body)
            guard let s = parseSession(d) else { status = "Couldn't read the session."; return }
            // Epoch re-check after the network await: a sign-out during verification
            // must not be undone by the stale reply.
            guard (try? writerBoundary.validateEpoch(epoch)) != nil else { return }
            setSession(s); pendingEmail = nil; status = nil
            await refresh()
        } catch { status = error.localizedDescription }
    }
    func signOut() {
        try? writerBoundary.withEffect {
            setSession(nil); recipes = []; shopping = []; saveCache()
        }
    }

    private func validToken() async -> String? {
        guard var s = session, let base else { return nil }
        if WatchAuthRequests.needsRefresh(expiresAt: s.expiresAt) {
            let epoch = writerBoundary.captureEpoch()
            guard let d = try? await send(WatchAuthRequests.refreshURL(base: base), body: ["refresh_token": s.refreshToken]),
                  let n = parseSession(d) else { status = "Session expired — sign in again."; return nil }
            // Epoch re-check after the network await: only the current session may be written.
            guard (try? writerBoundary.validateEpoch(epoch)) != nil else { return nil }
            s = n; setSession(n)
        }
        return s.accessToken
    }

    // MARK: Sync
    func refresh() async {
        let epoch = writerBoundary.captureEpoch()
        guard let base, let token = await validToken() else { return }
        loading = true; defer { loading = false }
        do {
            let d = try await send(WatchAuthRequests.rowsURL(base: base), method: "GET", body: nil, bearer: token)
            let rows = try JSONDecoder().decode([WatchRow].self, from: d)
            let out = WatchRows.decode(rows)
            // Epoch re-check after the network await: a session change mid-flight owns
            // the state via its own refresh; the stale result is dropped, and the UI
            // must not claim the cache is merely offline.
            try writerBoundary.validateEpoch(epoch)
            try writerBoundary.withEffect {
                recipes = out.recipes; shopping = out.shopping; saveCache(); status = nil
            }
        } catch WatchWriterBoundary.Failure.staleEpoch {
            // Dropped stale result: the current session's refresh owns the state.
        } catch WatchWriterBoundary.Failure.effectNotPerformed, WatchWriterBoundary.Failure.repeatedEffect {
            // A boundary defect is not a network failure: never claim "offline".
            status = "Couldn't refresh your recipes. Try again."
        } catch { status = "Offline — showing saved recipes." }
    }

    func toggle(_ item: WatchShoppingItem) async {
        let (n, row) = WatchRows.toggled(item, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        try? writerBoundary.withEffect {
            if let i = shopping.firstIndex(where: { $0.id == item.id }) { shopping[i] = n }
            saveCache()
        }
        WKInterfaceDevice.current().play(.click)
        guard let base, let s = session, let token = await validToken() else { return }
        let epoch = writerBoundary.captureEpoch()
        let body: [String: Any] = ["user_id": s.userID, "kind": "shopping", "id": row.id,
                                   "data": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(row.data))) ?? NSNull(),
                                   "updated_at": row.updated_at, "deleted": false]
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/user_recipes"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,kind,id")]
        _ = try? await send(c.url!, body: [body], bearer: token, prefer: "resolution=merge-duplicates,return=minimal")
        // Epoch re-check after the network await: the remote write already happened and
        // is never rolled back, but a session change mid-flight leaves the optimistic
        // local state suspect - reconcile it to the server instead of keeping it.
        if (try? writerBoundary.validateEpoch(epoch)) == nil { await refresh() }
    }

    fileprivate func apply(_ p: WatchBridgePayload) {
        try? writerBoundary.withEffect {
            if p.signedOut { signOut() }
            if let s = p.session, s != session { setSession(s); Task { await refresh() } }
            phoneCook = p.cook
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in if let p = WatchBridgePayload.from(ctx) { self.apply(p) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in if let p = WatchBridgePayload.from(ctx) { self.apply(p) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in if let p = WatchBridgePayload.from(message) { self.apply(p) } }
    }
}

/// Keeps step timers alive with the screen down (WKExtendedRuntimeSession) and plays a haptic on finish.
@Observable
@MainActor
final class WristTimer: NSObject, WKExtendedRuntimeSessionDelegate {
    var timer: WatchStepTimer? { didSet { WatchTimerStore.save(timer); WidgetCenter.shared.reloadAllTimelines() } }
    var now = Date()
    private var runtime: WKExtendedRuntimeSession?
    private var ticker: Timer?

    override init() { super.init(); timer = WatchTimerStore.load() }

    func start(title: String, step: Int, seconds: Int) {
        timer = .start(title: title, step: step, seconds: seconds)
        beginRuntime(); startTicking()
    }
    func pauseResume() {
        guard var t = timer else { return }
        if t.endDate == nil { t.resume() } else { t.pause() }
        timer = t
    }
    func cancel() { timer = nil; runtime?.invalidate(); runtime = nil; ticker?.invalidate() }

    private func beginRuntime() {
        runtime?.invalidate()
        let s = WKExtendedRuntimeSession(); s.delegate = self; s.start(); runtime = s
    }
    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        now = Date()
        guard let t = timer, t.isFinished(at: now) else { return }
        let device = WKInterfaceDevice.current()
        device.play(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { device.play(.notification) }
        timer = nil; ticker?.invalidate(); runtime?.invalidate(); runtime = nil
    }

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in WKInterfaceDevice.current().play(.retry) }
    }
    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
}
