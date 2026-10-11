import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Data the app publishes for its widgets, controls and Lock Screen accessories (App Group JSON).
/// Compiled into the app and the AteWidgets extension. Pure Codable + helpers, so it is unit-tested in AteTests.
struct WidgetSnapshot: Codable, Equatable {
    struct Recipe: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var minutes: Int?
        var favorite: Bool
        /// File name in the App Group's Covers folder (nil = branded tile).
        var cover: String?
        var stepCount: Int
    }
    struct Item: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var done: Bool
    }
    struct Pick: Codable, Equatable {
        var recipeID: String
        var title: String
        var why: String
        var minutes: Int?
        var cover: String?
        /// Health state title ("Recovery day"), nil when Health isn't connected.
        var healthTitle: String?
        var healthSymbol: String?
    }

    var updatedAt: Date = Date()
    var favourites: [Recipe] = []
    var shopping: [Item] = []
    var pick: Pick?
    var recipeCount: Int = 0
    var cookingStreak: Int = 0
    var cookedToday: Bool = false

    static let key = "ate.widgets.snapshot.v1"
    static let maxFavourites = 4
    static let maxShopping = 8

    static func load(_ d: UserDefaults = SharedContainer.defaults) -> WidgetSnapshot? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }
    func save(_ d: UserDefaults = SharedContainer.defaults) {
        d.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// Unticked items first (in list order), for the widget and the inline Lock Screen accessory.
    var openItems: [Item] { shopping.filter { !$0.done } }
    var nextItem: Item? { openItems.first }

    /// Applies a tick from the widget to the snapshot so the widget re-renders before the app runs.
    mutating func setDone(_ id: String, _ done: Bool) {
        if let i = shopping.firstIndex(where: { $0.id == id }) { shopping[i].done = done }
    }
}

/// Changes made from widgets / controls / Siri while the app wasn't running. The app applies them when it becomes active.
enum WidgetInbox {
    static let shoppingKey = "ate.widgets.pending.shopping.v1"   // [itemID: done]
    static let addsKey = "ate.widgets.pending.adds.v1"           // [name]
    static let urlKey = "ate.widgets.pending.url.v1"             // deep link to open on next activation

    static func setDone(_ id: String, _ done: Bool, _ d: UserDefaults = SharedContainer.defaults) {
        var m = pendingShopping(d); m[id] = done
        d.set(try? JSONEncoder().encode(m), forKey: shoppingKey)
    }
    static func pendingShopping(_ d: UserDefaults = SharedContainer.defaults) -> [String: Bool] {
        d.data(forKey: shoppingKey).flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
    }
    static func addItem(_ name: String, _ d: UserDefaults = SharedContainer.defaults) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        d.set(pendingAdds(d) + [n], forKey: addsKey)
    }
    static func pendingAdds(_ d: UserDefaults = SharedContainer.defaults) -> [String] { d.stringArray(forKey: addsKey) ?? [] }
    static func openLater(_ url: URL, _ d: UserDefaults = SharedContainer.defaults) { d.set(url.absoluteString, forKey: urlKey) }

    /// Returns everything queued and clears the queue.
    static func drain(_ d: UserDefaults = SharedContainer.defaults) -> (shopping: [String: Bool], adds: [String], url: URL?) {
        let s = pendingShopping(d), a = pendingAdds(d), u = d.string(forKey: urlKey).flatMap(URL.init(string:))
        d.removeObject(forKey: shoppingKey); d.removeObject(forKey: addsKey); d.removeObject(forKey: urlKey)
        return (s, a, u)
    }
}

/// ate:// deep links used by widgets, controls and intents.
enum WidgetLinks {
    enum AddMode: String, CaseIterable, Codable { case link, photo, prompt }
    enum Target: Equatable {
        case recipe(String), cook(String), add(AddMode), shopping, timers
    }
    static func recipe(_ id: String) -> URL { URL(string: "ate://open/\(enc(id))")! }
    static func cook(_ id: String) -> URL { URL(string: "ate://cook/\(enc(id))")! }
    static func add(_ m: AddMode) -> URL { URL(string: "ate://add/\(m.rawValue)")! }
    static let shopping = URL(string: "ate://shopping")!
    static let timers = URL(string: "ate://timers")!

    static func parse(_ url: URL) -> Target? {
        guard url.scheme == "ate" else { return nil }
        let last = url.pathComponents.filter { $0 != "/" }.last?.removingPercentEncoding
        switch url.host {
        case "open": return last.map { .recipe($0) }
        case "cook": return last.map { .cook($0) }
        case "add": return .add(last.flatMap(AddMode.init(rawValue:)) ?? .link)
        case "shopping": return .shopping
        case "timers": return .timers
        default: return nil
        }
    }
    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
}

/// Text shown by the timer widgets and Lock Screen accessories.
enum WidgetFormat {
    static func mmss(_ s: Int) -> String {
        let s = max(0, s)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
    /// "Step 4 · Simmer the tripe · 12:40 left" (paused: "· paused 12:40").
    static func stepLine(_ t: TimerSnapshot, now: Date = Date()) -> String {
        let title = t.stepText.split(separator: ".").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? t.stepText
        let short = title.count > 28 ? String(title.prefix(27)) + "…" : title
        let rem = TimerMath.remaining(t, now: now)
        let label = t.recipeID == TimerMath.quickRecipeID ? "Kitchen timer" : "Step \(t.stepIndex + 1)"
        return t.endDate == nil ? "\(label) · \(short) · paused \(mmss(rem))" : "\(label) · \(short) · \(mmss(rem)) left"
    }
}

/// Pure timer rules shared by the app, widget buttons and controls (operate on the App Group `TimerSnapshot` list).
enum TimerMath {
    static let quickRecipeID = "ate.quick"
    static let quickSeconds = 5 * 60

    static func id(_ t: TimerSnapshot) -> String { "\(t.recipeID)#\(t.stepIndex)" }
    static func remaining(_ t: TimerSnapshot, now: Date = Date()) -> Int {
        if let e = t.endDate { return max(0, Int(ceil(e.timeIntervalSince(now)))) }
        return t.pausedRemaining
    }
    /// Running timers first (soonest end), then paused ones; finished timers are dropped.
    static func ordered(_ all: [TimerSnapshot], now: Date = Date()) -> [TimerSnapshot] {
        let live = all.filter { $0.endDate == nil || $0.endDate! > now }
        return live.sorted { a, b in
            switch (a.endDate, b.endDate) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.stepIndex < b.stepIndex
            }
        }
    }
    static func next(_ all: [TimerSnapshot], now: Date = Date()) -> TimerSnapshot? { ordered(all, now: now).first }

    enum Command: String, Codable { case pause, resume, toggle, stop }

    /// Applies a command to the list. Returns the new list and the affected timer (after the change; nil if stopped/missing).
    static func apply(_ cmd: Command, id: String, to all: [TimerSnapshot], now: Date = Date()) -> [TimerSnapshot] {
        var list = all
        guard let i = list.firstIndex(where: { Self.id($0) == id }) else { return list }
        var t = list[i]
        let running = t.endDate != nil
        switch cmd {
        case .stop: list.remove(at: i); return list
        case .pause where running, .toggle where running:
            t.pausedRemaining = remaining(t, now: now); t.endDate = nil
        case .resume where !running, .toggle where !running:
            if t.pausedRemaining <= 0 { t.pausedRemaining = t.total }
            t.endDate = now.addingTimeInterval(TimeInterval(t.pausedRemaining))
        default: return list
        }
        list[i] = t
        return list
    }

    /// Kitchen-timer control: pause the running timer, else resume a paused one, else start a quick timer.
    static func kitchenToggle(_ all: [TimerSnapshot], now: Date = Date(), seconds: Int = quickSeconds) -> (list: [TimerSnapshot], action: String) {
        let live = ordered(all, now: now)
        if let r = live.first(where: { $0.endDate != nil }) { return (apply(.pause, id: id(r), to: all, now: now), "paused") }
        if let p = live.first { return (apply(.resume, id: id(p), to: all, now: now), "resumed") }
        let q = TimerSnapshot(recipeID: quickRecipeID, recipeTitle: "Kitchen timer", stepIndex: 0, stepCount: 1,
                              stepText: "Kitchen timer", total: seconds, endDate: now.addingTimeInterval(TimeInterval(seconds)),
                              pausedRemaining: seconds)
        return (all + [q], "started")
    }
}

/// Widget kinds, so the app reloads exactly what changed.
enum WidgetKinds {
    static let timers = "ate.widget.timers"
    static let pick = "ate.widget.pick"
    static let shopping = "ate.widget.shopping"
    static let shoppingInline = "ate.widget.shopping.inline"
    static let quickAdd = "ate.widget.quickadd"
    static let favourites = "ate.widget.favourites"
    static let cooking = "ate.widget.cooking"
    static let kitchenControl = "ate.control.kitchentimer"
    static let quickAddControl = "ate.control.quickadd"
    /// Written by the widget extension when it builds a timeline: proves the extension can read the App Group.
    static let heartbeatKey = "ate.widgets.heartbeat.v1"

    static func reload(_ kinds: [String]) {
        #if canImport(WidgetKit)
        for k in kinds { WidgetCenter.shared.reloadTimelines(ofKind: k) }
        if kinds.contains(timers) {
            ControlCenter.shared.reloadControls(ofKind: kitchenControl)
        }
        #endif
    }
    static func reloadAll() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        #endif
    }
}

/// Cover thumbnails from the App Group Covers folder (same location as the app's CoverStore).
enum WidgetCovers {
    static func url(_ file: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedContainer.groupID)?
            .appendingPathComponent("Covers", isDirectory: true).appendingPathComponent(file)
    }
}
