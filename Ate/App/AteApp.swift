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
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store
        TabView(selection: tabSelection) {
            NavigationStack(path: $store.path) {
                LibraryView().withTimerBar().navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)
            .accessibilityIdentifier("tab.library")

            NavigationStack(path: $store.shoppingPath) {
                ShoppingListView().withTimerBar().navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Shopping list", systemImage: "basket") }
            .badge(store.pendingShoppingCount)
            .tag(AppTab.shopping)

            NavigationStack(path: $store.settingsPath) {
                SettingsView().withTimerBar().navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
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
    /// Re-tapping the current tab pops its stack to the root (standard iOS behaviour).
    var tabSelection: Binding<AppTab> {
        Binding(get: { store.tab }, set: { new in
            if new == store.tab {
                switch new {
                case .library: store.path = []
                case .shopping: store.shoppingPath = []
                case .settings: store.settingsPath = []
                }
            }
            store.tab = new
        })
    }

    @ViewBuilder func destination(_ route: Route) -> some View {
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

