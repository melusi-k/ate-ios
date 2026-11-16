import Foundation

/// Corrects only unambiguous field placement. Never guesses an amount or food.
enum IngredientFieldNormalization {
    private static let preparationWords: Set<String> = ["diced", "chopped", "sliced", "minced", "crushed", "grated", "peeled", "finely", "roughly", "thinly", "coarsely"]

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

    /// Join preparation once without losing distinct preparation details.
    static func preparation(_ first: String?, _ second: String?) -> String? {
        let pieces = [first, second].compactMap { $0 }.flatMap { $0.components(separatedBy: ";") }
        var seen = Set<String>()
        let unique = pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: "; ")
    }

    /// Presentation does not invent a sprig, clove or gram measure from "herb".
    /// Keep the original unit in the draft for the quality warning and editor.
    static func displayUnit(_ ingredient: Ingredient, generated: Bool) -> String {
        if generated && ["herb", "herbs"].contains(ingredient.unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) { return "" }
        return ingredient.unit
    }

    static func normalizeGenerated(_ original: Ingredient) -> Ingredient {
        var ingredient = original
        let nameWords = Set(original.name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !nameWords.isEmpty, nameWords.isSubset(of: preparationWords), let food = foodInUnit(original) {
            ingredient.name = food
            ingredient.unit = "pcs"
            ingredient.notes = preparation(original.name, original.notes)
        } else {
            let split = splitPreparation(original.name)
            if let prep = split.prep {
                ingredient.name = split.name
                ingredient.notes = preparation(prep, original.notes)
            }
        }
        ingredient.notes = preparation(ingredient.notes, nil)
        return ingredient
    }

    static func identity(_ ingredient: Ingredient) -> String {
        [ingredient.name, foodInUnit(ingredient)].compactMap { $0 }.joined(separator: " ")
    }
}
