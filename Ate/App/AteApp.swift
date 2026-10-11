import SwiftUI
import SwiftData

@main
struct AteApp: App {
    let container: ModelContainer?
    @State private var store: AppStore

    init() {
        TabBarStyle.apply()
        if AppConfig.isUITesting {
            for k in ["ate.settings.v1", "ate.timerprefs.v1"] { UserDefaults.standard.removeObject(forKey: k) }
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: AppConfig.isUITesting)
        let c = try? ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: config)
        container = c
        let st = AppStore(context: c?.mainContext)
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
            if !store.timers.timers.isEmpty && store.cookTarget == nil { TimerBar() }
        }
    }
}
extension View { func withTimerBar() -> some View { modifier(TimerBarInset()) } }

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
                tabs                      // portrait iPhone: bottom tab bar; iPad: adaptable sidebar
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
        .onReceive(tick) { store.timers.tick($0) }
        .onChange(of: phase) { _, p in
            if p == .active {
                store.timers.tick(); store.timers.ensureLiveActivities(); store.scheduleSync(delay: 0.2); store.checkInbox()
                WidgetBridge.drainInbox(store)
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
                if !store.showOnboarding && store.isAtTabRoot { BetaBanner { store.tab = .more; BetaQA.shared.openRequested = true }.padding(.vertical, 4) }
                if !NetworkMonitor.shared.isOnline { OfflineBanner().transition(.move(edge: .top).combined(with: .opacity)) }
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
    }
}

extension RootView {
    /// Compact tab bar: exactly four tabs. Collections live in More (portrait) and the landscape sidebar only.
    @ViewBuilder var tabs: some View {
        @Bindable var store = store
        TabView(selection: tabSelection) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: $store.path) {
                    LibraryView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Shopping", systemImage: "basket", value: AppTab.shopping) {
                NavigationStack(path: $store.shoppingPath) {
                    ShoppingListView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            .badge(store.pendingShoppingCount)
            Tab("More", systemImage: "square.grid.2x2", value: AppTab.more) {
                NavigationStack(path: $store.morePath) {
                    MoreView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }.withTimerBar()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack(path: $store.settingsPath) {
                    SettingsView().navigationDestination(for: Route.self) { RouteView(route: $0) }
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
                case .settings: store.settingsPath = []
                case .more: store.morePath = []
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
            case .beta: BetaTestingView()
            case .betaNote: BetaExpectationsView()
            case .journal: JournalListView()
            case .journalEntry(let id): JournalEntryDetailView(entryID: id)
            }
        }
        .toolbarTitleDisplayMode(.inline)
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
                        row(.more, "More", "square.grid.2x2")
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
                        LibraryView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .shopping:
                    NavigationStack(path: $store.shoppingPath) {
                        ShoppingListView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .more:
                    NavigationStack(path: $store.morePath) {
                        MoreView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }.withTimerBar()
                case .settings:
                    NavigationStack(path: $store.settingsPath) {
                        SettingsView().navigationDestination(for: Route.self) { RouteView(route: $0) }
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
