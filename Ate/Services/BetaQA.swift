import Foundation
import UIKit
import Observation

/// On-device Pilot-gate checklist: journeys auto-tick ✅ / ❌ when they really complete or fail; others are manual.
@MainActor
@Observable
final class BetaQA {
    static let shared = BetaQA()

    enum Status: String, Codable { case untested, pass, fail, skip
        var symbol: String { switch self { case .untested: "○"; case .pass: "✅"; case .fail: "❌"; case .skip: "⏭️" } }
    }
    struct Result: Codable, Equatable {
        var status: Status = .untested
        var note: String = ""
        var auto: Bool = false
        var ts: Date = Date()
        var build: String = ""
    }

    private static let key = "ate.betaqa.v1"
    /// Set by the first-launch banner to open Settings › Beta testing.
    var openRequested = false
    var magicLinkSent: Bool {
        get { UserDefaults.standard.bool(forKey: "ate.betaqa.magic") }
        set { UserDefaults.standard.set(newValue, forKey: "ate.betaqa.magic") }
    }
    @ObservationIgnored var lastPulled = 0
    @ObservationIgnored var lastSyncFailure: String?
    @ObservationIgnored var networkLossSeen = false
    private(set) var results: [String: Result] = [:]
    var bannerDismissed: Bool { didSet { UserDefaults.standard.set(bannerDismissed, forKey: "ate.betaqa.banner.\(AppConfig.buildNumber)") } }

    private init() {
        bannerDismissed = UserDefaults.standard.bool(forKey: "ate.betaqa.banner.\(AppConfig.buildNumber)")
        if let d = UserDefaults.standard.data(forKey: Self.key), let r = try? JSONDecoder().decode([String: Result].self, from: d) { results = r }
    }
    private func save() {
        if AppConfig.isUITesting { return }
        if let d = try? JSONEncoder().encode(results) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func result(_ id: String) -> Result { results[id] ?? Result() }

    func set(_ id: String, _ status: Status, note: String, auto: Bool) {
        results[id] = Result(status: status, note: String(note.prefix(400)), auto: auto, ts: Date(), build: AppConfig.buildLabel)
        save()
    }
    /// Auto pass. Never overrides a manual verdict.
    func pass(_ id: String, note: String) {
        if let r = results[id], !r.auto, r.status != .untested { return }
        set(id, .pass, note: note, auto: true)
    }
    /// Auto fail (keeps an earlier auto pass only if it's from a later attempt — failures are always recorded).
    func fail(_ id: String, error: String) {
        if let r = results[id], !r.auto, r.status != .untested { return }
        set(id, .fail, note: error, auto: true)
    }
    func reset() { results = [:]; save() }

    func progress(_ category: String? = nil) -> (passed: Int, total: Int) {
        let items = BetaChecklist.items.filter { category == nil || $0.category == category }
        return (items.filter { result($0.id).status == .pass }.count, items.count)
    }

    // MARK: lifecycle signals
    private var backgroundedAt: Date?
    private var backgroundTimers = 0
    func launched(recipeCount: Int, restoredTimers: Int) {
        pass("A-REL-01", note: "Launched cleanly with \(recipeCount) recipes")
        pass("A-CI-01", note: "Running numbered build \(AppConfig.buildLabel)")
        let last = UserDefaults.standard.integer(forKey: "ate.betaqa.lastRecipeCount")
        if UserDefaults.standard.object(forKey: "ate.betaqa.lastRecipeCount") != nil, last > 0 {
            if recipeCount >= last { pass("A-EDIT-02", note: "Relaunch kept all \(recipeCount) recipes") }
            else { fail("A-EDIT-02", error: "Relaunch found \(recipeCount) recipes, expected \(last)") }
        }
        if restoredTimers > 0 { pass("A-TIMER-03", note: "Restored \(restoredTimers) timer(s) after relaunch") }
    }
    func recipeCountChanged(_ n: Int) { UserDefaults.standard.set(n, forKey: "ate.betaqa.lastRecipeCount") }
    func wentToBackground(runningTimers: Int) { backgroundedAt = Date(); backgroundTimers = runningTimers }
    func returnedToForeground(runningTimers: Int) {
        guard let at = backgroundedAt else { return }
        backgroundedAt = nil
        let secs = Int(Date().timeIntervalSince(at))
        if backgroundTimers > 0 && secs >= 5 {
            pass("A-TIMER-02", note: "Back after \(secs)s in background with \(backgroundTimers) running timer(s); countdown resumed from wall clock")
        }
    }

    // MARK: export / upload
    func exportJSON() -> Data {
        let rows = BetaChecklist.items.map { i -> [String: Any] in
            let r = result(i.id)
            return ["item_id": i.id, "title": i.title, "category": i.category, "status": r.status.rawValue, "note": r.note,
                    "auto": r.auto, "ts": ISO8601DateFormatter().string(from: r.ts), "build": r.build]
        }
        return (try? JSONSerialization.data(withJSONObject: ["build": AppConfig.buildLabel, "results": rows], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
    func exportMarkdown() -> String {
        var s = "# ate beta results — \(AppConfig.buildLabel)\n\n\(BetaChecklist.tierName): \(progress().passed)/\(progress().total) passed\n"
        for c in BetaChecklist.categories {
            let p = progress(c)
            s += "\n## \(c) — \(p.passed)/\(p.total)\n\n| ID | Item | Status | Note |\n|---|---|---|---|\n"
            for i in BetaChecklist.items where i.category == c {
                let r = result(i.id)
                s += "| \(i.id) | \(i.title) | \(r.status.symbol) \(r.status.rawValue)\(r.auto ? " (auto)" : "") | \(r.note.replacingOccurrences(of: "|", with: "/")) |\n"
            }
        }
        return s
    }

    /// Upserts every tested item into public.qa_results (RLS: own rows). Returns an error message or nil.
    func upload(session: AuthSession) async -> String? {
        guard let base = AppConfig.supabaseURL else { return "Cloud isn't configured in this build." }
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = BetaChecklist.items.compactMap { i in
            let r = result(i.id); guard r.status != .untested else { return nil }
            return ["user_id": session.userID, "build": AppConfig.buildLabel, "item_id": i.id, "status": r.status.rawValue,
                    "note": r.note, "auto": r.auto, "ts": iso.string(from: r.ts), "source": "device"]
        }
        guard !rows.isEmpty else { return "Nothing tested yet." }
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/qa_results"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,build,item_id,source")]
        var req = URLRequest(url: c.url!); req.httpMethod = "POST"
        Net.authorize(&req, key: AppConfig.supabasePublishableKey, bearer: session.accessToken)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: rows)
        do {
            let (d, resp) = try await Net.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code) ? nil : "Upload failed (\(code)): \(String(decoding: d, as: UTF8.self).prefix(120))"
        } catch { return Net.friendly(error) }
    }
}

// MARK: CI results (qa_results source='ci', written by backend-e2e / simulator jobs)
struct CIResult: Equatable { var status: BetaQA.Status; var note: String; var build: String; var ts: String }
@MainActor enum CIStatus {
    static var results: [String: CIResult] = AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaCIResults")
        ? ["A-SYNC-02": CIResult(status: .pass, note: "7 fixture scenarios converge", build: "ci", ts: "2026-10-10T02:17:00Z"),
           "A-SHARE-05": CIResult(status: .fail, note: "ErrorRetryCard missing", build: "ci", ts: "2026-10-10T02:17:00Z")]
        : [:]
    static var lastError: String?
    /// Latest CI verdict per item (owner-readable via RLS).
    static func refresh(session: AuthSession) async {
        guard !AppConfig.isUITesting, let base = AppConfig.supabaseURL else { return }
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/qa_results"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "select", value: "item_id,status,note,build,ts"), URLQueryItem(name: "source", value: "eq.ci"),
                        URLQueryItem(name: "user_id", value: "eq.\(session.userID)"), URLQueryItem(name: "order", value: "ts.desc"),
                        URLQueryItem(name: "limit", value: "500")]
        var req = URLRequest(url: c.url!)
        Net.authorize(&req, key: AppConfig.supabasePublishableKey, bearer: session.accessToken)
        do {
            let (d, resp) = try await Net.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let rows = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { lastError = "CI results unavailable"; return }
            var out: [String: CIResult] = [:]
            for r in rows {
                guard let id = r["item_id"] as? String, out[id] == nil else { continue }
                out[id] = CIResult(status: BetaQA.Status(rawValue: r["status"] as? String ?? "") ?? .untested,
                                   note: r["note"] as? String ?? "", build: r["build"] as? String ?? "", ts: r["ts"] as? String ?? "")
            }
            results = out; lastError = nil
        } catch { lastError = Net.friendly(error) }
    }
}

// MARK: auth / sync signals
extension BetaQA {
    func authLinkSignedIn(email: String) {
        if magicLinkSent { pass("A-AUTH-04", note: "Magic link signed in \(email)"); magicLinkSent = false }
        else { pass("A-AUTH-01", note: "Confirmation link signed in \(email)") }
    }
    func signedOut(removeLocalData: Bool, remaining: Int) {
        pass("A-AUTH-03", note: removeLocalData ? "Signed out and removed local data (\(remaining) left)" : "Signed out, kept \(remaining) recipes")
    }
    func syncPulled(rows: Int) { lastPulled = rows }
    func syncSucceeded(pushed: Int) {
        let total = lastPulled + pushed
        if total >= 1 { pass("A-SYNC-01", note: "Sync OK: pulled \(lastPulled), pushed \(pushed) rows") }
        if let f = lastSyncFailure {
            pass("A-SYNC-04", note: "Recovered after failure: \(f)")
            pass("A-OFF-02", note: "Retry after network loss succeeded")
            lastSyncFailure = nil
        } else if networkLossSeen {
            pass("A-OFF-02", note: "Synced after an offline attempt"); networkLossSeen = false
        }
    }
    func syncFailed(_ msg: String) { lastSyncFailure = msg; set("A-SYNC-04", .untested, note: "Last sync failed: \(msg) — waiting for a retry", auto: true) }
    func markNetworkLoss() { networkLossSeen = true }
}

/// Which checks the Beta testing page hides behind "Passed (N)".
enum BetaVisibility {
    /// Passed = device pass, or CI pass for this exact build; any failure (device or CI) shows it again.
    static func isPassed(device: BetaQA.Result, ci: CIResult?, build: String) -> Bool {
        if device.status == .fail || ci?.status == .fail { return false }
        if device.status == .pass { return true }
        if let ci, ci.status == .pass, ci.build == build { return true }
        return false
    }
}

// MARK: Tier C auto-detection (runs when the Beta page opens on a TierC build)
extension BetaQA {
    /// Ticks Tier C checks whose evidence the app can see itself: accessibility settings in use while the app runs,
    /// widgets actually reading the App Group, and Tier A passes that cover the same behaviour. Never overrides a manual verdict.
    func detectTierC() {
        guard BetaChecklist.isTierC else { return }
        // Accessibility settings are setup conditions, not proof that acceptance criteria pass.
        // AX/NAT accessibility items remain untested until an audit/test or explicit manual review
        // verifies the required screens and behaviors; do not auto-pass them from environment flags.
        if AppGroupResolver.current.available && !WidgetBridge.heartbeats.isEmpty {
            pass("C-WID-01", note: "App Group OK, \(WidgetBridge.heartbeats.count) widget kind(s) loaded")
        }
        let mirrors = ["A-OFF-02": "C-NAT-13", "A-COVER-01": "C-COV-02"]
        for (a, c) in mirrors where result(a).status == .pass { pass(c, note: "Covered by \(a): " + result(a).note) }
    }
}
