import AppIntents
import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hooks the app installs so intents that run in the app's process act on the live TimerCenter / AppStore
/// (keeps notifications, Live Activities and the UI in step). In the widget extension they stay nil and the
/// intents fall back to editing the App Group snapshot, which the app picks up when it becomes active.
@MainActor
enum IntentRelay {
    static var timer: ((TimerMath.Command, String) -> Void)?
    static var kitchenToggle: (() -> String)?
    static var toggleShopping: ((String, Bool) -> Void)?
    static var addShopping: ((String) -> Void)?
    static var open: ((URL) -> Void)?
}

@MainActor
enum SharedTimerOps {
    /// The whole load/apply/save runs inside the writer boundary, so a timer
    /// command from a widget, control or Siri can never interleave with the app's
    /// own timer writes. A durable nonpersonal OS-submission token is installed
    /// under that same effect, before releasing the flock. Reset/auth rotation
    /// refuse until all awaited notification adds finish and the token is removed.
    /// No flock crosses a suspension.
    static func run(_ cmd: TimerMath.Command, id: String,
                    boundary: SharedWriterBoundary = .current) async {
        if let r = IntentRelay.timer { r(cmd, id); return }
        guard let pair = try? boundary.withEffect({ () -> (before: [TimerSnapshot], after: [TimerSnapshot], submission: SharedNotificationSubmission.Token) in
            let submission = try SharedNotificationSubmission.begin(directory: SharedWriterGateComposition.controlDirectory())
            let before = TimerSnapshot.load()
            let after = TimerMath.apply(cmd, id: id, to: before)
            TimerSnapshot.save(after, boundary: boundary)
            return (before, after, submission)
        }) else { return } // boundary refused: leave state, notifications and UI unchanged
        await reschedule(before: pair.before, after: pair.after)
        try? pair.submission.finish()
        WidgetKinds.reload([WidgetKinds.timers])
    }

    static func kitchenToggle(boundary: SharedWriterBoundary = .current) async -> String {
        if let r = IntentRelay.kitchenToggle { return r() }
        guard let result = try? boundary.withEffect({ () -> (before: [TimerSnapshot], after: [TimerSnapshot], action: String, submission: SharedNotificationSubmission.Token) in
            let submission = try SharedNotificationSubmission.begin(directory: SharedWriterGateComposition.controlDirectory())
            let before = TimerSnapshot.load()
            let res = TimerMath.kitchenToggle(before)
            TimerSnapshot.save(res.list, boundary: boundary)
            return (before, res.list, res.action, submission)
        }) else { return "unavailable" } // boundary refused: nothing changed
        await reschedule(before: result.before, after: result.after)
        try? result.submission.finish()
        WidgetKinds.reload([WidgetKinds.timers])
        return result.action
    }

    /// Keeps the "timer done" notifications right when the app isn't running (same ids as TimerAlerts).
    static func reschedule(before: [TimerSnapshot], after: [TimerSnapshot]) async {
        let c = UNUserNotificationCenter.current()
        let ids = Set(before.map(TimerMath.id)).union(after.map(TimerMath.id))
        c.removePendingNotificationRequests(withIdentifiers: ids.map { "ate.timer." + $0 })
        for t in after {
            guard let end = t.endDate, end > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = t.recipeID == TimerMath.quickRecipeID ? "Kitchen timer done" : "Step \(t.stepIndex + 1) timer done"
            content.body = t.recipeTitle
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            try? await c.add(UNNotificationRequest(identifier: "ate.timer." + TimerMath.id(t), content: content, trigger: trig))
        }
    }
}

// LiveActivityIntent: the system runs these in the app's process when it can (so the Live Activity and
// in-app timers update too); the snapshot fallback covers the widget-extension case.

struct ToggleTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume timer"
    static let isDiscoverable = false
    @Parameter(title: "Timer") var timerID: String
    init() {}
    init(timerID: String) { self.timerID = timerID }
    @MainActor func perform() async throws -> some IntentResult { await SharedTimerOps.run(.toggle, id: timerID); return .result() }
}

struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop timer"
    static let isDiscoverable = false
    @Parameter(title: "Timer") var timerID: String
    init() {}
    init(timerID: String) { self.timerID = timerID }
    @MainActor func perform() async throws -> some IntentResult { await SharedTimerOps.run(.stop, id: timerID); return .result() }
}

/// Siri / Shortcuts: act on the next timer.
struct PauseTimersIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause cook timer"
    static let description = IntentDescription("Pauses the ate timer that ends next.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let t = TimerMath.ordered(TimerSnapshot.load()).first(where: { $0.endDate != nil }) else { return .result(dialog: "No timer is running.") }
        await SharedTimerOps.run(.pause, id: TimerMath.id(t)); return .result(dialog: "Paused \(t.recipeTitle).")
    }
}

struct ResumeTimersIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume cook timer"
    static let description = IntentDescription("Resumes the paused ate timer.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let t = TimerMath.ordered(TimerSnapshot.load()).first(where: { $0.endDate == nil }) else { return .result(dialog: "No timer is paused.") }
        await SharedTimerOps.run(.resume, id: TimerMath.id(t)); return .result(dialog: "Resumed \(t.recipeTitle).")
    }
}

struct StopTimersIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop cook timer"
    static let description = IntentDescription("Stops the ate timer that ends next.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let t = TimerMath.next(TimerSnapshot.load()) else { return .result(dialog: "No timers to stop.") }
        await SharedTimerOps.run(.stop, id: TimerMath.id(t)); return .result(dialog: "Stopped \(t.recipeTitle).")
    }
}

/// Control Center / Action button: pause the running timer, resume a paused one, or start a 5-minute kitchen timer.
struct KitchenTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Kitchen timer"
    static let description = IntentDescription("Starts a 5-minute kitchen timer, or pauses / resumes the running one.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let a = await SharedTimerOps.kitchenToggle()
        return .result(dialog: "Timer \(a).")
    }
}

/// Widget checkbox: tick a shopping item off without opening the app.
struct ToggleShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick shopping item"
    static let isDiscoverable = false
    @Parameter(title: "Item") var itemID: String
    @Parameter(title: "Done") var done: Bool
    init() {}
    init(itemID: String, done: Bool) { self.itemID = itemID; self.done = done }
    @MainActor func perform() async throws -> some IntentResult {
        if let r = IntentRelay.toggleShopping { r(itemID, done) } else {
            // The inbox entry and the widget snapshot are one unit: a reader must
            // never see the tick in one place but not the other.
            let boundary = SharedWriterBoundary.current
            try? boundary.withEffect {
                WidgetInbox.setDone(itemID, done, boundary: boundary)
                if var s = WidgetSnapshot.load() { s.setDone(itemID, done); s.save(boundary: boundary) }
            }
        }
        WidgetKinds.reload([WidgetKinds.shopping, WidgetKinds.shoppingInline])
        return .result()
    }
}

enum QuickAddMode: String, AppEnum, CaseIterable {
    case link, photo, prompt
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Add from"
    static let caseDisplayRepresentations: [QuickAddMode: DisplayRepresentation] = [
        .link: DisplayRepresentation(title: "Link", image: .init(systemName: "link")),
        .photo: DisplayRepresentation(title: "Photo", image: .init(systemName: "photo")),
        .prompt: DisplayRepresentation(title: "Prompt", image: .init(systemName: "pencil.line")),
    ]
    var link: WidgetLinks.AddMode { WidgetLinks.AddMode(rawValue: rawValue) ?? .link }
}

/// Opens ate straight on Add recipe (Quick add widget, Control Center, Action button).
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a recipe"
    static let description = IntentDescription("Opens ate on Add recipe, ready for a link, a photo or a prompt.")
    static let openAppWhenRun = true
    @Parameter(title: "From", default: .link) var mode: QuickAddMode
    init() {}
    init(mode: QuickAddMode) { self.mode = mode }
    @MainActor func perform() async throws -> some IntentResult {
        let u = WidgetLinks.add(mode.link)
        if let o = IntentRelay.open { o(u) } else { WidgetInbox.openLater(u) }
        return .result()
    }
}
