import Foundation

/// A review hint, not a rename or a new save/repair gate. Only flag explicit,
/// exclusive ribs/wings disagreement supported by both ingredients and method.
enum GeneratedTitleReview {
    static func warning(_ card: RecipeCard) -> String? {
        guard RecipeQuality.isGenerated(card) else { return nil }
        let title = GeneratedStepQuality.words(card.title)
        let ingredients = GeneratedStepQuality.words(card.ingredients.map { IngredientFieldNormalization.identity($0) }.joined(separator: " "))
        let method = GeneratedStepQuality.words(card.steps.map(\.instruction).joined(separator: " "))
        for (named, written) in [("wing", "rib"), ("rib", "wing")] {
            guard title.contains(named), !title.contains(written),
                  ingredients.contains(written), !ingredients.contains(named),
                  method.contains(written), !method.contains(named) else { continue }
            return "The title says \(named)s, but the ingredients and method say \(written)s. Check which cut is intended; nothing has been renamed."
        }
        return nil
    }
}
