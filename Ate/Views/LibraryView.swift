import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    /// The Library tab (drawer on older iOS) and the iOS 26 Search tab keep separate query slots,
    /// so a search on one surface never clobbers the other; each survives tab switches through SceneStorage.
    @SceneStorage("ate.library.query") private var libraryQuery = ""
    @SceneStorage("ate.search.query") private var searchQuery = ""
    enum SearchPlacement { case drawer, none, tabBar }
    /// iOS 26: the Library tab has no field (.none); the search tab hosts it in the tab bar (.tabBar).
    var searchPlacement: SearchPlacement = .drawer
    @State private var showAdd = false
    @State private var addMode: WidgetLinks.AddMode?
    @State private var addPrompt: String?
    @State private var confirmDelete: RecipeCard?
    @State private var quickLookRecipe: RecipeCard?
    @State private var recipeSheetDetent: PresentationDetent = .height(260)
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.horizontalSizeClass) private var hSize
    /// Landscape iPhone / iPad: card grid instead of the single-column list.
    private var useGrid: Bool { vSize == .compact || hSize == .regular }

    /// The query this surface searches with: the Search tab owns its dedicated slot.
    private var query: String {
        get { searchPlacement == .tabBar ? searchQuery : libraryQuery }
        nonmutating set { if searchPlacement == .tabBar { searchQuery = newValue } else { libraryQuery = newValue } }
    }
    private var queryBinding: Binding<String> { searchPlacement == .tabBar ? $searchQuery : $libraryQuery }

    /// iOS 26 Search tab with no query yet: a search-first start, not a second Library browser.
    private var isSearchStart: Bool {
        searchPlacement == .tabBar && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isSearching: Bool {
        searchPlacement != .none && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adopts a system search-intent query ("Search ate for tripe", AppStore.pendingSearch) in the
    /// instance that can show it. iOS 26: the Library tab has no search field, so it hands the query
    /// to the Search tab, which consumes it on change or on first appear; if the Search tab consumed
    /// first, it selects itself so the user lands on the results. Either handler ordering ends on the
    /// Search tab with the query applied; older iOS keeps the existing drawer behaviour.
    private func adoptPendingSearch() {
        guard let q = store.pendingSearch else { return }
        switch searchPlacement {
        case .none:
            store.select(.search)
        case .tabBar:
            query = q
            store.pendingSearch = nil
            if store.tab != .search { store.select(.search) }
        case .drawer:
            query = q
            store.pendingSearch = nil
        }
    }

    private func canReorder(_ filtered: [RecipeCard]) -> Bool {
        store.layout.canReorder(
            showingCount: filtered.count,
            recipeCount: store.recipes.count,
            hasSearch: searchPlacement != .none && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasFilter: store.filter.isActive
        )
    }

    var body: some View {
        let filtered = store.filter.apply(store.recipes, query: searchPlacement == .none ? "" : query)
        ZStack {
            Theme.background.ignoresSafeArea()
            if useGrid { grid(filtered) } else { list(filtered) }
        }
        // Attach the recipe quick-look sheet to the layout container itself, separate from
        // LibrarySheets' add/import presentations. This keeps the row/grid selection sheet
        // independently presented rather than competing with the add-flow sheet modifiers.
        .sheet(item: $quickLookRecipe, onDismiss: { recipeSheetDetent = .height(260) }) { recipe in
            ExpandableRecipeDetailSheet(recipe: recipe, detent: $recipeSheetDetent)
                .environment(store)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Same bottom system as recipe detail: sits directly above the stack's timer bar.
            // iOS 26: the tab bar's bottom accessory carries "Add recipe" instead (C-TAB-01).
            if !TabChrome.usesAccessory {
                Button { addMode = nil; addPrompt = nil; showAdd = true } label: { Label("Add recipe", systemImage: "plus").padding(.horizontal, 10) }
                    .buttonStyle(.ate(.primary, height: 56)).floatShadow().padding(.vertical, 8).frame(maxWidth: .infinity)
            }
        }
        // System search (glass on iOS 26). The query lives in SceneStorage so switching tabs or cancelling and
        // coming back restores it; the List keeps its own scroll position per tab stack.
        .modifier(LibrarySearch(query: queryBinding, placement: searchPlacement, prompt: "Search \(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s")"))
        .textInputAutocapitalization(.never)
        .navigationTitle(store.filter.collection?.title ?? L10n.libraryTitle)
        .onAppear { store.bottomAddContext = .recipe }
        .ateRootNavigationChrome(logoID: "libraryLogo")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { trailingMenu } }
        .modifier(LibrarySheets(confirmDelete: $confirmDelete, showAdd: $showAdd, initialMode: addMode, initialPrompt: addPrompt, pushesToSearchStack: searchPlacement == .tabBar, global: searchPlacement != .tabBar))
        .onChange(of: store.pendingSearch) { _, _ in adoptPendingSearch() }
        .onAppear { adoptPendingSearch() }
    }

    @ViewBuilder private func emptyState(_ filtered: [RecipeCard]) -> some View {
        if store.recipes.isEmpty {
            EmptyStateCard(symbol: "fork.knife", title: "Nothing saved yet",
                           message: "Save an existing recipe or create a new one from your idea.")
            VStack(alignment: .leading, spacing: 12) {
                firstRecipeAction("Import a recipe", detail: "Paste a link to a recipe you already found.", symbol: "link", mode: .link)
                firstRecipeAction("Photograph a recipe", detail: "Read a recipe screenshot, or estimate a dish from a food photo.", symbol: "camera", mode: .photo)
                firstRecipeAction("Describe a recipe", detail: "Generate a new recipe, for example: miso salmon for two.", symbol: "sparkles", mode: .prompt)
            }
        } else if filtered.isEmpty {
            EmptyStateCard(symbol: "fork.knife", title: "No matches",
                           message: store.filter.isActive ? "No recipes match these filters. Remove them to keep looking." : "Try another ingredient or tag.")
            if store.filter.isActive {
                Button("Remove all filters") { store.filter.clear() }
                    .buttonStyle(.ate(.secondary, height: 44)).accessibilityIdentifier("library.empty.clearFilters")
            }
            if searchPlacement != .none && !query.isEmpty {
                Button("Clear search") { query = "" }
                    .buttonStyle(.ate(.secondary, height: 44)).accessibilityIdentifier("library.empty.clearSearch")
                Button { addMode = .prompt; addPrompt = query.trimmingCharacters(in: .whitespacesAndNewlines); showAdd = true } label: {
                    Label("Describe it as a new recipe", systemImage: "sparkles")
                }
                .buttonStyle(.ate(.secondary, height: 44)).accessibilityIdentifier("library.empty.describe")
            }
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

    /// Keep explicit recently-cooked collection ordering through the layout's sorting pass.
    private var collectionLayout: LibraryLayout {
        var layout = store.layout
        if store.filter.collection == .recentlyCooked { layout.sort = .recentlyCooked }
        return layout
    }

    private func grid(_ filtered: [RecipeCard]) -> some View {
        let sections = collectionLayout.sections(filtered)
        let ordered = sections.flatMap(\.recipes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(resultCount: filtered.count)
                if isSearchStart && !store.recipes.isEmpty { searchStartPrompt }
                TodayJournalHubCard()
                TodayHealthCard()
                recipeRediscovery
                FilterChips(resultCount: filtered.count)
                emptyState(filtered)
                if !isSearchStart {
                    if isSearching && !filtered.isEmpty { searchResultsHeader(count: filtered.count) }
                    ForEach(sections) { sec in
                        if !sec.title.isEmpty { sectionHeader(sec.title, count: sec.recipes.count) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: vSize == .compact ? 220 : 250, maximum: 420), spacing: 14)], spacing: 14) {
                            ForEach(sec.recipes) { r in
                                gridCell(r, ordered: ordered, canReorder: canReorder(filtered))
                            }
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

    @ViewBuilder private func gridCell(_ r: RecipeCard, ordered: [RecipeCard], canReorder: Bool) -> some View {
        let cell = ZStack(alignment: .topTrailing) {
            Button { quickLookRecipe = r } label: { RecipeGridCard(recipe: r) }
                .buttonStyle(PressScale())
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .contextMenu { menu(r) } preview: { RecipeGridCard(recipe: r).frame(width: 300) }
                .accessibilityIdentifier("gridCard")
            // Keep the favourite action directly reachable in grid layout, matching list swipe and context-menu actions.
            Button { store.toggleFavourite(r.id) } label: {
                Image(systemName: r.favorite ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(r.favorite ? Theme.primaryForeground : Theme.foreground)
                    .frame(width: 40, height: 40)
                    .background(r.favorite ? Theme.primary : Theme.card.opacity(0.96), in: Circle())
                    .overlay(Circle().stroke(Theme.input, lineWidth: r.favorite ? 0 : 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(r.favorite ? "Remove \(r.title) from Favourites" : "Add \(r.title) to Favourites")
            .accessibilityIdentifier("gridFavourite.\(r.id)")
        }
        if canReorder {
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
        let sections = collectionLayout.sections(filtered)
        let ordered = sections.flatMap(\.recipes)
        let mover: ((IndexSet, Int) -> Void)? = canReorder(filtered)
            ? { from, to in withAnimation(Motion.anim()) { store.move(fromOffsets: from, toOffset: to, in: ordered) } } : nil
        return List {
            Group {
                header(resultCount: filtered.count)
                if isSearchStart && !store.recipes.isEmpty { searchStartPrompt }
                TodayJournalHubCard()
                recipeRediscovery
                FilterChips(resultCount: filtered.count)
                emptyState(filtered)
                if !isSearchStart {
                    if isSearching && !filtered.isEmpty { searchResultsHeader(count: filtered.count) }
                    ForEach(sections) { sec in
                        if !sec.title.isEmpty { sectionHeader(sec.title, count: sec.recipes.count) }
                        ForEach(sec.recipes) { r in row(r) }
                            .onMove(perform: mover)
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

    private func row(_ r: RecipeCard) -> some View {
        // Keep list and grid selection consistent: both open the expandable recipe sheet.
        Button { quickLookRecipe = r } label: { RecipeRowView(recipe: r) }
            .buttonStyle(PressScale())
            .accessibilityIdentifier("listCard")
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { Task { await store.deleteWithUndo(r.id) } } label: { Label("Delete", systemImage: "trash") }
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

    /// The landing page owns discovery: collections, ingredient filters and health/journal entry points.
    private var libraryMenu: some View {
        @Bindable var store = store
        return Menu {
            Section("Collections") {
                ForEach([RecipeCollection.quick, .favourites, .recentlyAdded, .recentlyCooked, .cookedMeals], id: \.self) { c in
                    Button { selectCollection(c) } label: {
                        Label(c.title, systemImage: c.symbol)
                    }
                    .accessibilityIdentifier("library.collection.\(c.title)")
                }
            }
            let tags = IngredientTags.collections(in: store.recipes)
            if !tags.isEmpty {
                Section("By ingredient") {
                    ForEach(tags, id: \.self) { tag in
                        Button { store.filter.tags = [tag] } label: {
                            Label(tag, systemImage: "leaf")
                        }
                        .accessibilityIdentifier("library.ingredient.\(tag)")
                    }
                }
            }
            Section("Arrange") {
                Menu {
                    Picker("Group by", selection: $store.layout.group) {
                        ForEach(LibraryLayout.GroupBy.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: { Label("Group by", systemImage: "rectangle.3.group") }
                .accessibilityIdentifier("groupByMenu")
                Menu {
                    Picker("Sort", selection: $store.layout.sort) {
                        ForEach(LibraryLayout.SortBy.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("sortMenu")
            }
        } label: {
            Label("Browse and arrange", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("libraryBrowseMenu")
    }

    /// Placement-dependent trailing menu: the Search tab offers results options; the Library
    /// surface keeps its browse & arrange menu. Journal and Insights have their own entry points
    /// (the Journal tab root and its named route), so the Library menu carries no Explore links.
    @ViewBuilder private var trailingMenu: some View {
        if searchPlacement == .tabBar { resultsMenu } else { libraryMenu }
    }

    /// The Search tab's results options: the existing recipe filters, the existing six sort
    /// choices, and Reset Filters. Clear Search stays in the search field and the no-results
    /// empty state, separate from Reset Filters, so resetting filters never silently erases the
    /// query. No Insights/Journal jump and no Add Recipe item in this menu; the global root
    /// Add accessory is unchanged and is not part of this increment.
    private var resultsMenu: some View {
        @Bindable var store = store
        return Menu {
            Section("Filters") {
                Button { store.filter.favouritesOnly.toggle() } label: {
                    Label("Favourites", systemImage: store.filter.favouritesOnly ? "checkmark" : "star")
                }
                .accessibilityIdentifier("search.filter.favourites")
                .accessibilityAddTraits(store.filter.favouritesOnly ? .isSelected : [])
                .accessibilityHint(store.filter.favouritesOnly ? "Removes this filter" : "Filters your library")
                Menu {
                    ForEach(RecipeFilter.timeOptions, id: \.self) { m in
                        Button { store.filter.maxMinutes = store.filter.maxMinutes == m ? nil : m } label: {
                            Label("\(m) min or less", systemImage: store.filter.maxMinutes == m ? "checkmark" : "clock")
                        }
                        .accessibilityAddTraits(store.filter.maxMinutes == m ? .isSelected : [])
                        .accessibilityHint(store.filter.maxMinutes == m ? "Removes this filter" : "Filters your library")
                    }
                } label: { Label("Cook time", systemImage: "clock") }
                Menu {
                    ForEach(RecipeOrigin.allCases, id: \.self) { o in
                        Button {
                            if store.filter.origins.contains(o) { store.filter.origins.remove(o) } else { store.filter.origins.insert(o) }
                        } label: {
                            Label(FilterChips.label(o), systemImage: store.filter.origins.contains(o) ? "checkmark" : FilterChips.symbol(o))
                        }
                        .accessibilityAddTraits(store.filter.origins.contains(o) ? .isSelected : [])
                        .accessibilityHint(store.filter.origins.contains(o) ? "Removes this filter" : "Filters your library")
                    }
                } label: { Label("From", systemImage: "tray.full") }
                Menu {
                    ForEach(RecipeFilter.Servings.allCases, id: \.self) { sv in
                        Button {
                            if store.filter.servings.contains(sv) { store.filter.servings.remove(sv) } else { store.filter.servings.insert(sv) }
                        } label: {
                            Label("\(sv.rawValue) servings", systemImage: store.filter.servings.contains(sv) ? "checkmark" : "person.2")
                        }
                        .accessibilityAddTraits(store.filter.servings.contains(sv) ? .isSelected : [])
                        .accessibilityHint(store.filter.servings.contains(sv) ? "Removes this filter" : "Filters your library")
                    }
                } label: { Label("Servings", systemImage: "person.2") }
                let tags = IngredientTags.available(in: store.recipes)
                if !tags.isEmpty {
                    Menu {
                        ForEach(tags, id: \.self) { t in
                            Button {
                                if store.filter.tags.contains(t) { store.filter.tags.remove(t) } else { store.filter.tags.insert(t) }
                            } label: {
                                Label(t, systemImage: store.filter.tags.contains(t) ? "checkmark" : "leaf")
                            }
                            .accessibilityAddTraits(store.filter.tags.contains(t) ? .isSelected : [])
                            .accessibilityHint(store.filter.tags.contains(t) ? "Removes this filter" : "Filters your library")
                        }
                    } label: { Label("Ingredient", systemImage: "leaf") }
                }
            }
            Section("Sort") {
                Picker(selection: $store.layout.sort) {
                    ForEach(LibraryLayout.SortBy.allCases) { Text($0.rawValue).tag($0) }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("sortMenu")
            }
            Section {
                Button { store.filter.clear() } label: { Label("Reset Filters", systemImage: "arrow.uturn.backward") }
                    .disabled(!store.filter.isActive)
                    .accessibilityIdentifier("search.resetFilters")
            }
        } label: {
            Label("Results options", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("searchResultsMenu")
    }

    private func selectCollection(_ c: RecipeCollection) {
        store.filter.clear()
        store.filter.collection = c
    }

    /// Prominent count and filter state; the logo lives in the toolbar and the title is the native large title.
    private func header(resultCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.recipes.count) saved recipe\(store.recipes.count == 1 ? "" : "s")")
                .font(AteFont.display(22)).accessibilityIdentifier("libraryCount")
            if store.filter.isActive {
                Text("\(resultCount) showing · \(store.filter.activeCount) active filter\(store.filter.activeCount == 1 ? "" : "s")")
                    .font(AteFont.body(14, .semibold)).accessibilityIdentifier("library.filterSummary")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstRecipeAction(_ title: String, detail: String, symbol: String, mode: WidgetLinks.AddMode) -> some View {
        Button { addMode = mode; addPrompt = nil; showAdd = true } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AteFont.body(16, .semibold))
                    Text(detail).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 14)
        }.buttonStyle(.plain).accessibilityIdentifier("library.firstRecipe.\(mode.rawValue)")
    }

    /// The Search tab's start: an explicit search prompt, with rediscovery below it.
    private var searchStartPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search your recipes").font(AteFont.display(24))
                .accessibilityIdentifier("library.searchStart")
            Text("Find a saved recipe by name, ingredient or tag. Filters and collections still apply.")
                .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Labels the result set as recipe results, distinct from any future Journal or other matches.
    private func searchResultsHeader(count: Int) -> some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text("\(count) recipe\(count == 1 ? "" : "s") for “\(q)”")
            .font(AteFont.body(16, .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("library.searchResults")
    }

    /// Recipe-only suggestions, never inserted into an active search or filtered collection.
    @ViewBuilder private var recipeRediscovery: some View {
        if !store.filter.isActive && (searchPlacement == .none || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            let recent = RecipeFilter(collection: .recentlyCooked).apply(store.recipes)
            let favourites = LibraryLayout(sort: .recentlyCooked).sorted(store.recipes.filter { $0.favorite })
            if !recent.isEmpty { rediscoverySection("Recently cooked", recipes: recent, collection: .recentlyCooked) }
            if !favourites.isEmpty { rediscoverySection("Favourites", recipes: favourites, collection: .favourites) }
        }
    }

    private func rediscoverySection(_ title: String, recipes: [RecipeCard], collection: RecipeCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(AteFont.body(16, .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all (\(recipes.count))") { selectCollection(collection) }
                    .accessibilityIdentifier("library.rediscovery.\(title)")
            }
            ForEach(Array(recipes.prefix(2))) { recipe in
                Button { quickLookRecipe = recipe } label: { RecipeRowView(recipe: recipe) }.buttonStyle(.plain)
            }
        }
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
        let visible = store.filter.apply(store.recipes, query: searchPlacement == .none ? "" : query)
        if canReorder(visible) {
            let ordered = store.layout.sorted(visible)
            if let i = ordered.firstIndex(where: { $0.id == r.id }) {
                if i > 0 { Button { store.move(r.id, before: ordered[i - 1].id, in: ordered) } label: { Label("Move up", systemImage: "arrow.up") } }
                if i < ordered.count - 1 {
                    Button { store.move(fromOffsets: IndexSet(integer: i), toOffset: i + 2, in: ordered) } label: { Label("Move down", systemImage: "arrow.down") }
                }
            }
        }
        Divider()
        Button(role: .destructive) { Task { await store.deleteWithUndo(r.id) } } label: { Label("Delete", systemImage: "trash") }
    }
}

/// Delete confirmation + add sheets (shared by list and grid layouts).
private struct LibrarySheets: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var confirmDelete: RecipeCard?
    @Binding var showAdd: Bool
    /// Only one LibraryView (the Library tab) presents the store-wide quick-add / import sheets.
    var initialMode: WidgetLinks.AddMode?
    /// Starting text for the prompt mode (a search with no results can become the new recipe's idea).
    var initialPrompt: String?
    /// The Search tab keeps its own stack: saving there pushes detail on searchPath, not an
    /// invisible Library-stack detail while the user stays on Search.
    var pushesToSearchStack: Bool = false
    var global: Bool = true
    private func openDetail(for card: RecipeCard) {
        if pushesToSearchStack { store.searchPath.append(.recipe(card.id)) } else { store.path.append(.recipe(card.id)) }
    }
    func body(content: Content) -> some View {
        content
        .confirmationDialog("Delete “\(confirmDelete?.title ?? "")”?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                if let r = confirmDelete { Task { if await store.delete(r.id) { store.show("Recipe deleted"); Haptics.warning() } } }
                confirmDelete = nil
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddRecipeSheet(initialMode: initialMode, initialPrompt: initialPrompt) { card in
                    store.add(card)
                    store.show("Saved to your library")
                    showAdd = false
                    openDetail(for: card)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { global ? store.quickAdd : nil }, set: { store.quickAdd = $0 })) { req in
            NavigationStack {
                AddRecipeSheet(initialMode: req.mode) { card in
                    store.add(card)
                    store.show("Saved to your library")
                    store.quickAdd = nil
                    openDetail(for: card)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { global ? store.pendingImport : nil }, set: { store.pendingImport = $0 })) { item in
            NavigationStack {
                AddRecipeSheet(initial: item) { card in
                    store.add(card)
                    store.show("Saved to your library")
                    store.pendingImport = nil
                    openDetail(for: card)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}


/// Search placement + iOS 26 search/scroll-edge behaviour (C-TAB-03/04/05).
struct LibrarySearch: ViewModifier {
    @Binding var query: String
    let placement: LibraryView.SearchPlacement
    let prompt: String
    func body(content: Content) -> some View {
        switch placement {
        case .none:
            styled(content)
        case .drawer:
            styled(content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt))
        case .tabBar:
            // The search-role tab's automatic placement rendered no search field at all on the
            // iOS 27 simulator (issue-73 qualification lane pixel evidence), so pin the field to an
            // always-visible drawer like the Library tab: search-first needs a field on arrival.
            styled(content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt))
        }
    }
    @ViewBuilder private func styled<V: View>(_ v: V) -> some View {
        if #available(iOS 26, *) {
            v.searchPresentationToolbarBehavior(.avoidHidingContent)   // "Your Kitchen" stays visible while searching
             .scrollEdgeEffectStyle(.soft, for: .top)
        } else { v }
    }
}


/// Always-visible Library shortcut to the combined Insights hub.
struct TodayJournalHubCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            store.openInsightsHub()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Insights").font(AteFont.body(15, .semibold))
                    Text("Cooking history, Health insights, and your entries")
                        .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.todayJournalHub")
    }
}
