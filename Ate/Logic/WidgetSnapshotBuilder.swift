import Foundation

/// Builds the App Group snapshot the widgets read. Pure, so the rules are unit-tested.
enum WidgetSnapshotBuilder {
    static func build(recipes: [RecipeCard], shopping: [ShoppingItem], health: HealthState?, now: Date = Date(),
                      calendar: Calendar = .current) -> WidgetSnapshot {
        var s = WidgetSnapshot(updatedAt: now)
        s.recipeCount = recipes.count
        s.favourites = favourites(recipes).prefix(WidgetSnapshot.maxFavourites).map(lite)
        s.shopping = shopping.filter { !$0.done }.prefix(WidgetSnapshot.maxShopping).map { .init(id: $0.id, name: label($0), done: false) }
        s.pick = pick(recipes: recipes, health: health, now: now, calendar: calendar)
        s.cookingStreak = CookingHistory.shared.streak(asOf: now)
        s.cookedToday = CookingHistory.shared.cooked(on: now)
        return s
    }

    /// Favourites first (most recently cooked/added), topped up with recent recipes when there are fewer than 3.
    static func favourites(_ recipes: [RecipeCard]) -> [RecipeCard] {
        let favs = recipes.filter(\.favorite).sorted { ($0.lastCookedAt ?? $0.createdAt) > ($1.lastCookedAt ?? $1.createdAt) }
        guard favs.count < 3 else { return favs }
        let recent = recipes.filter { !$0.favorite }.sorted { $0.createdAt > $1.createdAt }
        return favs + recent.prefix(WidgetSnapshot.maxFavourites - favs.count)
    }

    static func lite(_ r: RecipeCard) -> WidgetSnapshot.Recipe {
        .init(id: r.id, title: r.title, minutes: r.timeMinutes, favorite: r.favorite, cover: coverFile(r), stepCount: r.steps.count)
    }
    static func coverFile(_ r: RecipeCard) -> String? {
        guard let f = r.coverImage, f != CoverStore.removed else { return nil }
        return f
    }

    static func label(_ i: ShoppingItem) -> String {
        guard i.quantity > 0 else { return i.name }
        let q = i.quantity.rounded() == i.quantity ? String(Int(i.quantity)) : String(format: "%.1f", i.quantity)
        return "\(i.name) (\(q)\(i.unit.isEmpty ? "" : " " + i.unit))"
    }

    /// Tonight's pick: best Health match when Health is connected; otherwise a daily rotation through favourites
    /// (or the whole library). Recipes cooked in the last 2 days are skipped when there's an alternative.
    static func pick(recipes: [RecipeCard], health: HealthState?, now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot.Pick? {
        guard !recipes.isEmpty else { return nil }
        let recentCutoff = (now.timeIntervalSince1970 - 2 * 86400) * 1000
        let fresh = recipes.filter { ($0.lastCookedAt ?? 0) < recentCutoff }
        let pool = fresh.isEmpty ? recipes : fresh
        func make(_ r: RecipeCard, _ why: String) -> WidgetSnapshot.Pick {
            .init(recipeID: r.id, title: r.title, why: why, minutes: r.timeMinutes, cover: coverFile(r),
                  healthTitle: health?.title, healthSymbol: health?.symbol)
        }
        if let h = health, let best = RecipeHealthMatcher.suggestions(for: h, recipes: pool, limit: 1).first,
           let r = pool.first(where: { $0.id == best.recipeID }) {
            return make(r, best.why)
        }
        let favs = pool.filter(\.favorite)
        let list = (favs.isEmpty ? pool : favs).sorted { $0.createdAt < $1.createdAt }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let r = list[day % list.count]
        return make(r, favs.isEmpty ? "From your library" : "One of your favourites")
    }
}
