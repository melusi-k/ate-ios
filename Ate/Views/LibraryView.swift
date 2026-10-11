import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @SceneStorage("ate.library.query") private var query = ""
    @State private var showAdd = false
    @State private var confirmDelete: RecipeCard?
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.horizontalSizeClass) private var hSize
    /// Landscape iPhone / iPad: card grid instead of the single-column list.
    private var useGrid: Bool { vSize == .compact || hSize == .regular }

    var body: some View {
        let filtered = store.filter.apply(store.recipes, query: query)
        ZStack {
            Theme.background.ignoresSafeArea()
            if useGrid { grid(filtered) } else { list(filtered) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Same bottom system as recipe detail: sits directly above the stack's timer bar.
            Button { showAdd = true } label: { Label("Add recipe", systemImage: "plus").padding(.horizontal, 10) }
                .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.vertical, 8).frame(maxWidth: .infinity)
        }
        // System search (glass on iOS 26). The query lives in SceneStorage so switching tabs or cancelling and
        // coming back restores it; the List keeps its own scroll position per tab stack.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s")")
        .textInputAutocapitalization(.never)
        .navigationTitle(store.filter.collection?.title ?? L10n.libraryTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("AteLogo").resizable().scaledToFit().frame(width: 28, height: 28)
                    .accessibilityLabel("ate").accessibilityIdentifier("libraryLogo")
            }
            ToolbarItem(placement: .topBarTrailing) { layoutMenu }
        }
        .modifier(LibrarySheets(confirmDelete: $confirmDelete, showAdd: $showAdd))
        .onChange(of: store.pendingSearch) { _, q in if let q { query = q; store.pendingSearch = nil } }
        .onAppear { if let q = store.pendingSearch { query = q; store.pendingSearch = nil } }
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

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).overline().accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(count)").font(AteFont.body(12, .medium)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("section." + title)
    }

    private func grid(_ filtered: [RecipeCard]) -> some View {
        let sections = store.layout.sections(filtered)
        let ordered = sections.flatMap(\.recipes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                TodayHealthCard()
                FilterChips(resultCount: filtered.count)
                emptyState(filtered)
                ForEach(sections) { sec in
                    if !sec.title.isEmpty { sectionHeader(sec.title, count: sec.recipes.count) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: vSize == .compact ? 220 : 250, maximum: 420), spacing: 14)], spacing: 14) {
                        ForEach(sec.recipes) { r in
                            gridCell(r, ordered: ordered)
                        }
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

    @ViewBuilder private func gridCell(_ r: RecipeCard, ordered: [RecipeCard]) -> some View {
        let cell = Button { store.path.append(.recipe(r.id)) } label: { RecipeGridCard(recipe: r) }
            .buttonStyle(PressScale())
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contextMenu { menu(r) } preview: { RecipeGridCard(recipe: r).frame(width: 300) }
            .accessibilityIdentifier("gridCard")
        if store.layout.canReorder {
            cell
                .draggable(r.id) { RecipeGridCard(recipe: r).frame(width: 260).opacity(0.9) }
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, id != r.id else { return false }
                    withAnimation(Motion.anim(.snappy)) { store.move(id, before: r.id, in: ordered) }
                    return true
                }
        } else {
            cell
        }
    }

    private func list(_ filtered: [RecipeCard]) -> some View {
        let sections = store.layout.sections(filtered)
        let ordered = sections.flatMap(\.recipes)
        let mover: ((IndexSet, Int) -> Void)? = store.layout.canReorder
            ? { from, to in withAnimation(Motion.anim()) { store.move(fromOffsets: from, toOffset: to, in: ordered) } } : nil
        return List {
            Group {
                header
                FilterChips(resultCount: filtered.count)
                emptyState(filtered)
                ForEach(sections) { sec in
                    if !sec.title.isEmpty { sectionHeader(sec.title, count: sec.recipes.count) }
                    ForEach(sec.recipes) { r in row(r) }
                        .onMove(perform: mover)
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

    private func row(_ r: RecipeCard) -> some View {
        Button { store.path.append(.recipe(r.id)) } label: { RecipeRowView(recipe: r) }
            .buttonStyle(PressScale())
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { store.deleteWithUndo(r.id) } label: { Label("Delete", systemImage: "trash") }
                    .tint(Theme.destructive)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button { store.toggleFavourite(r.id) } label: {
                    Label(r.favorite ? "Unfavourite" : "Favourite", systemImage: r.favorite ? "star.slash" : "star.fill")
                }.tint(Theme.accent)
                Button { store.addToShopping(r, factor: 1); store.show("Added to your shopping list") } label: {
                    Label("Add to list", systemImage: "basket")
                }.tint(Theme.primary)
            }
            .contextMenu { menu(r) } preview: { RecipeRowView(recipe: r).frame(width: 340) }
    }

    /// One icon-only "Group & sort" toolbar menu (the two text pills truncated).
    private var layoutMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker(selection: $store.layout.group) {
                ForEach(LibraryLayout.GroupBy.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            } label: { Label("Group by", systemImage: "rectangle.3.group") }
                .pickerStyle(.menu).accessibilityIdentifier("groupByMenu")
            Picker(selection: $store.layout.sort) {
                ForEach(LibraryLayout.SortBy.allCases) { Text($0.rawValue).tag($0) }
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .pickerStyle(.menu).accessibilityIdentifier("sortMenu")
        } label: { Label("Group & sort", systemImage: "line.3.horizontal.decrease.circle") }
            .accessibilityIdentifier("groupSortMenu")
    }

    /// Quiet count under the search bar; the logo lives in the toolbar and the title is the native large title.
    private var header: some View {
        Text("\(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s") saved on this device.")
            .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("libraryCount")
    }

    @ViewBuilder private func menu(_ r: RecipeCard) -> some View {
        Button { store.cookTarget = CookTarget(id: r.id) } label: { Label("Cook", systemImage: "flame") }
        ShareLink(item: RecipeLogic.text(for: r, units: store.settings.units), subject: Text(r.title)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button { store.toggleFavourite(r.id) } label: {
            Label(r.favorite ? "Remove from Favourites" : "Favourite", systemImage: r.favorite ? "star.slash" : "star")
        }
        Button { store.addToShopping(r, factor: 1); store.show("Added to your shopping list") } label: {
            Label("Add to shopping list", systemImage: "basket")
        }
        if store.layout.canReorder {
            let ordered = store.layout.sorted(store.filter.apply(store.recipes, query: query))
            if let i = ordered.firstIndex(where: { $0.id == r.id }) {
                if i > 0 { Button { store.move(r.id, before: ordered[i - 1].id, in: ordered) } label: { Label("Move up", systemImage: "arrow.up") } }
                if i < ordered.count - 1 {
                    Button { store.move(fromOffsets: IndexSet(integer: i), toOffset: i + 2, in: ordered) } label: { Label("Move down", systemImage: "arrow.down") }
                }
            }
        }
        Divider()
        Button(role: .destructive) { store.deleteWithUndo(r.id) } label: { Label("Delete", systemImage: "trash") }
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
        .sheet(item: Binding(get: { store.quickAdd }, set: { store.quickAdd = $0 })) { req in
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
        .sheet(item: Binding(get: { store.pendingImport }, set: { store.pendingImport = $0 })) { item in
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
    }
}
