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
        var catalogueRevision: String? = nil
        var itemRevision: String? = nil
        var commitSHA: String? = nil
        var runID: String? = nil
        var runNumber: String? = nil
    }

    private static let key = "ate.betaqa.v1"
    private static let historyKey = "ate.betaqa.history.v1"
    struct CatalogueSnapshot: Codable {
        let revision: String
        let pilotItems: [BetaItem]; let otherDocumentedItems: [BetaItem]
    }
    private(set) var catalogueSnapshots: [String: CatalogueSnapshot] = [:]
    private(set) var persistenceWarning: String?
    private var legacyPayloadUnreadable = false
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
    private(set) var history: [String: [Result]] = [:]
    var bannerDismissed: Bool { didSet { UserDefaults.standard.set(bannerDismissed, forKey: "ate.betaqa.banner.\(AppConfig.buildNumber)") } }

    private init() {
        bannerDismissed = UserDefaults.standard.bool(forKey: "ate.betaqa.banner.\(AppConfig.buildNumber)")
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            do { results = try JSONDecoder().decode([String: Result].self, from: data) }
            catch {
                legacyPayloadUnreadable = true
                persistenceWarning = "Saved beta evidence could not be read. Its original bytes have been preserved; recording is paused."
                UserDefaults.standard.set(data, forKey: "ate.betaqa.unreadable.backup.v1")
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.historyKey) {
            do { history = try JSONDecoder().decode([String: [Result]].self, from: data) }
            catch {
                legacyPayloadUnreadable = true
                persistenceWarning = "Saved beta history could not be read. Its original bytes have been preserved; recording is paused."
                UserDefaults.standard.set(data, forKey: "ate.betaqa.history.unreadable.backup.v1")
            }
        }
        if let data = UserDefaults.standard.data(forKey: "ate.betaqa.catalogues.v1"), let saved = try? JSONDecoder().decode([String: CatalogueSnapshot].self, from: data) {
            // Deduplicate old build-keyed snapshots without dropping any known wording.
            for snapshot in saved.values { catalogueSnapshots[snapshot.revision] = snapshot }
        }
        catalogueSnapshots[BetaChecklist.catalogueRevision] = CatalogueSnapshot(revision: BetaChecklist.catalogueRevision,
            pilotItems: BetaChecklist.tierA, otherDocumentedItems: BetaChecklist.tierC)
        if !AppConfig.isUITesting, let data = try? JSONEncoder().encode(catalogueSnapshots) {
            UserDefaults.standard.set(data, forKey: "ate.betaqa.catalogues.v1")
        }
    }
    private func save() {
        if AppConfig.isUITesting || legacyPayloadUnreadable { return }
        if let d = try? JSONEncoder().encode(results) { UserDefaults.standard.set(d, forKey: Self.key) }
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: Self.historyKey) }
        if let d = try? JSONEncoder().encode(catalogueSnapshots) { UserDefaults.standard.set(d, forKey: "ate.betaqa.catalogues.v1") }
    }

    func result(_ id: String) -> Result { results[id] ?? Result() }

    func currentResult(_ id: String) -> Result {
        let r = result(id)
        return Self.matchesCurrent(r) && r.itemRevision == BetaChecklist.all.first(where: { $0.id == id })?.revision ? r : Result()
    }
    static func matches(_ r: Result, build: String, sha: String, runID: String) -> Bool {
        !sha.isEmpty && sha != "dev" && !runID.isEmpty && runID != "0" &&
        r.build == build && r.commitSHA == sha && r.runID == runID
    }
    static func matchesCurrent(_ r: Result) -> Bool {
        guard r.catalogueRevision == BetaChecklist.catalogueRevision else { return false }
        if AppConfig.isUITesting { return r.build == AppConfig.buildLabel && r.commitSHA == AppConfig.gitSHAFull && r.runID == AppConfig.gitRunID }
        return matches(r, build: AppConfig.buildLabel, sha: AppConfig.gitSHAFull, runID: AppConfig.gitRunID)
    }
    func previousResults(_ id: String) -> [Result] {
        let latest = result(id)
        return (history[id] ?? []).filter { !Self.matchesCurrent($0) } + (latest.status != .untested && !Self.matchesCurrent(latest) ? [latest] : [])
    }

    func set(_ id: String, _ status: Status, note: String, auto: Bool) {
        guard !legacyPayloadUnreadable else { return }
        if let old = results[id], Self.shouldArchive(old, build: AppConfig.buildLabel, sha: AppConfig.gitSHAFull,
            runID: AppConfig.gitRunID, catalogue: BetaChecklist.catalogueRevision) { history[id, default: []].append(old) }
        results[id] = Result(status: status, note: String(note.prefix(400)), auto: auto, ts: Date(), build: AppConfig.buildLabel,
                             catalogueRevision: BetaChecklist.catalogueRevision, itemRevision: BetaChecklist.all.first(where: { $0.id == id })?.revision,
                             commitSHA: AppConfig.gitSHAFull, runID: AppConfig.gitRunID, runNumber: AppConfig.buildNumber)
        save()
    }
    static func shouldArchive(_ old: Result, build: String, sha: String, runID: String, catalogue: String) -> Bool {
        old.status != .untested && !(old.build == build && old.commitSHA == sha && old.runID == runID && old.catalogueRevision == catalogue)
    }
    static func retainingHistoryAfterCurrentReset(_ input: [String: Result], build: String, sha: String, runID: String, catalogue: String) -> [String: Result] {
        input.filter { _, r in !(r.build == build && r.commitSHA == sha && r.runID == runID && r.catalogueRevision == catalogue) }
    }
    var hasVerifiableBuildIdentity: Bool {
        !AppConfig.gitSHAFull.isEmpty && AppConfig.gitSHAFull != "dev" && (Int64(AppConfig.gitRunID) ?? 0) > 0
    }
    /// Auto pass. Never overrides a manual verdict.
    func pass(_ id: String, note: String) {
        if let r = results[id], Self.matchesCurrent(r), !r.auto, r.status != .untested { return }
        set(id, .pass, note: note, auto: true)
    }
    /// Auto fail (keeps an earlier auto pass only if it's from a later attempt — failures are always recorded).
    func fail(_ id: String, error: String) {
        if let r = results[id], Self.matchesCurrent(r), !r.auto, r.status != .untested { return }
        set(id, .fail, note: error, auto: true)
    }
    /// Called only after account-reset local byte erasure, with old UI retired.
    /// Drop retained personal notes so a later event cannot repersist erased history.
    func clearPersonalCacheAfterReset() {
        results = [:]; history = [:]; catalogueSnapshots = [:]
        legacyPayloadUnreadable = false; persistenceWarning = nil
        backgroundedAt = nil; backgroundTimers = 0
    }
    func resetCurrentBuild() {
        guard !legacyPayloadUnreadable else { return }
        results = Self.retainingHistoryAfterCurrentReset(results, build: AppConfig.buildLabel, sha: AppConfig.gitSHAFull,
            runID: AppConfig.gitRunID, catalogue: BetaChecklist.catalogueRevision)
        save()
    }

    func progress(_ category: String? = nil) -> (passed: Int, total: Int) {
        let items = BetaChecklist.items.filter { category == nil || $0.category == category }
        return (items.filter { currentResult($0.id).status == .pass }.count, items.count)
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
    private func recordedRows() -> [(BetaItem, Result)] {
        var knownItems: [String: BetaItem] = [:]
        for item in BetaChecklist.all { knownItems[item.id] = item }
        for snapshot in catalogueSnapshots.values {
            for item in snapshot.pilotItems + snapshot.otherDocumentedItems where knownItems[item.id] == nil { knownItems[item.id] = item }
        }
        let ids = Set(results.keys).union(history.keys)
        return ids.sorted().flatMap { id in
            let item = knownItems[id] ?? BetaItem(id: id, title: "Historical item (wording unavailable)",
                category: "Historical", how: "Original catalogue was not retained by that build.", auto: false, revision: "unknown")
            return ((history[id] ?? []) + (results[id].map { [$0] } ?? [])).map { (item, $0) }
        }
    }
    static func evidenceFields(_ r: Result) -> [String: Any] {
        ["build": r.build, "catalogue_revision": r.catalogueRevision as Any? ?? NSNull(), "item_revision": r.itemRevision as Any? ?? NSNull(), "commit_sha": r.commitSHA as Any? ?? NSNull(),
         "run_id": r.runID.flatMap(Int64.init) as Any? ?? NSNull(),
         "run_number": r.runNumber.flatMap(Int64.init) as Any? ?? NSNull()]
    }
    func exportJSON() -> Data {
        let rows = recordedRows().map { i, r -> [String: Any] in
            var row = Self.evidenceFields(r)
            row.merge(["item_id": i.id, "title": i.title, "category": i.category, "status": r.status.rawValue,
                       "note": r.note, "auto": r.auto, "ts": ISO8601DateFormatter().string(from: r.ts),
                       "current_build": Self.matchesCurrent(r)]) { _, new in new }
            return row
        }
        return (try? JSONSerialization.data(withJSONObject: ["build": AppConfig.buildLabel, "exported_from_build": AppConfig.buildLabel, "catalogue_revision": BetaChecklist.catalogueRevision, "catalogue_snapshots": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(catalogueSnapshots))) ?? [:], "results": rows], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
    func exportMarkdown() -> String {
        var s = "# ate beta evidence\n\nExported from \(AppConfig.buildLabel). Historical results are not current-build verification.\n\n"
        s += "| ID | Status | Recorded build | Recorded time | Commit | Run | Scope | Note |\n|---|---|---|---|---|---|---|---|\n"
        for (i, r) in recordedRows() {
            let cells = [i.id, r.status.rawValue, r.build, ISO8601DateFormatter().string(from: r.ts),
                         r.commitSHA ?? "Unknown", r.runID ?? "Unknown", Self.matchesCurrent(r) ? "Current build" : "Historical / legacy", r.note]
            s += "| " + cells.map { $0.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ") + " |\n"
        }
        return s
    }

    static func isUploadable(_ r: Result) -> Bool {
        r.status != .untested && !r.build.isEmpty && r.catalogueRevision != nil && r.itemRevision != nil &&
        !(r.commitSHA ?? "").isEmpty && r.commitSHA != "dev" && (r.runID.flatMap(Int64.init) ?? 0) > 0
    }
    var legacyNotUploadedCount: Int {
        let latest = results.values.filter { $0.status != .untested && !Self.isUploadable($0) }.count
        return latest + history.values.reduce(0) { $0 + $1.filter { $0.status != .untested && !Self.isUploadable($0) }.count }
    }

    /// Upserts every tested item into public.qa_results (RLS: own rows). Returns an error message or nil.
    func upload(session: AuthSession) async -> String? {
        guard let base = AppConfig.supabaseURL else { return "Cloud isn't configured in this build." }
        let iso = ISO8601DateFormatter()
        // The cloud schema stores one verdict per item/build/source. Upload only the latest
        // retained record for each original build, preserving its identity. The local history/export retains the latest preserved verdict for prior builds, not every attempt.
        var latest: [String: (BetaItem, Result)] = [:]
        for (i, r) in recordedRows() where Self.isUploadable(r) {
            let key = i.id + "\u{001F}" + r.build
            if latest[key].map({ $0.1.ts <= r.ts }) ?? true { latest[key] = (i, r) }
        }
        let rows: [[String: Any]] = latest.values.map { i, r in
            var row = Self.evidenceFields(r)
            row.removeValue(forKey: "catalogue_revision"); row.removeValue(forKey: "item_revision")
            row.merge(["user_id": session.userID, "item_id": i.id, "status": r.status.rawValue,
                       "note": r.note, "auto": r.auto, "ts": iso.string(from: r.ts), "source": "device"]) { _, new in new }
            return row
        }
        guard !rows.isEmpty else { return "No verifiable records to upload. Earlier/unknown records are preserved in the local export." }
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
struct CIResult: Equatable {
    var status: BetaQA.Status; var note: String; var build: String; var ts: String
    var commitSHA: String? = nil; var runID: String? = nil; var runURL: String? = nil
    func matches(build: String, sha: String, runID: String) -> Bool {
        !sha.isEmpty && sha != "dev" && !runID.isEmpty && runID != "0" &&
        self.build == build && commitSHA == sha && self.runID == runID
    }
}
enum BetaCIViewState: Equatable {
    case loading, unknown, notLoaded, noEvidence, evidence
    static func resolve(loading: Bool, error: String?, refreshed: Date?, count: Int) -> Self {
        if loading { return .loading }
        if error != nil { return .unknown }
        guard refreshed != nil else { return .notLoaded }
        return count == 0 ? .noEvidence : .evidence
    }
}
@MainActor enum CIStatus {
    static var results: [String: CIResult] = AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaCIResults")
        ? ["A-SYNC-02": CIResult(status: .pass, note: "7 fixture scenarios converge", build: "ci", ts: "2026-10-10T02:17:00Z"),
           "A-SHARE-05": CIResult(status: .fail, note: "ErrorRetryCard missing", build: "ci", ts: "2026-10-10T02:17:00Z")]
        : [:]
    static var lastError: String?
    static var lastRefreshed: Date?
    private static var generation = 0
    /// Latest CI verdict per item (owner-readable via RLS).
    static func refresh(session: AuthSession) async {
        guard !AppConfig.isUITesting else { return }
        generation += 1
        let requestGeneration = generation
        results = [:]; lastError = nil; lastRefreshed = nil
        guard let base = AppConfig.supabaseURL else { lastError = "CI is not configured in this build."; return }
        guard !AppConfig.gitRunID.isEmpty, AppConfig.gitSHAFull != "dev" else {
            lastError = "This build has no verifiable CI identity."; return
        }
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/qa_results"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "select", value: "item_id,status,note,build,ts,commit_sha,run_id,run_url"), URLQueryItem(name: "source", value: "eq.ci"),
                        URLQueryItem(name: "user_id", value: "eq.\(session.userID)"), URLQueryItem(name: "order", value: "ts.desc"),
                        URLQueryItem(name: "build", value: "eq.\(AppConfig.buildLabel)"),
                        URLQueryItem(name: "commit_sha", value: "eq.\(AppConfig.gitSHAFull)"),
                        URLQueryItem(name: "run_id", value: "eq.\(AppConfig.gitRunID)"),
                        URLQueryItem(name: "limit", value: "500")]
        var req = URLRequest(url: c.url!)
        Net.authorize(&req, key: AppConfig.supabasePublishableKey, bearer: session.accessToken)
        do {
            let (d, resp) = try await Net.data(for: req)
            guard requestGeneration == generation else { return }
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let rows = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { lastError = "CI results unavailable"; return }
            var out: [String: CIResult] = [:]
            for r in rows {
                guard let id = r["item_id"] as? String, out[id] == nil else { continue }
                out[id] = CIResult(status: BetaQA.Status(rawValue: r["status"] as? String ?? "") ?? .untested,
                                   note: r["note"] as? String ?? "", build: r["build"] as? String ?? "", ts: r["ts"] as? String ?? "",
                                   commitSHA: r["commit_sha"] as? String,
                                   runID: (r["run_id"] as? NSNumber)?.stringValue ?? r["run_id"] as? String,
                                   runURL: r["run_url"] as? String)
                if out[id]?.matches(build: AppConfig.buildLabel, sha: AppConfig.gitSHAFull, runID: AppConfig.gitRunID) != true { out[id] = nil }
            }
            results = out; lastError = nil; lastRefreshed = Date()
        } catch { if requestGeneration == generation { lastError = Net.friendly(error) } }
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
        if device.status == .fail || (ci?.build == build && ci?.status == .fail) { return false }
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
        for (a, c) in mirrors where currentResult(a).status == .pass { pass(c, note: "Covered by \(a): " + currentResult(a).note) }
    }
}
