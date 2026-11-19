#if DEBUG
import Foundation
/// Synthetic saved favourites/cooking history only; never selects or opens cards.
enum LibrarySelectionQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting,
              ProcessInfo.processInfo.arguments.contains("-qaLibrarySelectionRediscovery") else { return }
        guard store.recipes.isEmpty else { return }
        let now = Date().timeIntervalSince1970 * 1000
        store.recipes = ["qa-dogfood-first", "qa-dogfood-second"].enumerated().map { index, id in
            var card = RecipeCard(id: id, title: index == 0 ? "Zesty tacos" : "Apple crumble", servings: 2, timeMinutes: 25)
            card.favorite = true
            card.lastCookedAt = now - Double(index * 1000)
            return card
        }
        store.filter.clear()
        store.layout = LibraryLayout()
    }
}
#endif
