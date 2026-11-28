import Foundation
import UserNotifications
import UIKit
import AudioToolbox

enum TimerAlerts {
    /// Serial queue carrying every notification-center IPC. The first synchronous
    /// UNUserNotificationCenter call of a process can block for a very long time
    /// (usernoted startup); synchronous callers include the widget/Siri relay return,
    /// which has a hard wall-clock allowance, so alert IPC never runs on the
    /// caller's thread. One serial queue preserves schedule/cancel ordering.
    private static let alertQueue = DispatchQueue(label: "ate.timer-alerts", qos: .userInitiated)

    private static let stateLock = NSLock()
    private static var _lastScheduleError: String?
    /// Recorded failure surface for best-effort scheduling: the most recent
    /// notification-center error, nil after the most recent success. Nothing throws.
    static var lastScheduleError: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return _lastScheduleError
    }

    /// The blocking system calls, isolated behind one seam so tests can observe or
    /// stall them. A nil request performs only the cancel half. Always invoked on
    /// alertQueue; never call directly from a thread with a return deadline.
    static func systemSchedule(id: String, request: UNNotificationRequest?, completion: @escaping (Error?) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ate.timer." + id])
        guard let request else { completion(nil); return }
        center.add(request, withCompletionHandler: completion)
    }
    /// Test seam; production keeps the default. Restored by tests in tearDown.
    static var performSystemSchedule: (_ id: String, _ request: UNNotificationRequest?, _ completion: @escaping (Error?) -> Void) -> Void = systemSchedule

    static func requestPermission() async -> Bool {
        if AppConfig.isUITesting { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }

    /// Quiet window, handles overnight ranges.
    static func isQuiet(_ prefs: TimerPrefs, at date: Date = Date()) -> Bool {
        guard prefs.quietHours else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let s = minutes(prefs.quietStart), e = minutes(prefs.quietEnd)
        if s == e { return false }
        return s < e ? (now >= s && now < e) : (now >= s || now < e)
    }

    /// Best-effort: the request is built on the caller's thread, but the blocking
    /// notification-center IPC (cancel-then-add) runs on alertQueue and failures are
    /// recorded in `lastScheduleError` instead of thrown, so synchronous callers such
    /// as the kitchen-toggle relay return immediately.
    static func schedule(id: String, step: Int, recipeTitle: String, at end: Date, prefs: TimerPrefs) {
        let request: UNNotificationRequest? = {
            guard prefs.stepAlerts else { return nil }
            let content = UNMutableNotificationContent()
            content.title = "Step \(step) is done"
            content.body = recipeTitle
            content.sound = (prefs.sound && !isQuiet(prefs, at: end)) ? UNNotificationSound(named: UNNotificationSoundName("ate-chime.wav")) : nil
            content.interruptionLevel = .timeSensitive
            let interval = max(1, end.timeIntervalSinceNow)
            return UNNotificationRequest(identifier: "ate.timer." + id, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        }()
        alertQueue.async {
            performSystemSchedule(id, request) { error in
                stateLock.lock()
                _lastScheduleError = error.map { String(describing: $0) }
                stateLock.unlock()
            }
        }
    }

    static func cancel(id: String) {
        alertQueue.async {
            performSystemSchedule(id, nil) { _ in }
        }
    }

    /// Clear-all (lane 3): removes pending AND delivered notifications, then verifies
    /// once after the system's asynchronous removal settles. No retry loop: a non-empty
    /// read-back is reported to the caller, never hidden. Covers the "ate.timer."
    /// requests scheduled here and by the widget extension - the only requests the app
    /// family creates.
    static func removeAllAndVerify() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        // The removals run asynchronously on the system side; settle once, then verify.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        return pending.isEmpty && delivered.isEmpty
    }

    /// Foreground finish: chime + haptics (the scheduled notification covers background).
    @MainActor static func timerFinished(prefs: TimerPrefs) {
        if prefs.sound && !isQuiet(prefs) { Haptics.chime(); if AppConfig.isUITesting { Task { @MainActor in QAProbe.shared.chimes += 1 } } }
        if prefs.vibration { Haptics.timerDone(); if AppConfig.isUITesting { Task { @MainActor in QAProbe.shared.finishHaptics += 1 } } }
    }
}
