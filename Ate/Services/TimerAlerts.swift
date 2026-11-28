import Foundation
import UserNotifications
import UIKit
import AudioToolbox

enum TimerAlerts {
    /// Serial queue carrying the blocking schedule/cancel IPC and the ordered erase.
    /// Measured fact (KITCHEN-SUB ledger, run 46113118998): a 110s stall inside
    /// TimerAlerts.schedule as a whole on the kitchen-toggle relay return, which has
    /// a hard wall-clock allowance. Hypothesis (unverified): the first synchronous
    /// UNUserNotificationCenter IPC of the process blocks on usernoted startup.
    /// Only schedule/cancel and the erase half of removeAllAndVerify run on this
    /// queue; requestPermission and the removeAllAndVerify read-back stay off it.
    /// The trigger interval is computed after the removal, immediately before the
    /// add, from the retained absolute end date; an end date expired by then is
    /// refused. The erase waits (bounded) for in-flight add callbacks and fences
    /// stale queued work with a writer epoch; a clear-all that cannot drain
    /// reports failure instead of claiming erasure.
    private static let alertQueue = DispatchQueue(label: "ate.timer-alerts", qos: .userInitiated)

    private static let stateLock = NSLock()
    private static var _scheduleSeq = 0
    private static var _lastRecordedSeq = 0
    private static var _lastScheduleError: String?
    /// Writer epoch: bumped when a clear-all is requested. Work enqueued before
    /// the bump is fenced off as stale if it reaches the queue afterwards.
    private static var _epoch = 0
    /// Add callbacks that have been initiated but not yet completed. The erase
    /// waits for these to drain before removing, so no add can land after a
    /// successful clear-all. Guarded by drainCond.
    private static let drainCond = NSCondition()
    private static var _inFlightAdds = 0
    /// Bound on how long the erase waits for in-flight add callbacks once the
    /// erase body is executing on alertQueue. It is a callback-drain bound only,
    /// not a total clear-all deadline: an earlier stalled synchronous IPC body
    /// ahead on the serial queue can delay the erase body past this bound before
    /// the wait even starts. Not a retry or a lane allowance: on expiry the
    /// clear-all reports failure. Test seam; production keeps 5s, tests lower it
    /// and restore it in tearDown.
    static var drainTimeout: TimeInterval = 5
    /// Test seam: invoked once the clear-all fence (writer epoch) is installed,
    /// before the erase is queued. Production keeps the no-op; tests restore it.
    static var fenceInstalled: () -> Void = {}
    /// Recorded failure surface for best-effort scheduling: the outcome (error or
    /// refusal, nil = success) of the newest-enqueued schedule that has completed.
    /// An older add callback can never overwrite a newer recorded result.
    static var lastScheduleError: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return _lastScheduleError
    }

    private static func record(_ seq: Int, _ result: String?) {
        stateLock.lock()
        if seq > _lastRecordedSeq { _lastRecordedSeq = seq; _lastScheduleError = result }
        stateLock.unlock()
    }

    /// Clock seam: the trigger interval is computed after the removal at execution
    /// time, and tests advance the clock while the worker is held mid-removal.
    /// Production keeps `Date.init`.
    static var now: () -> Date = Date.init

    /// The blocking system calls, isolated behind one seam so tests can observe or
    /// stall them. The removal runs first; makeRequest is invoked after it,
    /// immediately before the add, so the deadline is computed against the clock
    /// at that moment. A nil request performs only the cancel half. Always invoked
    /// on alertQueue; never call directly from a thread with a return deadline.
    static func systemSchedule(id: String, makeRequest: () -> UNNotificationRequest?, completion: @escaping (Error?) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ate.timer." + id])
        guard let request = makeRequest() else { completion(nil); return }
        center.add(request, withCompletionHandler: completion)
    }
    /// Test seam; production keeps the default. Restored by tests in tearDown.
    static var performSystemSchedule: (_ id: String, _ makeRequest: () -> UNNotificationRequest?, _ completion: @escaping (Error?) -> Void) -> Void = systemSchedule

    /// The erase half of clear-all, isolated behind one seam so tests can order it
    /// against queued schedule work. Always invoked on alertQueue.
    static func systemRemoveAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    /// Test seam; production keeps the default. Restored by tests in tearDown.
    static var performRemoveAll: () -> Void = systemRemoveAll

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

    /// Best-effort: preference reads and the epoch stamp happen on the caller's
    /// thread; everything blocking happens on alertQueue. The request is built by
    /// the system seam after the removal, immediately before the add, so the
    /// trigger interval reflects the retained absolute end date at that moment -
    /// a queued or removal-stalled schedule fires on the original end date, never
    /// late by its wait time. An end date already expired then is refused (cancel
    /// half only) and the refusal is recorded. Work enqueued before a clear-all
    /// fence that reaches the queue after it is rejected as stale. The blocking
    /// IPC never runs on the caller's thread, so synchronous callers such as the
    /// kitchen-toggle relay return immediately.
    static func schedule(id: String, step: Int, recipeTitle: String, at end: Date, prefs: TimerPrefs) {
        let alertsOn = prefs.stepAlerts
        let soundOn = prefs.sound && !isQuiet(prefs, at: end)
        stateLock.lock()
        _scheduleSeq += 1
        let seq = _scheduleSeq
        let enqueueEpoch = _epoch
        stateLock.unlock()
        alertQueue.async {
            stateLock.lock(); let stale = enqueueEpoch != _epoch; stateLock.unlock()
            if stale {
                record(seq, "refused stale schedule for ate.timer.\(id): superseded by clear-all")
                return
            }
            var refusal: String? = nil
            drainCond.lock(); _inFlightAdds += 1; drainCond.unlock()
            performSystemSchedule(id, {
                guard alertsOn else { return nil }
                let interval = end.timeIntervalSince(now())
                if interval <= 0 {
                    refusal = "refused expired schedule for ate.timer.\(id)"
                    return nil
                }
                let content = UNMutableNotificationContent()
                content.title = "Step \(step) is done"
                content.body = recipeTitle
                content.sound = soundOn ? UNNotificationSound(named: UNNotificationSoundName("ate-chime.wav")) : nil
                content.interruptionLevel = .timeSensitive
                return UNNotificationRequest(identifier: "ate.timer." + id, content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
            }) { error in
                drainCond.lock(); _inFlightAdds -= 1; drainCond.signal(); drainCond.unlock()
                record(seq, refusal ?? error.map { String(describing: $0) })
            }
        }
    }

    static func cancel(id: String) {
        alertQueue.async {
            performSystemSchedule(id, { nil }, { _ in })
        }
    }

    /// Clear-all (lane 3): removes pending AND delivered notifications, then verifies
    /// once after the system's asynchronous removal settles. No retry loop: a non-empty
    /// read-back is reported to the caller, never hidden. Covers the "ate.timer."
    /// requests scheduled here and by the widget extension - the only requests the app
    /// family creates.
    static func removeAllAndVerify() async -> Bool {
        // Writer-epoch fence: work enqueued after this point carries the new epoch;
        // anything enqueued earlier that has not yet executed is rejected as stale.
        stateLock.lock()
        _epoch += 1
        _scheduleSeq += 1
        let seq = _scheduleSeq
        stateLock.unlock()
        fenceInstalled()
        // Ordered erase with an in-flight barrier: the removal runs on alertQueue
        // behind any schedule/cancel already queued, and first waits for add
        // callbacks already initiated. The drainTimeout bound covers only this
        // callback-drain wait once the erase body runs; it is not a total
        // clear-all deadline, since a stalled body ahead on the queue delays the
        // erase body itself. If the work cannot drain, erasure is not claimed:
        // no removal runs, the failure is recorded, and false is returned.
        let drained = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            alertQueue.async {
                drainCond.lock()
                let deadline = Date().addingTimeInterval(drainTimeout)
                while _inFlightAdds > 0 && drainCond.wait(until: deadline) {}
                let drained = _inFlightAdds == 0
                drainCond.unlock()
                if drained { performRemoveAll() }
                cont.resume(returning: drained)
            }
        }
        guard drained else {
            record(seq, "clear-all could not drain in-flight alert work; erasure not claimed")
            return false
        }
        let center = UNUserNotificationCenter.current()
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
