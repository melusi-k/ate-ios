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
    /// Writes inside the writer boundary's effect. Returns false when the
    /// boundary refused the effect; nothing was written.
    @discardableResult
    func save(_ d: UserDefaults = SharedContainer.defaults, boundary: SharedWriterBoundary = .current) -> Bool {
        (try? boundary.withEffect { () -> Void in
            d.set(try? JSONEncoder().encode(self), forKey: Self.key)
        }) != nil
    }

    /// Unticked items first (in list order), for the widget and the inline Lock Screen accessory.
    var openItems: [Item] { shopping.filter { !$0.done } }
    var nextItem: Item? { openItems.first }

    /// Applies a tick from the widget to the snapshot so the widget re-renders before the app runs.
    mutating func setDone(_ id: String, _ done: Bool) {
        if let i = shopping.firstIndex(where: { $0.id == id }) { shopping[i].done = done }
    }
}

/// Do not tell someone to repeat setup when this installation cannot share data.
/// No snapshot is not a zero-day streak, empty library or completed shopping list.
enum WidgetDataMessage {
    static func unavailable(groupAvailable: Bool) -> String {
        groupAvailable
            ? "Open ate and refresh widgets in Beta testing."
            : "Shared widget data is unavailable. Open ate for widget diagnostics."
    }
}

/// App-side publication cache. The explicit repair path must rewrite an unchanged
/// snapshot if its saved bytes were lost, and request each affected timeline once.
struct WidgetSnapshotPublisher {
    private var lastPublished: WidgetSnapshot?

    @discardableResult
    mutating func publish(_ value: WidgetSnapshot, force: Bool = false,
                          defaults: UserDefaults = SharedContainer.defaults,
                          boundary: SharedWriterBoundary = .current,
                          reload: ([String]) -> Void) -> Bool {
        let changed: [String]
        if let old = lastPublished, !force {
            var kinds: [String] = []
            if old.favourites != value.favourites { kinds.append(WidgetKinds.favourites) }
            if old.shopping != value.shopping { kinds += [WidgetKinds.shopping, WidgetKinds.shoppingInline] }
            if old.pick != value.pick { kinds.append(WidgetKinds.pick) }
            if old.cookingStreak != value.cookingStreak || old.cookedToday != value.cookedToday { kinds.append(WidgetKinds.cooking) }
            changed = kinds
        } else {
            changed = [WidgetKinds.favourites, WidgetKinds.shopping, WidgetKinds.shoppingInline, WidgetKinds.pick, WidgetKinds.cooking]
        }
        guard !changed.isEmpty else { return false }
        // The save and the in-memory publish cache commit under one effect, so a
        // concurrent gated writer never sees half of the update. The reload is a
        // hint and runs only after a committed publish, outside the boundary.
        guard (try? boundary.withEffect { () -> Void in
            value.save(defaults, boundary: boundary)
            lastPublished = value
        }) != nil else { return false }
        reload(changed)
        return true
    }
}

/// Changes made from widgets / controls / Siri while the app wasn't running. The app applies them when it becomes active.
enum WidgetInbox {
    static let shoppingKey = "ate.widgets.pending.shopping.v1"   // [itemID: done]
    static let addsKey = "ate.widgets.pending.adds.v1"           // [name]
    static let urlKey = "ate.widgets.pending.url.v1"             // deep link to open on next activation

    /// Queues a tick as one gated read-modify-write, so concurrent widget and
    /// app writers cannot lose each other's entries. Returns false (nothing
    /// queued) when the boundary refused the effect.
    @discardableResult
    static func setDone(_ id: String, _ done: Bool, _ d: UserDefaults = SharedContainer.defaults,
                        boundary: SharedWriterBoundary = .current) -> Bool {
        (try? boundary.withEffect { () -> Void in
            var m = pendingShopping(d); m[id] = done
            d.set(try? JSONEncoder().encode(m), forKey: shoppingKey)
        }) != nil
    }
    static func pendingShopping(_ d: UserDefaults = SharedContainer.defaults) -> [String: Bool] {
        d.data(forKey: shoppingKey).flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
    }
    /// Queues an added item as one gated read-modify-write. Returns false (and
    /// queues nothing) for a blank name or when the boundary refused the effect.
    @discardableResult
    static func addItem(_ name: String, _ d: UserDefaults = SharedContainer.defaults,
                        boundary: SharedWriterBoundary = .current) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        return (try? boundary.withEffect { () -> Void in
            d.set(pendingAdds(d) + [n], forKey: addsKey)
        }) != nil
    }
    static func pendingAdds(_ d: UserDefaults = SharedContainer.defaults) -> [String] { d.stringArray(forKey: addsKey) ?? [] }
    /// Gated so the write can never interleave with the app's drain and be lost.
    /// Returns false when the boundary refused the effect.
    @discardableResult
    static func openLater(_ url: URL, _ d: UserDefaults = SharedContainer.defaults,
                          boundary: SharedWriterBoundary = .current) -> Bool {
        (try? boundary.withEffect { () -> Void in
            d.set(url.absoluteString, forKey: urlKey)
        }) != nil
    }

    /// Returns everything queued and clears the queue as one gated effect, so a
    /// writer in another process cannot write between the read and the clear and
    /// have it silently dropped. A refused effect returns an empty result and
    /// leaves the queue intact for the next activation.
    static func drain(_ d: UserDefaults = SharedContainer.defaults,
                      boundary: SharedWriterBoundary = .current) -> (shopping: [String: Bool], adds: [String], url: URL?) {
        (try? boundary.withEffect {
            let s = pendingShopping(d), a = pendingAdds(d), u = d.string(forKey: urlKey).flatMap(URL.init(string:))
            d.removeObject(forKey: shoppingKey); d.removeObject(forKey: addsKey); d.removeObject(forKey: urlKey)
            return (s, a, u)
        }) ?? ([:], [], nil)
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
