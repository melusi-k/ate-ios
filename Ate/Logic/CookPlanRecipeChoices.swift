import Foundation

/// A local chooser over saved recipes, never generated candidates or a second library owner.
enum CookPlanRecipeChoices {
    static func matches(_ recipes: [RecipeCard], query: String) -> [RecipeCard] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return recipes.filter { needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle) }
            .sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }
}
