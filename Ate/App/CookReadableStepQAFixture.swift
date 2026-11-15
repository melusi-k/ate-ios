import Foundation

#if DEBUG
/// One synthetic long instruction on the normal Cook route. No model or real data.
@MainActor
enum CookReadableStepQAFixture {
    static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaCookReadableStep") else { return }
        let instruction = """
        Before heating the pan, measure the beans and stock into separate bowls. Rinse the beans, drain well, and set them beside the hob. Chop the onion into even pieces so it softens at the same rate.

        Warm the oil over medium heat. Add the onion and stir gently until it softens without browning. Add the carrots and peppers, turn them through the oil, and scrape any pieces from the bottom of the pan with a wooden spoon.

        Stir in the tomatoes and beans, then pour in the measured stock. Bring to a gentle simmer. Lower the heat, cover loosely, and stir from the bottom occasionally so the beans do not stick. Add a little water only if the mixture starts to catch.

        Check that the vegetables are tender and that the sauce coats the back of a spoon. Taste a small cooled spoonful, adjust the seasoning, and remove the pan from the heat. Final check: serve the stew while warm.
        """
        let recipe = RecipeCard(id: "qa-readable-cook", title: "Readable long-step stew", steps: [
            Step(order: 1, instruction: instruction, timeSeconds: nil),
            Step(order: 2, instruction: "Put the remaining stew into a clean serving bowl.", timeSeconds: nil)
        ])
        store.recipes = [recipe]
        store.beginCookSession(recipeID: recipe.id, factor: 1)
        store.cookTarget = CookTarget(id: recipe.id)
    }
}
#endif
