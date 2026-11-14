import Foundation

/// Presentation-only: the stored ingredient list and nutrition calculation keep
/// every source row. Never infer amounts, sum rows, or merge different prep uses.
enum IngredientPresentation {
    private struct Key: Hashable {
        let quantity: Double
        let unit: String
        let name: String
        let notes: String
    }
    private static func textKey(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    static func rows(_ ingredients: [Ingredient], units: UnitSystem) -> [Ingredient] {
        var seen = Set<Key>()
        return ingredients.filter { ingredient in
            // Identity must precede lossy conversion/formatting. Different source
            // quantities can render identically (100g and101g both show3.5oz).
            let key = Key(quantity: ingredient.quantity, unit: ingredient.unit, name: textKey(ingredient.name),
                          notes: textKey(ingredient.notes ?? ""))
            return seen.insert(key).inserted
        }
    }
    static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(textKey($0)).inserted }
    }
}
