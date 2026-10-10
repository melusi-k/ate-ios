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

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            LibraryView()
                .navigationDestination(for: Route.self) { route in
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
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.timers.timers.isEmpty && store.cookTarget == nil { TimerBar() }
        }
        .fullScreenCover(item: $store.cookTarget) { target in
            CookModeView(recipeID: target.id, onExit: { store.cookTarget = nil }).environment(store)
        }
        .onReceive(tick) { store.timers.tick($0) }
        .onChange(of: phase) { _, p in if p == .active { store.timers.tick(); store.scheduleSync(delay: 0.2) } }
        .task { if store.session != nil { await store.syncNow() } }
        .tint(Theme.primary)
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(toast: t).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)).id(t.id)
            }
        }
    }
}
