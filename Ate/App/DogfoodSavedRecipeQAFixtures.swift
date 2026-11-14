#if DEBUG
import Foundation

/// Precondition data for menu/reorder and Cook Mode. Only the explicit action-only
/// flag selects My order; card positions and action results are never seeded.
enum DogfoodSavedRecipeQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting else { return }
        let args = ProcessInfo.processInfo.arguments
        let menus = args.contains("-qaSavedRecipesForGroupSort")
        let reorder = args.contains("-qaSavedRecipesForDogfoodReorder")
        let reorderAction = args.contains("-qaSavedRecipesForReorderAction")
        let cook = args.contains("-qaSavedRecipeForCookMode")
        guard menus || reorder || reorderAction || cook else { return }
        precondition([menus, reorder, reorderAction, cook].filter { $0 }.count == 1, "Choose exactly one Dogfood saved-recipe fixture")
        store.filter.clear()
        store.layout = LibraryLayout()
        if reorderAction { store.layout.sort = .myOrder }
        let now = Date().timeIntervalSince1970 * 1000
        if cook {
            store.recipes = [card(id: "qa-cook-mode-saved", title: "Miso salmon for two", createdAt: now)]
            return
        }
        let first = card(id: "qa-dogfood-first", title: menus ? "Zesty tacos" : "First dish", createdAt: now - 1000)
        let second = card(id: "qa-dogfood-second", title: menus ? "Apple crumble" : "Second dish", createdAt: now)
        store.recipes = [second, first]
    }

    private static func card(id: String, title: String, createdAt: Double) -> RecipeCard {
        // Match the existing mock generation's 25-minute card, including shopping
        // ingredients, while keeping both recipes unordered and unfavourited.
        RecipeCard(id: id, title: title, servings: 2, timeMinutes: 25,
            ingredients: [.init(name: "salmon fillets", quantity: 2, unit: "pcs"),
                          .init(name: "white miso", quantity: 2, unit: "tbsp"),
                          .init(name: "honey", quantity: 1, unit: "tbsp"),
                          .init(name: "garlic", quantity: 2, unit: "cloves", notes: "finely chopped"),
                          .init(name: "rice", quantity: 150, unit: "g")],
            steps: [Step(order: 1, instruction: "Heat the oven to 200°C and line a tray.", timeSeconds: nil),
                    Step(order: 2, instruction: "Mix miso, honey and garlic; brush over the salmon.", timeSeconds: nil),
                    Step(order: 3, instruction: "Roast the salmon until just flaky.", timeSeconds: 600),
                    Step(order: 4, instruction: "Rest for a minute, then serve over rice.", timeSeconds: 60)],
            createdAt: createdAt)
    }
}
#endif
