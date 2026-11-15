import Foundation
import Observation
import WatchConnectivity
import WatchKit
import WidgetKit

/// Watch-side state: Supabase session, offline cache, REST sync and the phone bridge.
@Observable
@MainActor
final class WatchStore: NSObject {
    private(set) var session: WatchBridgePayload.Session?
    private var content: WatchOwnedContent
    var recipes: [WatchRecipe] { content.recipes }
    var shopping: [WatchShoppingItem] { content.shopping }
    var phoneCook: [WatchBridgePayload.CookMirror] = []
    var status: String?
    var loading = false
    var pendingEmail: String?

    private let base: URL? = (Bundle.main.object(forInfoDictionaryKey: "AteSupabaseURL") as? String).flatMap(URL.init(string:))
    private let key = (Bundle.main.object(forInfoDictionaryKey: "AteSupabasePublishableKey") as? String) ?? ""
    private let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-cache.json")

    /// Writer seam (#245, lane 3): production watch wiring injects the real boundary
    /// before ordinary use; `.legacy` preserves today's behavior exactly.
    @ObservationIgnored var writerBoundary = WatchWriterBoundary(perform: { try $0() })

    override init() {
        let saved = UserDefaults.standard.data(forKey: "ate.watch.session")
            .flatMap { try? JSONDecoder().decode(WatchBridgePayload.Session.self, from: $0) }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-cache.json")
        session = saved
        content = WatchOwnedContent(session: saved, cacheURL: url)
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    var signedIn: Bool { session != nil }

    @discardableResult
    private func setSession(_ next: WatchBridgePayload.Session?) -> Bool {
        do {
            try writerBoundary.withEffect {
                writerBoundary.invalidateEpoch()
                // Clear/quarantine before changing the visible identity. A disk
                // error leaves BOTH content and public identity signed out.
                session = nil; phoneCook = []; pendingEmail = nil
                do { try content.transition(to: next, cacheURL: cacheURL) }
                catch { try? content.transition(to: nil, cacheURL: cacheURL); throw error }
                let bytes = try next.map { try JSONEncoder().encode($0) }
                UserDefaults.standard.set(bytes, forKey: "ate.watch.session")
                guard UserDefaults.standard.data(forKey: "ate.watch.session") == bytes else {
                    try? content.transition(to: nil, cacheURL: cacheURL)
                    throw WatchOwnedContent.Failure.unavailable
                }
                session = next
            }
            return true
        } catch { status = "Couldn't verify saved account data. Sign in again."; return false }
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
            guard setSession(s) else { return }; pendingEmail = nil; status = nil
            await refresh()
        } catch { status = error.localizedDescription }
    }
    func signOut() {
        _ = setSession(nil)
    }

    private func validToken() async -> String? {
        guard var s = session, let base else { return nil }
        if WatchAuthRequests.needsRefresh(expiresAt: s.expiresAt) {
            let epoch = writerBoundary.captureEpoch()
            let data = try? await send(WatchAuthRequests.refreshURL(base: base), body: ["refresh_token": s.refreshToken])
            guard session == s, (try? writerBoundary.validateEpoch(epoch)) != nil else { return nil }
            guard let data, let n = parseSession(data), n.userID == s.userID else {
                status = "Session expired - sign in again."; return nil
            }
            // Epoch re-check after the network await: only the current session may be written.
            guard (try? writerBoundary.validateEpoch(epoch)) != nil else { return nil }
            guard setSession(n) else { status = "Couldn't update your sign-in. Try again."; return nil }
            s = n
        }
        return s.accessToken
    }

    // MARK: Sync
    func refresh() async {
        guard let base else { return }
        loading = true; defer { loading = false }
        var responseSession = session
        do {
            try await writerBoundary.publishAfterToken(token: { await validToken() }, isCurrentToken: { session?.accessToken == $0 }, fetch: { token in
                let original = session
                responseSession = original
                let d = try await send(base.appendingPathComponent("rest/v1/rpc/account_data_snapshot"), body: [:], bearer: token)
                guard session == original else { throw WatchWriterBoundary.Failure.staleEpoch }
                guard let owner = original?.userID else { throw WatchWriterBoundary.Failure.staleEpoch }
                let snapshot = try WatchAccountSnapshot.decode(d, ownerID: owner)
                return (snapshot, original)
            }, publish: { result in
                guard let expected = result.1, session == expected else { throw WatchWriterBoundary.Failure.staleEpoch }
                try content.publish(result.0, session: expected, cacheURL: cacheURL)
                status = nil
            })
        } catch WatchWriterBoundary.Failure.staleEpoch {
            // Dropped stale result: the current session's refresh owns the state.
        } catch WatchWriterBoundary.Failure.effectNotPerformed, WatchWriterBoundary.Failure.repeatedEffect {
            // A boundary defect is not a network failure: never claim "offline".
            guard session == responseSession else { return }
            status = "Couldn't refresh your recipes. Try again."
        } catch {
            guard session == responseSession else { return }
            status = content.recipes.isEmpty && content.shopping.isEmpty
                ? "Offline. No verified recipes are saved for this account."
                : "Offline. Showing this account's saved recipes."
        }
    }

    func toggle(_ item: WatchShoppingItem) async {
        guard let base, let originalSession = session else { return }
        let capture: WatchOwnedContent.Toggle
        do {
            capture = try writerBoundary.withEffect {
                try content.prepareToggle(item, session: originalSession,
                    nowMs: Int64(Date().timeIntervalSince1970 * 1000), cacheURL: cacheURL)
            }
        } catch { status = "Shopping changed. Refresh before trying again."; return }
        WKInterfaceDevice.current().play(.click)
        guard let token = await validToken() else { return }
        let epoch = writerBoundary.captureEpoch()
        do {
            try content.validate(capture, session: session)
            guard token == capture.session.accessToken else { throw WatchWriterBoundary.Failure.staleEpoch }
            let row = capture.row
            let dataObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row.data ?? .null))
            let body: [String: Any] = ["p_caller_generation": capture.generation, "p_kind": "shopping", "p_id": row.id,
                "p_data": dataObject, "p_updated_at": row.updated_at, "p_deleted": false]
            _ = try await send(base.appendingPathComponent("rest/v1/rpc/put_user_recipe"), body: body, bearer: token)
            try writerBoundary.validateEpoch(epoch)
            try content.validate(capture, session: session)
        } catch {
            // An old request must never invalidate/publish status into a new owner.
            guard session == capture.session else {
                // Token refresh is permitted to fetch NEW rows, never to retry
                // the old item under its new session/generation.
                if session?.userID == capture.session.userID { await refresh() }
                return
            }
            content.invalidate(capture)
            status = "Shopping update was not confirmed. Refreshing your account."
            await refresh()
        }
    }

    fileprivate func apply(_ p: WatchBridgePayload) {
        try? writerBoundary.withEffect {
            if p.signedOut { signOut(); return }
            if let s = p.session, s != session {
                guard setSession(s) else { return }
                Task { await refresh() }
            }
            guard session != nil else { return }
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
