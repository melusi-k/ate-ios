import Foundation
import Observation
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

struct ActiveTimer: Identifiable, Equatable {
    var id: String { "\(recipeID)#\(stepIndex)" }
    let recipeID: String
    var recipeTitle: String
    let stepIndex: Int
    var stepCount: Int
    var stepText: String
    var total: Int
    var endDate: Date?          // nil = paused
    var pausedRemaining: Int

    var isRunning: Bool { endDate != nil }
    func remaining(at now: Date = Date()) -> Int {
        if let e = endDate { return max(0, Int(ceil(e.timeIntervalSince(now)))) }
        return pausedRemaining
    }
    static func key(_ recipeID: String, _ step: Int) -> String { "\(recipeID)#\(step)" }
}

/// App-wide cook timers: drives cook mode, the sticky timer bar, notifications and Live Activities.
@Observable
@MainActor
final class TimerCenter {
    private(set) var timers: [ActiveTimer] = [] { didSet { persist() } }

    init() {
        if AppConfig.isUITesting { TimerSnapshot.save([]); return }
        timers = TimerSnapshot.load().map {
            ActiveTimer(recipeID: $0.recipeID, recipeTitle: $0.recipeTitle, stepIndex: $0.stepIndex, stepCount: $0.stepCount,
                        stepText: $0.stepText, total: $0.total, endDate: $0.endDate, pausedRemaining: $0.pausedRemaining)
        }
    }

    @ObservationIgnored private var suppressPersist = false
    private func persist() {
        if suppressPersist { return }
        PhoneWatchBridge.shared.update(timers: timers)
        TimerSnapshot.save(snapshots)
        WidgetKinds.reload([WidgetKinds.timers])
    }
    var snapshots: [TimerSnapshot] {
        timers.map {
            TimerSnapshot(recipeID: $0.recipeID, recipeTitle: $0.recipeTitle, stepIndex: $0.stepIndex, stepCount: $0.stepCount,
                          stepText: $0.stepText, total: $0.total, endDate: $0.endDate, pausedRemaining: $0.pausedRemaining)
        }
    }

    /// Widget buttons / controls that ran in the extension changed the App Group copy: adopt it, then fix up
    /// Live Activities (their notifications were already rescheduled by the extension).
    func reloadFromShared() {
        if AppConfig.isUITesting && !ProcessInfo.processInfo.arguments.contains("-qaSharedTimers") { return }
        let shared = TimerSnapshot.load()
        guard shared != snapshots else { return }
        let old = timers
        suppressPersist = true
        timers = shared.map {
            ActiveTimer(recipeID: $0.recipeID, recipeTitle: $0.recipeTitle, stepIndex: $0.stepIndex, stepCount: $0.stepCount,
                        stepText: $0.stepText, total: $0.total, endDate: $0.endDate, pausedRemaining: $0.pausedRemaining)
        }
        suppressPersist = false
        PhoneWatchBridge.shared.update(timers: timers)
        for t in old where !timers.contains(where: { $0.id == t.id }) { LiveActivities.end(t.id) }
        for t in timers { LiveActivities.startOrUpdate(t) }
    }

    /// Runs a widget / Siri / Control Center command against the live timers.
    func run(_ cmd: TimerMath.Command, id: String) {
        switch cmd {
        case .pause: pause(id)
        case .resume: resume(id)
        case .toggle: toggle(id)
        case .stop: stop(id)
        }
    }

    /// Kitchen timer control: pause the running timer, else resume a paused one, else start a 5-minute timer.
    @discardableResult
    func kitchenToggle(seconds: Int = TimerMath.quickSeconds) -> String {
        if let r = timers.first(where: { $0.isRunning }) { pause(r.id); return "paused" }
        if let p = timers.first { resume(p.id); return "resumed" }
        startQuick(seconds: seconds); return "started"
    }

    func startQuick(seconds: Int = TimerMath.quickSeconds) {
        let total = AppConfig.qaFastTimers ? max(2, seconds / 30) : seconds
        var t = ActiveTimer(recipeID: TimerMath.quickRecipeID, recipeTitle: "Kitchen timer", stepIndex: 0, stepCount: 1,
                            stepText: "Kitchen timer", total: total, endDate: nil, pausedRemaining: total)
        if let existing = timer(TimerMath.quickRecipeID, 0) { t = existing; if t.isRunning { return } }
        t.endDate = Date().addingTimeInterval(TimeInterval(t.pausedRemaining > 0 ? t.pausedRemaining : total))
        upsert(t)
        TimerAlerts.schedule(id: t.id, step: 1, recipeTitle: t.recipeTitle, at: t.endDate!, prefs: prefsProvider())
        LiveActivities.startOrUpdate(t)
    }
    var now = Date()
    var prefsProvider: @MainActor () -> TimerPrefs = { TimerPrefs() }
    private var permissionAsked = false

    func timer(_ recipeID: String, _ step: Int) -> ActiveTimer? {
        timers.first { $0.id == ActiveTimer.key(recipeID, step) }
    }

    func start(recipe: RecipeCard, stepIndex: Int) {
        guard recipe.steps.indices.contains(stepIndex) else { return }
        let step = recipe.steps[stepIndex]
        var total = step.timeSeconds ?? 0
        guard total > 0 else { return }
        if AppConfig.qaFastTimers { total = max(2, total / 30) }
        if !permissionAsked, prefsProvider().stepAlerts {
            permissionAsked = true
            Task { _ = await TimerAlerts.requestPermission() }
        }
        var t = timer(recipe.id, stepIndex) ?? ActiveTimer(recipeID: recipe.id, recipeTitle: recipe.title, stepIndex: stepIndex,
                                                         stepCount: recipe.steps.count, stepText: step.instruction,
                                                         total: total, endDate: nil, pausedRemaining: total)
        if t.isRunning { return }
        if t.pausedRemaining <= 0 { t.pausedRemaining = total }
        t.endDate = Date().addingTimeInterval(TimeInterval(t.pausedRemaining))
        upsert(t)
        TimerAlerts.schedule(id: t.id, step: stepIndex + 1, recipeTitle: t.recipeTitle, at: t.endDate!, prefs: prefsProvider())
        LiveActivities.startOrUpdate(t)
    }

    func pause(_ id: String) {
        guard var t = timers.first(where: { $0.id == id }), t.isRunning else { return }
        t.pausedRemaining = t.remaining()
        t.endDate = nil
        upsert(t)
        TimerAlerts.cancel(id: id)
        LiveActivities.startOrUpdate(t)
    }

    func toggle(_ id: String) {
        guard let t = timers.first(where: { $0.id == id }) else { return }
        if t.isRunning { pause(id) } else { resume(id) }
    }

    func resume(_ id: String) {
        guard var t = timers.first(where: { $0.id == id }), !t.isRunning else { return }
        if t.pausedRemaining <= 0 { t.pausedRemaining = t.total }
        t.endDate = Date().addingTimeInterval(TimeInterval(t.pausedRemaining))
        upsert(t)
        TimerAlerts.schedule(id: t.id, step: t.stepIndex + 1, recipeTitle: t.recipeTitle, at: t.endDate!, prefs: prefsProvider())
        LiveActivities.startOrUpdate(t)
    }

    func reset(_ id: String) {
        guard var t = timers.first(where: { $0.id == id }) else { return }
        t.endDate = nil
        t.pausedRemaining = t.total
        upsert(t)
        TimerAlerts.cancel(id: id)
        LiveActivities.startOrUpdate(t)
    }

    func stop(_ id: String) {
        timers.removeAll { $0.id == id }
        TimerAlerts.cancel(id: id)
        LiveActivities.end(id)
    }

    /// Called when cook mode exits: drop timers that aren't running (their Live Activities end too).
    func cleanupIdle(recipeID: String) {
        for t in timers where t.recipeID == recipeID && !t.isRunning { stop(t.id) }
    }

    func stopAll(recipeID: String) { for t in timers where t.recipeID == recipeID { stop(t.id) } }

    /// Timers restored from persistence (or running when we come back to the foreground) get their Live Activity back.
    func ensureLiveActivities() {
        for t in timers where t.isRunning { LiveActivities.startOrUpdate(t) }
    }

    func tick(_ date: Date = Date()) {
        now = date
        for t in timers where t.isRunning && t.remaining(at: date) == 0 {
            timers.removeAll { $0.id == t.id }
            TimerAlerts.timerFinished(prefs: prefsProvider())
            BetaQA.shared.pass("A-TIMER-01", note: "Timer for step \(t.stepIndex + 1) finished")
            LiveActivities.end(t.id, finished: t)
        }
    }

    private func upsert(_ t: ActiveTimer) {
        if let i = timers.firstIndex(where: { $0.id == t.id }) { timers[i] = t } else { timers.append(t) }
    }
}

import os

/// Last Live Activity request outcome, shown in More → About → Live Activity.
@MainActor
@Observable
final class LiveActivityLog {
    static let shared = LiveActivityLog()
    private static let key = "ate.liveactivity.log.v1"
    private(set) var entries: [String] = UserDefaults.standard.stringArray(forKey: LiveActivityLog.key) ?? []
    func add(_ s: String) {
        entries.insert("\(Date().formatted(date: .omitted, time: .standard)) \(s)", at: 0)
        if entries.count > 20 { entries.removeLast(entries.count - 20) }
        UserDefaults.standard.set(entries, forKey: Self.key)
    }
}

@MainActor
enum LiveActivityDiagnostics {
    static let log = Logger(subsystem: "com.melusik.ate", category: "LiveActivity")
    static var lastResult: String { LiveActivityLog.shared.entries.first ?? "no request yet" }
    static var enabledNow: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }
    static var activeCount: Int {
        #if canImport(ActivityKit)
        return Activity<CookTimerAttributes>.activities.count
        #else
        return 0
        #endif
    }
    /// Lists *.appex inside Bundle.main.builtInPlugInsURL (Sideloadly "Remove extensions" deletes these).
    static var plugIns: [String] {
        guard let u = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(atPath: u.path) else { return [] }
        return items.filter { $0.hasSuffix(".appex") }.sorted()
    }
    static var widgetAppexPresent: Bool { plugIns.contains("AteWidgets.appex") }
    static var widgetBundleID: String? {
        guard let u = Bundle.main.builtInPlugInsURL?.appendingPathComponent("AteWidgets.appex") else { return nil }
        return Bundle(url: u)?.bundleIdentifier
    }
    /// Why the widget gallery might skip the extension: id must be `<app id>.<suffix>`, and its profile must name it.
    static var widgetSigningIssues: [String] {
        guard let u = Bundle.main.builtInPlugInsURL?.appendingPathComponent("AteWidgets.appex"),
              let wid = Bundle(url: u)?.bundleIdentifier, let app = Bundle.main.bundleIdentifier else { return [] }
        var out: [String] = []
        if !wid.hasPrefix(app + ".") { out.append("widget id \(wid) is not under app id \(app)") }
        if let d = try? Data(contentsOf: u.appendingPathComponent("embedded.mobileprovision")),
           let s = d.range(of: Data("<?xml".utf8)), let e = d.range(of: Data("</plist>".utf8), in: s.lowerBound..<d.endIndex),
           let pl = try? PropertyListSerialization.propertyList(from: d[s.lowerBound..<e.upperBound], format: nil) as? [String: Any],
           let ent = pl["Entitlements"] as? [String: Any], let appID = ent["application-identifier"] as? String {
            let idPart = appID.split(separator: ".", maxSplits: 1).last.map(String.init) ?? appID
            if idPart != wid && idPart != "*" { out.append("widget profile is for \(idPart), not \(wid)") }
        } else { out.append("widget has no provisioning profile") }
        return out
    }
    static func record(_ s: String) { LiveActivityLog.shared.add(s); log.notice("\(s, privacy: .public)") }
}

@MainActor
enum LiveActivities {
    static var enabled: Bool {
        #if canImport(ActivityKit)
        if AppConfig.isUITesting { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    #if canImport(ActivityKit)
    static func state(_ t: ActiveTimer, finished: Bool = false) -> CookTimerAttributes.ContentState {
        let rem = finished ? 0 : t.remaining()
        return CookTimerAttributes.ContentState(stepIndex: t.stepIndex, stepCount: t.stepCount, stepText: t.stepText,
                                                startDate: Date(), endDate: finished ? nil : t.endDate, remaining: rem,
                                                total: t.total, finished: finished)
    }

    static func activity(_ id: String) -> Activity<CookTimerAttributes>? {
        Activity<CookTimerAttributes>.activities.first { $0.attributes.timerID == id }
    }
    #endif

    static func startOrUpdate(_ t: ActiveTimer) {
        if AppConfig.isUITesting { Task { @MainActor in QAProbe.shared.liveActivityRequests += 1 } }
        #if canImport(ActivityKit)
        LiveActivityDiagnostics.record("attempt: \(t.isRunning ? "running" : "paused") timer step \(t.stepIndex + 1)")
        guard enabled else {
            LiveActivityDiagnostics.record("skipped: areActivitiesEnabled = false (Settings → ate → Live Activities)")
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            LiveActivityDiagnostics.record("skipped: app in background (requests must be made in the foreground)")
            return
        }
        let content = ActivityContent(state: state(t), staleDate: t.endDate?.addingTimeInterval(60))
        if let a = activity(t.id) {
            Task { await a.update(content); LiveActivityDiagnostics.record("updated \(a.id.prefix(8)) state=\(String(describing: a.activityState))") }
        } else {
            let attrs = CookTimerAttributes(recipeID: t.recipeID, recipeTitle: t.recipeTitle, timerID: t.id)
            do {
                let a = try Activity.request(attributes: attrs, content: content, pushType: nil)
                LiveActivityDiagnostics.record("started \(a.id.prefix(8)) state=\(String(describing: a.activityState)), total active \(Activity<CookTimerAttributes>.activities.count)")
                BetaQA.shared.pass("A-TIMER-02", note: "Live Activity request succeeded (\(a.id.prefix(8)))")
            } catch {
                LiveActivityDiagnostics.record("error: \(error.localizedDescription) [\(String(describing: error))]")
                BetaQA.shared.fail("A-TIMER-02", error: "Live Activity request failed: \(error.localizedDescription)")
                LiveActivityDiagnostics.log.error("Activity.request failed: \(String(describing: error), privacy: .public)")
            }
        }
        #endif
    }

    static func end(_ id: String, finished: ActiveTimer? = nil) {
        #if canImport(ActivityKit)
        guard let a = activity(id) else { return }
        let st = finished.map { state($0, finished: true) } ?? a.content.state
        Task {
            await a.end(ActivityContent(state: st, staleDate: nil),
                        dismissalPolicy: finished == nil ? .immediate : .after(Date().addingTimeInterval(120)))
        }
        #endif
    }
}
