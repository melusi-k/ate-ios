import Foundation
import UserNotifications
import UIKit
import AudioToolbox

enum TimerAlerts {
    static func requestPermission() async -> Bool {
        if AppConfig.isUITesting { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .timeSensitive])) ?? false
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

    static func schedule(id: String, step: Int, recipeTitle: String, at end: Date, prefs: TimerPrefs) {
        cancel(id: id)
        guard prefs.stepAlerts else { return }
        let content = UNMutableNotificationContent()
        content.title = "Step \(step) is done"
        content.body = recipeTitle
        content.sound = (prefs.sound && !isQuiet(prefs, at: end)) ? .default : nil
        content.interruptionLevel = .timeSensitive
        let interval = max(1, end.timeIntervalSinceNow)
        let req = UNNotificationRequest(identifier: "ate.timer." + id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ate.timer." + id])
    }

    /// Foreground finish: chime + haptics (the scheduled notification covers background).
    @MainActor static func timerFinished(prefs: TimerPrefs) {
        if prefs.sound && !isQuiet(prefs) {
            // Three-tone chime approximation using system sounds (no bundled audio yet).
            for (i, delay) in [0.0, 0.28, 0.56].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { AudioServicesPlaySystemSound(i == 2 ? 1057 : 1104) }
            }
        }
        if prefs.vibration { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
