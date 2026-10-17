import SwiftUI

import Combineimport SwiftData

@main
struct AteApp: App {
    let container: ModelContainer?
    @State private var store: AppStore

    init() {
        TabBarStyle.apply()
        if AppConfig.isUITesting {
            for k in ["ate.settings.v1", "ate.timerprefs.v1"] { UserDefaults.standard.removeObject(forKey: k) }
        }
        // Corruption-safe open: a broken store is moved aside and a fresh one opened; never crashes (R-DATA-01).
        let corruptQA = AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaCorruptStore")
        let outcome: StoreRecovery.Outcome
        if corruptQA {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("qa-corrupt-\(UUID().uuidString).store")
            try? Data("not a sqlite database".utf8).write(to: url)
            outcome = StoreRecovery.open(url: url)
        } else {
            outcome = StoreRecovery.open(inMemory: AppConfig.isUITesting)
        }
        let c = outcome.container
        container = c
        let st = AppStore(context: c?.mainContext)
        if outcome.recovered || outcome.inMemoryFallback || (c == nil && !AppConfig.isUITesting) {
            st.recovery = RecoveryInfo(backupPath: outcome.backupURL?.lastPathComponent, inMemory: outcome.inMemoryFallback || c == nil, error: outcome.error)
        }
        StoreSaver.onFailure = { [weak st] msg in st?.show(msg, error: true, seconds: 4) }
        if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaHealthRecipes") && st.recipes.isEmpty {
            st.recipes = HealthFixtures.library
        }
        _store = State(initialValue: st)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { store.handle(url: $0) }
                .task {
                    PhoneWatchBridge.shared.activate()
                    Task { await CoverStore.checkPlayground() }
                    PhoneWatchBridge.shared.update(session: store.session)
                    if let u = AppConfig.launchURL { store.handle(url: u) }
                    if store.recovery != nil { await store.completeRecovery() }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    if let u = a.webpageURL { store.handle(url: u) }
                }
        }
    }
}

/// Sticky timer summary bar, one per stack; it reserves layout space so bottom actions sit above it.
struct TimerBarInset: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        // Applied once per NavigationStack (not per screen), so it can never show twice. Screen-level bottom
        // actions (Cook mode, Add recipe) use their own inner safeAreaInset and therefore sit directly above it.
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            // iOS 26: at tab roots the timer lives in the tab bar's bottom accessory, so the inset only shows on pushed screens.
            if !store.timers.timers.isEmpty && store.cookTarget == nil && !(TabChrome.usesAccessory && store.isAtTabRoot) { TimerBar() }
        }
    }
}
extension View { func withTimerBar() -> some View { modifier(TimerBarInset()) } }

/// Offline strip applied to each screen INSIDE its NavigationStack, so it takes real layout space below the
/// nav bar (C-FIX-03). It used to sit in a root-level safeAreaInset above the stacks and overlapped the
/// nav bar/large title on pushed screens.
struct OfflineStripInset: ViewModifier {
    func body(content: Content) -> some View {
        let isOnline = NetworkMonitor.shared.isOnline
        return content.safeAreaInset(edge: .top, spacing: 0) {
            if !isOnline { OfflineBanner().padding(.vertical, 4).frame(maxWidth: .infinity).transition(.opacity) }
        }
    }
}
extension View { func offlineStrip() -> some View { modifier(OfflineStripInset()) } }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.verticalSizeClass) private var vSize
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store
        Group {
            if vSize == .compact {
                LandscapeSplitView()      // iPhone landscape: custom collapsible sidebar
            } else {
                if #available(iOS 26, *) { tabs26 } else { tabs }   // portrait iPhone: bottom tab bar; iPad: adaptable sidebar
            }
        }
        .onChange(of: vSize) { _, v in
            // Collections are sidebar-only; back in portrait keep the filter but show the Library tab.
            if v != .compact, case .collection = store.tab { store.tab = .library }
        }
        .fullScreenCover(item: $store.cookTarget) { target in
            NavigationStack { CookModeView(recipeID: target.id, onExit: { store.cookTarget = nil }) }.environment(store)
        }
        .fullScreenCover(isPresented: $store.showOnboarding) { OnboardingView().environment(store) }
        .sheet(item: $store.authSheet) { m in AuthSheet(mode: m).environment(store) }
        .onReceive(tick) { date in
            // Avoid publishing a new TimerCenter.now value every 500 ms when no timer is
            // running. Besides needless view work, the constant observation churn makes
            // UI automation wait for the app to become idle for tens of seconds per action.
            guard store.timers.timers.contains(where: \.isRunning) else { return }
            store.timers.tick(date)
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                store.timers.tick(); store.timers.ensureLiveActivities(); store.scheduleSync(delay: 0.2); store.checkInbox()
                WidgetBridge.drainInbox(store)
            // Re-register App Shortcut phrases + parameter values on every launch (Siri learns them after first launch).
            if !AppConfig.isUITesting { AteShortcuts.updateAppShortcutParameters() }
                BetaQA.shared.returnedToForeground(runningTimers: store.timers.timers.filter(\.isRunning).count)
            } else if p == .background {
                BetaQA.shared.wentToBackground(runningTimers: store.timers.timers.filter(\.isRunning).count)
            }
        }
        .task {
            WidgetBridge.drainInbox(store)
            store.timers.ensureLiveActivities()
            BetaQA.shared.launched(recipeCount: store.recipes.count, restoredTimers: store.timers.timers.count)
            if store.session != nil { await store.syncNow() }
        }
        .tint(Theme.primary)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .safeAreaInset(edge: .top, spacing: 0) {
            // One top area: beta banner (tab roots only) and the slim offline strip. Nothing at the bottom competes with actions.
            VStack(spacing: 0) {
                if AppConfig.isBetaBuild && !store.showOnboarding && store.isAtTabRoot { BetaBanner { store.select(.settings); BetaQA.shared.openRequested = true }.padding(.vertical, 4) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if AppConfig.isUITesting {
                Text(QAProbe.shared.summary).font(.system(size: 6)).opacity(0.05)
                    .accessibilityIdentifier("qa.probe").allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(toast: t).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)).id(t.id)
            }
        }
        .sheet(item: Binding(get: { store.recovery }, set: { store.recovery = $0 })) { info in
            NavigationStack { RecoveryView(info: info) }.environment(store)
        }
    }
}

/// Shown once after the local library had to be repaired at launch (R-DATA-01).
struct RecoveryView: View {
    @Environment(AppStore.self) private var store
    let info: RecoveryInfo
    var body: some View {
        List {
            Section {
                Label("Ate repaired its library on this iPhone", systemImage: "wrench.and.screwdriver").font(AteFont.body(16, .semibold))
                Text("The saved data couldn't be opened, so Ate moved it aside and started a fresh library. Nothing was deleted.")
                    .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            }
            Section("What happened") {
                if let b = info.backupPath { LabeledContent("Backup", value: b) }
                if info.inMemory { Text("Running without on-device storage this session; changes sync if you're signed in.") }
                if info.restoredFromSync { LabeledContent("Restored from sync", value: "\(info.restoredCount) recipes") }
                else if store.session == nil { Text("Sign in from Settings to restore your recipes from sync.") }
            }
            if let u = info.exportURL {
                Section { ShareLink(item: u) { Label("Export recovered recipes (JSON)", systemImage: "square.and.arrow.up") } }
            }
        }
        .navigationTitle("Library repaired").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.recovery = nil } } }
        .accessibilityIdentifier("recoveryView")
    }
}

extension View {
    /// iOS 26 soft scroll-edge effect under the nav bar on long lists (C-TAB-05).
    @ViewBuilder func softTopEdge() -> some View {
        if #available(iOS 26, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}

/// iOS 26 tab chrome switches (C-TAB-xx). Older systems keep the floating Add button and the in-app timer bar.
enum TabChrome {
    static var usesAccessory: Bool { if #available(iOS 26, *) { return true }; return false }
}

/// Bottom accessory above the tab bar: "Add recipe", or the timer summary plus a + when timers exist.
@available(iOS 26, *)
struct AteBottomAccessory: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        let compact = placement == .inline
        HStack(spacing: 8) {
            if !store.timers.timers.isEmpty {
                TimerBar().padding(.bottom, -4).padding(.horizontal, -12)
                Button { add() } label: { Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Add recipe").accessibilityIdentifier("accessoryAdd")
            } else {
                Button { add() } label: {
                    Label(compact ? "Add" : "Add recipe", systemImage: "plus").font(AteFont.body(15, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Add recipe").accessibilityIdentifier("accessoryAdd")
            }
        }
        .padding(.horizontal, compact ? 4 : 12)
        .accessibilityElement(children: .contain).accessibilityIdentifier("bottomAccessory")
    }
    private func add() {
        if store.tab != .library { store.select(.library) }
        store.quickAdd = QuickAddRequest(mode: .link)
    }
}

extension RootView {
    /// iOS 26: core tabs + Search, bottom accessory, minimise on scroll. Beta tools live in Settings.
    @available(iOS 26, *)
    @ViewBuilder var tabs26: some View {
        @Bindable var store = store
        TabView(selection: tabSelection) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: $store.path) {
                    LibraryView(searchPlacement: .none).offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Shopping", systemImage: "basket", value: AppTab.shopping) {
                NavigationStack(path: $store.shoppingPath) {
                    ShoppingListView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            .badge(store.pendingShoppingCount)
            Tab("Insights", systemImage: "heart.text.square", value: AppTab.tracker) {
                NavigationStack(path: $store.trackerPath) {
                    CookingTrackerScreen().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack(path: $store.settingsPath) {
                    SettingsView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $store.searchPath) {
                    LibraryView(searchPlacement: .tabBar).offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            // Pushed screens reserve their own timer-bar inset. Keeping the accessory
            // at tab roots avoids a second timer bar beneath RecipeDetailView's Cook mode.
            if store.cookTarget == nil && store.isAtTabRoot { AteBottomAccessory() }
        }
    }

    /// Compact tab bar: core destinations only. Beta tools live in Settings; collections remain in the landscape sidebar.
    @ViewBuilder var tabs: some View {
        @Bindable var store = store
        TabView(selection: tabSelection) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: $store.path) {
                    LibraryView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Shopping", systemImage: "basket", value: AppTab.shopping) {
                NavigationStack(path: $store.shoppingPath) {
                    ShoppingListView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            .badge(store.pendingShoppingCount)
            Tab("Insights", systemImage: "heart.text.square", value: AppTab.tracker) {
                NavigationStack(path: $store.trackerPath) {
                    CookingTrackerScreen().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack(path: $store.settingsPath) {
                    SettingsView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
        }
        .tabViewStyle(.tabBarOnly)
    }

    /// Re-tapping the current tab pops its stack to the root (standard iOS behaviour).
    var tabSelection: Binding<AppTab> {
        Binding(get: { if case .collection = store.tab { return .library }; return store.tab }, set: { new in
            if new == store.tab {
                switch new {
                case .library, .collection: store.path = []
                case .shopping: store.shoppingPath = []
                case .tracker: store.trackerPath = []
                case .settings: store.settingsPath = []
                case .more: store.morePath = []
                case .search: store.searchPath = []
                }
            }
            store.select(new)
        })
    }
}

/// Destination for every NavigationStack.
struct RouteView: View {
    let route: Route
    var body: some View {
        Group {
            switch route {
            case .recipe(let id): RecipeDetailView(recipeID: id)
            case .cook(let id): CookModeView(recipeID: id)
            case .shopping: ShoppingListView()
            case .settings: SettingsView()
            case .shared(let slug): SharedRecipeView(slug: slug)
            case .notFound: NotFoundView()
            case .insights: InsightsView()
            case .beta: AppConfig.isBetaBuild ? AnyView(BetaTestingView()) : AnyView(SettingsView())
            case .betaNote: AppConfig.isBetaBuild ? AnyView(BetaExpectationsView()) : AnyView(SettingsView())
            case .journal: JournalListView()
            case .journalEntry(let id): JournalEntryDetailView(entryID: id)
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .offlineStrip()
    }
}

enum SidebarModel {
    static func collections(_ recipes: [RecipeCard]) -> [RecipeCollection] {
        [.quick, .favourites, .recentlyAdded, .recentlyCooked] + IngredientTags.collections(in: recipes).map { .ingredient($0) }
    }
}

/// iPhone landscape: custom collapsible sidebar (Library / Shopping / Settings + Collections) beside the selected stack.
/// (NavigationSplitView collapses to a single stack at compact width on non-Max iPhones, so this is hand-built.)
struct LandscapeSplitView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("ate.sidebar.visible") private var showSidebar = true

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            if showSidebar {
                List {
                    Section {
                        row(.library, "Library", "books.vertical")
                        row(.shopping, "Shopping list", "basket", badge: store.pendingShoppingCount)
                        row(.tracker, "Insights", "heart.text.square")
                        row(.settings, "Settings", "gearshape")
                    }
                    Section("Collections") {
                        ForEach(SidebarModel.collections(store.recipes), id: \.self) { c in row(.collection(c), c.title, c.symbol) }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Theme.muted.opacity(0.35))
                .frame(width: 240)
                .accessibilityIdentifier("sidebar")
                .transition(.move(edge: .leading))
                Divider()
            }
            Group {
                switch store.tab {
                case .library, .collection:
                    NavigationStack(path: $store.path) {
                        LibraryView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .shopping:
                    NavigationStack(path: $store.shoppingPath) {
                        ShoppingListView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .tracker:
                    NavigationStack(path: $store.trackerPath) {
                        CookingTrackerScreen().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .more:
                    NavigationStack(path: $store.morePath) {
                        MoreView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .settings, .search:
                    NavigationStack(path: $store.settingsPath) {
                        SettingsView().offlineStrip().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomLeading) {
            Button { withAnimation(Motion.anim(.snappy)) { showSidebar.toggle() } } label: {
                Image(systemName: "sidebar.left").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(showSidebar ? "Hide sidebar" : "Show sidebar")
            .accessibilityIdentifier("sidebarToggle")
            .padding(12)
        }
        .tint(Theme.primary)
    }

    private func row(_ t: AppTab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        Button { store.select(t) } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if badge > 0 { Text("\(badge)").font(AteFont.body(12, .semibold)).monospacedDigit().foregroundStyle(Theme.mutedForeground) }
            }
        }
        .listRowBackground(store.tab == t ? Theme.primary.opacity(0.15) : Color.clear)
        .foregroundStyle(store.tab == t ? Theme.primary : Theme.foreground)
        .accessibilityIdentifier("sidebar." + title)
        .accessibilityAddTraits(store.tab == t ? .isSelected : [])
    }
}

/// Selected tab = brand tint (via `.tint`), unselected = secondary label; same symbol weight for every item.
enum TabBarStyle {
    static func apply() {
        // System navigation bars keep the brand serif on large and inline titles.
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        let serif = { (size: CGFloat) -> UIFont in
            UIFont(name: "Fraunces", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) }
                ?? .boldSystemFont(ofSize: size)
        }
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: serif(32))]
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: serif(18))]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Theme.primary)
        let a = UITabBarAppearance()
        a.configureWithDefaultBackground()
        let sel = UIColor(Theme.primary), off = UIColor.secondaryLabel
        for l in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            l.selected.iconColor = sel
            l.selected.titleTextAttributes = [.foregroundColor: sel, .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
            l.normal.iconColor = off
            l.normal.titleTextAttributes = [.foregroundColor: off, .font: UIFont.systemFont(ofSize: 10, weight: .medium)]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
        UITabBar.appearance().unselectedItemTintColor = off
    }
}
