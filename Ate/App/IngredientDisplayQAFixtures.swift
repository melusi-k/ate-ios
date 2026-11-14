#if DEBUG
import Foundation

/// Explicit legacy-style duplicate fixture. It enters the real detail and nutrition
/// display without passing through generation normalization, as old saved cards do.
enum IngredientDisplayQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaDuplicateLemonDisplay") else { return }
        store.recipes = [RecipeCard(id: "qa-duplicate-lemon", title: "Fish and chips",
            ingredients: [.init(name: "for serving", quantity: 1, unit: "lemon", notes: "sliced"),
                          .init(name: " for  serving ", quantity: 1, unit: "lemon", notes: " SLICED ")],
            steps: [.init(order: 1, instruction: "Serve the lemon slices alongside the fish.", timeSeconds: nil)],
            source: .appleIntelligence)]
        store.filter.clear()
        store.layout.group = .none
    }
}
#endif
