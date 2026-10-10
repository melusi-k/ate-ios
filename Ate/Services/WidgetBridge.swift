import Foundation
import WidgetKit
import CoreSpotlight
import AppIntents

/// App side of widgets, controls and intents: publishes the App Group snapshot, applies changes queued by the
/// widget extension, installs the in-process intent relays and keeps Spotlight's recipe index current.
@MainActor
enum WidgetBridge {
    static let healthKey = "ate.widgets.healthState"
    private static var publishTask: Task<Void, Never>?
    private static var lastPublished: WidgetSnapshot?
    private(set) static var lastIndexed: Int = 0

    static var lastHealthState: HealthState? {
        get { UserDefaults.standard.string(forKey: healthKey).flatMap(HealthState.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: healthKey) }
    }

    /// Debounced: many edits in a row publish once.
    static func publish(_ store: AppStore, delay: Double = 0.4) {
        publishTask?.cancel()
        publishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            publishNow(store)
        }
    }

    static func publishNow(_ store: AppStore) {
        var snap = WidgetSnapshotBuilder.build(recipes: store.recipes, shopping: store.shopping, health: lastHealthState)
        let changed: [String]
        if let old = lastPublished {
            var kinds: [String] = []
            if old.favourites != snap.favourites { kinds.append(WidgetKinds.favourites) }
            if old.shopping != snap.shopping { kinds += [WidgetKinds.shopping, WidgetKinds.shoppingInline] }
            if old.pick != snap.pick { kinds.append(WidgetKinds.pick) }
            changed = kinds
        } else {
            changed = [WidgetKinds.favourites, WidgetKinds.shopping, WidgetKinds.shoppingInline, WidgetKinds.pick]
        }
        if let old = lastPublished, changed.isEmpty { snap.updatedAt = old.updatedAt; return }
        snap.save()
        lastPublished = snap
        WidgetKinds.reload(changed)
        if AppConfig.isUITesting { QAProbe.shared.widgetPublishes += 1 }
        index(store.recipes)
    }

    /// Applies ticks / adds / deep links queued by widgets and intents that ran outside the app.
    static func drainInbox(_ store: AppStore) {
        store.timers.reloadFromShared()
        let q = WidgetInbox.drain()
        for (id, done) in q.shopping { store.setShoppingDone(id, done) }
        for n in q.adds { store.addManual(n) }
        if !q.shopping.isEmpty { BetaQA.shared.pass("A-WIDGET-03", note: "Ticked \(q.shopping.count) item(s) from the widget") }
        if let u = q.url { store.handle(url: u) }
        publish(store, delay: 0)
    }

    /// Intents that run inside the app act on the live store instead of the App Group copy.
    static func installRelays(_ store: AppStore) {
        IntentRelay.timer = { [weak store] cmd, id in
            store?.timers.run(cmd, id: id)
            BetaQA.shared.pass("A-WIDGET-01", note: "Timer \(cmd.rawValue) from a widget/control/Siri")
        }
        IntentRelay.kitchenToggle = { [weak store] in
            let a = store?.timers.kitchenToggle() ?? "unavailable"
            BetaQA.shared.pass("A-CONTROL-01", note: "Kitchen timer \(a)")
            return a
        }
        IntentRelay.toggleShopping = { [weak store] id, done in
            store?.setShoppingDone(id, done)
            BetaQA.shared.pass("A-WIDGET-03", note: "Ticked an item from the widget")
        }
        IntentRelay.addShopping = { [weak store] n in store?.addManual(n) }
        IntentRelay.open = { [weak store] u in store?.handle(url: u) }
    }

    // MARK: diagnostics (Beta testing → Widgets)

    static var heartbeats: [String: Date] {
        ((SharedContainer.defaults.dictionary(forKey: WidgetKinds.heartbeatKey) as? [String: Double]) ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }
    static var diagnostics: String {
        var parts = ["App Group " + (SharedContainer.isAvailable ? "OK" : "missing (widgets can't read ate's data)")]
        parts.append(LiveActivityDiagnostics.widgetAppexPresent ? "widget extension installed" : "widget extension missing (Sideloadly removed it?)")
        if let id = LiveActivityDiagnostics.widgetBundleID { parts.append(id) }
        let hb = heartbeats
        parts.append(hb.isEmpty ? "no widget has loaded yet" : "\(hb.count) widget kind(s) loaded, last \(hb.values.max()!.formatted(date: .omitted, time: .shortened))")
        parts.append("Spotlight: \(lastIndexed) recipes")
        return parts.joined(separator: " · ")
    }

    // MARK: Spotlight (IndexedEntity, iOS 18)

    private static var indexTask: Task<Void, Never>?
    static func index(_ recipes: [RecipeCard]) {
        guard !AppConfig.isUITesting else { lastIndexed = recipes.count; return }
        indexTask?.cancel()
        let entities = recipes.map(RecipeAppEntity.init)
        indexTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            try? await CSSearchableIndex.default().indexAppEntities(entities)
            lastIndexed = entities.count
        }
    }
}
