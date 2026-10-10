import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var showAdd = false
    @State private var confirmDelete: RecipeCard?
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.horizontalSizeClass) private var hSize
    /// Landscape iPhone / iPad: card grid instead of the single-column list.
    private var useGrid: Bool { vSize == .compact || hSize == .regular }

    var body: some View {
        let filtered = store.filter.apply(store.recipes, query: query)
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            if useGrid { grid(filtered) } else { list(filtered) }
            Button { showAdd = true } label: { Label("Add recipe", systemImage: "plus").padding(.horizontal, 10) }
                .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.bottom, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .modifier(LibrarySheets(confirmDelete: $confirmDelete, showAdd: $showAdd))
    }

    @ViewBuilder private func emptyState(_ filtered: [RecipeCard]) -> some View {
        if store.recipes.isEmpty {
            EmptyStateCard(symbol: "fork.knife", title: "Nothing saved yet",
                           message: "Paste a link or a screenshot and get a clean recipe card in seconds.")
        } else if filtered.isEmpty {
            EmptyStateCard(symbol: "fork.knife", title: "No matches",
                           message: store.filter.isActive ? "No recipes match these filters." : "Try another ingredient or tag.")
        }
    }

    private func refresh() async {
        if store.session != nil { await store.syncNow() } else { store.show("Sign in from Settings to sync across devices") }
    }

    private func grid(_ filtered: [RecipeCard]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                FilterChips(resultCount: filtered.count)
                emptyState(filtered)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 14)], spacing: 14) {
                    ForEach(filtered) { r in
                        Button { store.path.append(.recipe(r.id)) } label: { RecipeGridCard(recipe: r) }
                            .buttonStyle(PressScale())
                            .contextMenu { menu(r) }
                            .accessibilityIdentifier("gridCard")
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .foregroundStyle(Theme.foreground)
        }
        .refreshable { await refresh() }
        .accessibilityIdentifier("libraryGrid")
    }

    private func list(_ filtered: [RecipeCard]) -> some View {
            List {
                Group {
                    header
                    FilterChips(resultCount: filtered.count)
                    emptyState(filtered)
                    if !filtered.isEmpty {
                        ForEach(filtered) { r in
                            Button { store.path.append(.recipe(r.id)) } label: { RecipeRowView(recipe: r) }
                                .buttonStyle(PressScale())
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { confirmDelete = r } label: { Label("Delete", systemImage: "trash") }
                                        .tint(Theme.destructive)
                                }
                                .swipeActions(edge: .leading) {
                                    Button { store.cookTarget = CookTarget(id: r.id) } label: { Label("Cook", systemImage: "flame") }
                                        .tint(Theme.primary)
                                }
                                .contextMenu { menu(r) } preview: { RecipeRowView(recipe: r).frame(width: 340) }
                        }
                    }
                    Color.clear.frame(height: 96)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .foregroundStyle(Theme.foreground)
                .pageWidth()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image("AteLogo").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                        Text("ate").font(AteFont.body(14, .bold)).tracking(2.8).foregroundStyle(Theme.primary)
                    }
                    Text(store.filter.collection?.title ?? L10n.libraryTitle).font(AteFont.display(36)).accessibilityAddTraits(.isHeader)
                    Text("\(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s") saved on this device.")
                        .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground).accessibilityHidden(true)
                TextField("Search chicken, pasta, vegan…", text: $query).font(AteFont.body(15))
                    .textInputAutocapitalization(.never).accessibilityLabel("Search recipes")
            }
            .padding(.horizontal, 18).frame(minHeight: 48)
            .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.input))
        }
        .padding(.top, 24)
    }

    @ViewBuilder private func menu(_ r: RecipeCard) -> some View {
        Button { store.path.append(.recipe(r.id)) } label: { Label("Open", systemImage: "book") }
        Button { store.cookTarget = CookTarget(id: r.id) } label: { Label("Start cooking", systemImage: "flame") }
        Button { store.toggleFavourite(r.id) } label: {
            Label(r.favorite ? "Remove from Favourites" : "Add to Favourites", systemImage: r.favorite ? "star.slash" : "star")
        }
        Button { store.addToShopping(r, factor: 1); store.show("Added to your shopping list") } label: {
            Label("Add to shopping list", systemImage: "basket")
        }
        Button { UIPasteboard.general.string = RecipeLogic.text(for: r, units: store.settings.units); store.show("Recipe copied") } label: {
            Label("Copy as text", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) { confirmDelete = r } label: { Label("Delete", systemImage: "trash") }
    }
}

/// Delete confirmation + add sheets (shared by list and grid layouts).
private struct LibrarySheets: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var confirmDelete: RecipeCard?
    @Binding var showAdd: Bool
    func body(content: Content) -> some View {
        content
        .confirmationDialog("Delete “\(confirmDelete?.title ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                if let r = confirmDelete { store.delete(r.id); store.show("Recipe deleted"); Haptics.warning() }
                confirmDelete = nil
            }
        }
        .sheet(isPresented: $showAdd) {
            AddRecipeSheet { card in
                store.add(card)
                store.show("Saved to your library")
                showAdd = false
                store.path.append(.recipe(card.id))
            }
            .environment(store)
            .presentationDetents([.large])
        }
        .sheet(item: Binding(get: { store.pendingImport }, set: { store.pendingImport = $0 })) { item in
            AddRecipeSheet(initial: item) { card in
                store.add(card)
                store.show("Saved to your library")
                store.pendingImport = nil
                store.path.append(.recipe(card.id))
            }
            .environment(store)
            .presentationDetents([.large])
        }
    }
}
