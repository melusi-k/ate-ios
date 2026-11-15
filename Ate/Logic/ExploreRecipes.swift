import Foundation

/// Local discovery only. Never fabricates a catalogue, popularity or model ranking.
enum ExploreRecipes {
    struct Group: Identifiable {
        let id: String
        let title: String
        let explanation: String
        let recipes: [RecipeCard]
    }

    static func groups(recipes: [RecipeCard], completed: [String: Set<String>]) -> [Group] {
        // Ignore stale completion references and duplicate identities; a recipe may
        // intentionally appear in more than one collection.
        var seen = Set<String>()
        let saved = recipes.filter { seen.insert($0.id).inserted }
        func newest(_ a: RecipeCard, _ b: RecipeCard) -> Bool {
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id < b.id
        }
        let quick = saved.filter { ($0.timeMinutes ?? 0) > 0 && ($0.timeMinutes ?? 0) <= 30 }.sorted {
            if $0.timeMinutes != $1.timeMinutes { return ($0.timeMinutes ?? 0) < ($1.timeMinutes ?? 0) }
            return newest($0, $1)
        }
        let favourites = saved.filter(\.favorite).sorted(by: newest)
        // CookingHistory day keys use fixed yyyy-MM-dd. A lastCookedAt value
        // alone can represent older open-only behaviour, so never use it here.
        let lastDay = completed.reduce(into: [String: String]()) { result, pair in
            for id in pair.value { result[id] = max(result[id] ?? "", pair.key) }
        }
        let again = saved.filter { lastDay[$0.id] != nil }.sorted {
            if lastDay[$0.id] != lastDay[$1.id] { return (lastDay[$0.id] ?? "") > (lastDay[$1.id] ?? "") }
            return newest($0, $1)
        }
        return [
            Group(id: "quick", title: "30 minutes or less", explanation: "Saved recipes with a cooking time of 30 minutes or less.", recipes: quick),
            Group(id: "favourites", title: "Your favourites", explanation: "Recipes you have marked as favourites.", recipes: favourites),
            Group(id: "again", title: "Cook again", explanation: "Saved recipes from your recorded completed cooks on this iPhone.", recipes: again)
        ]
    }
}
