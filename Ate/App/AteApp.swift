import SwiftUI
import SwiftData

@main
struct AteApp: App {
    let container: ModelContainer?
    @State private var store: AppStore

    init() {
        if AppConfig.isUITesting {
            for k in ["ate.settings.v1", "ate.timerprefs.v1"] { UserDefaults.standard.removeObject(forKey: k) }
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: AppConfig.isUITesting)
        let c = try? ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: config)
        container = c
        _store = State(initialValue: AppStore(context: c?.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { store.handle(url: $0) }
                .task { if let u = AppConfig.launchURL { store.handle(url: u) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    if let u = a.webpageURL { store.handle(url: u) }
                }
        }
    }
}

/// Sticky timer bar, applied per screen so it reserves layout space (floating buttons sit above it).
struct TimerBarInset: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
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
            CookModeView(recipeID: target.id, onExit: { store.cookTarget = nil }).environment(store)
        }
        .fullScreenCover(isPresented: $store.showOnboarding) { OnboardingView().environment(store) }
        .sheet(item: $store.authSheet) { m in AuthSheet(mode: m).environment(store) }
        .onReceive(tick) { store.timers.tick($0) }
        .onChange(of: phase) { _, p in if p == .active { store.timers.tick(); store.scheduleSync(delay: 0.2); store.checkInbox() } }
        .task { if store.session != nil { await store.syncNow() } }
        .tint(Theme.primary)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .overlay(alignment: .bottom) {
            if !NetworkMonitor.shared.isOnline && store.cookTarget == nil {
                OfflineBanner().padding(.bottom, 84).transition(.opacity)
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
    /// iOS 18+ `Tab`/`TabSection` API with `.sidebarAdaptable` (sidebar on iPad, tab bar on iPhone).
    @ViewBuilder var tabs: some View {
        @Bindable var store = store
        TabView(selection: tabSelection) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: $store.path) {
                    LibraryView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("Shopping list", systemImage: "basket", value: AppTab.shopping) {
                NavigationStack(path: $store.shoppingPath) {
                    ShoppingListView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            .badge(store.pendingShoppingCount)
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack(path: $store.settingsPath) {
                    SettingsView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            TabSection("Collections") {
                ForEach(SidebarModel.collections(store.recipes), id: \.self) { c in
                    Tab(c.title, systemImage: c.symbol, value: AppTab.collection(c)) {
                        NavigationStack(path: $store.path) {
                            LibraryView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                        }
                    }
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)   // collections live in the sidebar only
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// Re-tapping the current tab pops its stack to the root (standard iOS behaviour).
    var tabSelection: Binding<AppTab> {
        Binding(get: { store.tab }, set: { new in
            if new == store.tab {
                switch new {
                case .library, .collection: store.path = []
                case .shopping: store.shoppingPath = []
                case .settings: store.settingsPath = []
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
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withTimerBar()
    }
}

enum SidebarModel {
    static func collections(_ recipes: [RecipeCard]) -> [RecipeCollection] {
        [.quick, .favourites, .recentlyAdded, .recentlyCooked] + IngredientTags.collections(in: recipes).map { .ingredient($0) }
    }
}

/// iPhone landscape: collapsible sidebar (Library / Shopping / Settings + Collections) beside the selected stack.
struct LandscapeSplitView: View {
    @Environment(AppStore.self) private var store
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns) {
            List {
                Section {
                    row(.library, "Library", "books.vertical")
                    row(.shopping, "Shopping list", "basket", badge: store.pendingShoppingCount)
                    row(.settings, "Settings", "gearshape")
                }
                Section("Collections") {
                    ForEach(SidebarModel.collections(store.recipes), id: \.self) { c in row(.collection(c), c.title, c.symbol) }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("ate")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .accessibilityIdentifier("sidebar")
        } detail: {
            switch store.tab {
            case .library, .collection:
                NavigationStack(path: $store.path) {
                    LibraryView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            case .shopping:
                NavigationStack(path: $store.shoppingPath) {
                    ShoppingListView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            case .settings:
                NavigationStack(path: $store.settingsPath) {
                    SettingsView().withTimerBar().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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
