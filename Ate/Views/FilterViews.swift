import SwiftUI

/// Recipe card with a large thumbnail for the landscape / iPad grid.
struct RecipeGridCard: View {
    let recipe: RecipeCard
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RecipeThumb(recipe: recipe, width: nil, height: 140, emojiSize: 48)
                if recipe.favorite {
                    Image(systemName: "star.fill").font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .padding(7).background(Theme.primary, in: Circle()).padding(8).accessibilityLabel("Favourite")
                }
            }
            Text(recipe.title).font(AteFont.body(17, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
            HStack(spacing: 10) {
                if let m = recipe.timeMinutes, m > 0 { Label("\(m) min", systemImage: "clock") }
                Label("\(recipe.servings)", systemImage: "person.2")
                ForEach(Array(IngredientTags.tags(for: recipe).sorted().prefix(2)), id: \.self) { TagBadge(text: $0) }
            }
            .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.foreground)
        .cardSurface(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontally scrolling multi-select filter chips under the search bar.
struct FilterChips: View {
    @Environment(AppStore.self) private var store
    let resultCount: Int
    var queryIsActive: Bool = false

    var body: some View {
        let f = store.filter
        VStack(alignment: .leading, spacing: 6) {
            // One non-wrapping row; the selected chip scrolls into view.
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if f.isActive {
                        chip("Clear (\(f.activeCount))", symbol: "xmark", on: true, id: "chip.clear") { store.filter.clear() }
                    }
                    if let c = f.collection {
                        chip(c.title, symbol: c.symbol, on: true, id: "chip.collection") { store.filter.collection = nil }
                    }
                    chip("Quick ≤30 min", symbol: "bolt", on: f.maxMinutes == 30, id: "chip.time30") {
                        store.filter.maxMinutes = f.maxMinutes == 30 ? nil : 30
                    }
                    chip("Favourites", symbol: "star", on: f.favouritesOnly, id: "chip.favourites") { store.filter.favouritesOnly.toggle() }
                    ForEach(RecipeFilter.timeOptions.filter { $0 != 30 }, id: \.self) { m in
                        chip("≤\(m) min", symbol: "clock", on: f.maxMinutes == m, id: "chip.time\(m)") {
                            store.filter.maxMinutes = f.maxMinutes == m ? nil : m
                        }
                    }
                    ForEach(RecipeOrigin.allCases, id: \.self) { o in
                        chip(Self.label(o), symbol: Self.symbol(o), on: f.origins.contains(o), id: "chip.origin.\(o.rawValue)") {
                            if store.filter.origins.contains(o) { store.filter.origins.remove(o) } else { store.filter.origins.insert(o) }
                        }
                    }
                    ForEach(RecipeFilter.Servings.allCases, id: \.self) { sv in
                        chip("\(sv.rawValue) servings", symbol: "person.2", on: f.servings.contains(sv), id: "chip.servings.\(sv.rawValue)") {
                            if store.filter.servings.contains(sv) { store.filter.servings.remove(sv) } else { store.filter.servings.insert(sv) }
                        }
                    }
                    ForEach(IngredientTags.available(in: store.recipes), id: \.self) { t in
                        chip(t, symbol: nil, on: f.tags.contains(t), id: "chip.tag.\(t)") {
                            if store.filter.tags.contains(t) { store.filter.tags.remove(t) } else { store.filter.tags.insert(t) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: store.filter) { _, _ in
                withAnimation(Motion.anim()) { proxy.scrollTo(Self.firstSelectedID(store.filter), anchor: .center) }
            }
            }
            .accessibilityIdentifier("filterChips")
            if f.isActive || queryIsActive {
                Text("\(resultCount) of \(store.recipes.count) recipe\(store.recipes.count == 1 ? "" : "s")")
                    .font(AteFont.body(12, .medium)).foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("filterResultCount")
            }
        }
    }

    static func firstSelectedID(_ f: RecipeFilter) -> String {
        if f.collection != nil { return "chip.collection" }
        if f.favouritesOnly { return "chip.favourites" }
        if let m = f.maxMinutes { return "chip.time\(m)" }
        if let o = f.origins.first { return "chip.origin.\(o.rawValue)" }
        if let sv = f.servings.first { return "chip.servings.\(sv.rawValue)" }
        if let t = f.tags.sorted().first { return "chip.tag.\(t)" }
        return "chip.time30"
    }

    static func label(_ o: RecipeOrigin) -> String {
        switch o { case .link: return "From a link"; case .photo: return "From a photo"; case .prompt: return "From a prompt"; case .shared: return "Shared with me" }
    }

    static func symbol(_ o: RecipeOrigin) -> String {
        switch o { case .link: return "link"; case .photo: return "camera"; case .prompt: return "pencil.line"; case .shared: return "person.2" }
    }

    private func chip(_ title: String, symbol: String?, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.toggle() } label: {
            HStack(spacing: 5) {
                // Selected state isn't colour-only: a checkmark replaces the icon.
                if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true) }
                else if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)).accessibilityHidden(true) }
                Text(title).font(AteFont.body(13, .semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(on ? Theme.primary : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(on ? Color.clear : Theme.input))
            .foregroundStyle(on ? Theme.primaryForeground : Theme.foreground)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .id(id)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Removes this filter" : "Filters your library")
    }
}
