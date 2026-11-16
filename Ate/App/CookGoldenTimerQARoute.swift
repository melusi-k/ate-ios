#if DEBUG
import Foundation

/// Explicit test-only setup for layout evidence, not proof of the Start timer interaction.
/// Uses the real timer start and pushed detail route. No timer or idle behavior is disabled.
@MainActor
enum CookGoldenTimerQARoute {
    static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting,
              ProcessInfo.processInfo.arguments.contains("-qaCookGoldenRunningTimer") else { return }
        let recipe = RecipeCard(id: "qa-golden-timer", title: "Cook golden timer fixture",
            ingredients: [Ingredient(name: "pap", quantity: 200, unit: "g")],
            steps: [Step(order: 1, instruction: "Stir the pap, then simmer until cooked.", timeSeconds: 600)])
        store.recipes = [recipe]
        store.timers.start(recipe: recipe, stepIndex: 0)
        store.path = [.recipe(recipe.id)]
    }
}
#endif
