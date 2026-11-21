import SwiftUI

/// The Today tab (#642): the app's default landing tab. Saved recipes lead, the
/// full collection is one tap away ("Recipes"), and the #641 suggestions flow is
/// reachable without opening Add recipe first. Add recipe stays floating: the iOS 26
/// bottom accessory already carries it at this root, and older iOS keeps the same
/// floating button the Library had.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var showDiscovery = false

    /// Live gates for the suggestion entry, mirroring the #641 Add recipe entry.
    /// Reading this never calls the model or any backend; RecipeDiscoverySession
    /// re-checks every gate against live data before any generation starts.
    private var discoveryReadiness: RecipeDiscoveryReadiness {
        RecipeDiscoveryReadiness(privateMode: store.settings.onDeviceOnly,
            onDeviceBackend: store.backend is OnDeviceBackend,
            modelAvailable: OnDeviceBackend.isModelAvailable,
            modelUnavailableReason: OnDeviceBackend.availabilityNote,
            savedRecipes: store.recipes.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                glance
                whatShallWeCook
                trySomethingNew
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        // The tab bar's floating bottom accessory can overlap trailing scroll content;
        // match SettingsView and leave room for it.
        .contentMargins(.bottom, 96, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // iOS 26: the tab bar's bottom accessory carries "Add recipe" (C-TAB-01);
            // older iOS keep the floating button on the Today root itself.
            if !TabChrome.usesAccessory {
                Button { showAdd = true } label: { Label("Add recipe", systemImage: "plus").padding(.horizontal, 10) }
                    .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.vertical, 8).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Today")
        .onAppear { store.bottomAddContext = .recipe }
        .ateRootNavigationChrome(logoID: "todayLogo")
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddRecipeSheet { card in
                    store.add(card)
                    store.show("Saved to your library")
                    showAdd = false
                    store.path.append(.recipe(card.id))
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Store-wide quick-add (widgets, the iOS 26 accessory) and the share
        // extension's pending import have exactly one owner (#642): Today while the
        // home tab shows its root; once the collection is pushed, LibraryView's
        // global sheets own them exactly as before. No double presentation, one save.
        .sheet(item: Binding(get: { store.homeSheetOwner == .today ? store.quickAdd : nil }, set: { store.quickAdd = $0 })) { req in
            NavigationStack {
                AddRecipeSheet(initialMode: req.mode) { card in
                    store.add(card)
                    store.show("Saved to your library")
                    store.quickAdd = nil
                    store.path.append(.recipe(card.id))
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { store.homeSheetOwner == .today ? store.pendingImport : nil }, set: { store.pendingImport = $0 })) { item in
            NavigationStack {
                AddRecipeSheet(initial: item) { card in
                    store.add(card)
                    store.show("Saved to your library")
                    store.pendingImport = nil
                    store.path.append(.recipe(card.id))
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDiscovery) {
            NavigationStack { SuggestedNewRecipesView().environment(store) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TodayHome.greeting(hour: Calendar.current.component(.hour, from: Date())))
                .font(AteFont.display(28))
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.greeting")
    }

    private var glance: some View {
        HStack {
            Text("Your cooking, at a glance").font(AteFont.body(17, .semibold))
            Spacer()
            Button { store.openCollection() } label: { Text("Recipes") }
                .buttonStyle(.ate(.secondary, height: 36))
                .accessibilityIdentifier("today.recipes")
        }
    }

    private var whatShallWeCook: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What shall we cook?").font(AteFont.display(24))
            let picks = TodayHome.preview(store.recipes)
            if picks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No saved recipes yet").font(AteFont.body(17, .semibold))
                    // Exactly one "Add recipe" control exists on the Today root (the bottom
                    // accessory on iOS 26, the floating button above on older iOS), so XCTest
                    // queries for it stay unambiguous at the empty root.
                    Text("Tap Add recipe below and it will wait for you here.")
                        .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            } else {
                VStack(spacing: 12) {
                    ForEach(picks) { recipe in
                        Button { store.path.append(.recipe(recipe.id)) } label: { RecipeRowView(recipe: recipe) }
                            .buttonStyle(PressScale())
                            .accessibilityIdentifier("today.savedRecipe")
                    }
                }
                Button { store.openCollection() } label: {
                    HStack { Text("Browse saved recipes"); Image(systemName: "chevron.right") }
                }
                .buttonStyle(.ate(.secondary, height: 44, full: true))
                .accessibilityIdentifier("today.browseRecipes")
            }
        }
    }

    private var trySomethingNew: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try something new").font(AteFont.body(17, .semibold))
            Text("New recipe ideas from your saved tastes.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
            // The same #641 suggestions flow the Add recipe sheet opens: tapping only
            // presents it; generation, Review/Rerun and explicit Save live inside.
            Button { showDiscovery = true } label: {
                HStack { Text("Suggest a new recipe"); Image(systemName: "chevron.right") }
            }
            .buttonStyle(.ate(.secondary, height: 44, full: true))
            .accessibilityIdentifier("today.suggestNewRecipe")
            if let why = discoveryReadiness.explanation {
                Text(why).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("today.suggestNewRecipe.unavailable")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}
