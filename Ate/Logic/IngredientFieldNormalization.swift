import Foundation

/// Corrects only unambiguous field placement. Never guesses an amount or food.
enum IngredientFieldNormalization {
    private static let preparationWords: Set<String> = ["diced", "chopped", "sliced", "minced", "crushed", "grated", "peeled", "finely", "roughly", "thinly", "coarsely"]

    /// Known prep words alone are not a food identity, regardless of the unit.
    static func isPreparationOnly(_ name: String) -> Bool {
        let nameWords = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !nameWords.isEmpty && nameWords.isSubset(of: preparationWords)
    }

    static func splitPreparation(_ name: String) -> (name: String, prep: String?) {
        let tokens = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var end = tokens.count
        while end > 0 && preparationWords.contains(tokens[end - 1].lowercased()) { end -= 1 }
        guard end > 0, end < tokens.count else { return (name, nil) }
        return (tokens[..<end].joined(separator: " "), tokens[end...].joined(separator: " "))
    }

    /// Non-measure units sometimes hold a countable food ("1 onion diced").
    /// Known measurement/container units must never become ingredient identity.
    static func foodInUnit(_ ingredient: Ingredient) -> String? {
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty, IngredientParser.units[unit] == nil,
              IngredientParser.units[unit.lowercased()] == nil,
              !GeneratedStepQuality.anchors(unit).isEmpty else { return nil }
        return unit
    }

    static func normalizeGenerated(_ original: Ingredient) -> Ingredient {
        var ingredient = original
        if isPreparationOnly(original.name), let food = foodInUnit(original) {
            ingredient.name = food
            ingredient.unit = "pcs"
            ingredient.notes = [original.name, original.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
        } else {
            let split = splitPreparation(original.name)
            if let prep = split.prep {
                ingredient.name = split.name
                ingredient.notes = [prep, original.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
            }
        }
        return ingredient
    }

    static func identity(_ ingredient: Ingredient) -> String {
        [ingredient.name, foodInUnit(ingredient)].compactMap { $0 }.joined(separator: " ")
    }
}
