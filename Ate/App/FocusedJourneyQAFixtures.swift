#if DEBUG
import Foundation

/// Saved-recipe setup only. The journeys still drive real navigation, Cook,
/// Journal, native sort menus and reorder actions. No history/session is seeded.
enum FocusedJourneyQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting else { return }
        let args = ProcessInfo.processInfo.arguments
        let cook = args.contains("-qaSavedRecipeForCookExit")
        let reorder = args.contains("-qaSavedRecipesForReorder")
        guard cook || reorder else { return }
        precondition(cook != reorder, "Choose exactly one focused journey fixture")
        store.filter.clear()
        store.layout = LibraryLayout()
        if cook {
            let recipe = RecipeCard(id: "qa-focused-cook-exit", title: "Miso salmon for two",
                servings: 2, timeMinutes: 25,
                ingredients: [.init(name: "salmon fillets", quantity: 2, unit: "pcs"),
                              .init(name: "white miso", quantity: 2, unit: "tbsp"),
                              .init(name: "honey", quantity: 1, unit: "tbsp"),
                              .init(name: "garlic", quantity: 2, unit: "cloves", notes: "finely chopped"),
                              .init(name: "rice", quantity: 150, unit: "g")],
                steps: [Step(order: 1, instruction: "Heat the oven to 200°C and line a tray.", timeSeconds: nil),
                        Step(order: 2, instruction: "Mix miso, honey and garlic; brush over the salmon.", timeSeconds: nil),
                        Step(order: 3, instruction: "Roast the salmon until just flaky.", timeSeconds: 600),
                        Step(order: 4, instruction: "Rest for a minute, then serve over rice.", timeSeconds: 60)])
            store.recipes = [recipe]
            // Match the normal post-save detail route; Cook entry and exit are not mocked.
            store.path = [.recipe(recipe.id)]
        } else {
            // Both remain unordered. The test must select My order through the real menu.
            store.recipes = [RecipeCard(id: "qa-focused-second", title: "Second dish", createdAt: 2),
                             RecipeCard(id: "qa-focused-first", title: "First dish", createdAt: 1)]
        }
    }
}
#endif
