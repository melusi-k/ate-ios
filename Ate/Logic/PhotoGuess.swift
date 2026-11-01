import Foundation

/// Food photo (no recipe text) → likely dish → drafted recipe.
enum PhotoGuess {
    /// Screenshot of a recipe vs. a photo with stray text (a label, a menu word).
    static func isScreenshotText(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace }.count
        let lines = text.split(separator: "\n").count
        return words >= 15 || (lines >= 4 && words >= 8)
    }

    /// Vision taxonomy labels that are not dishes (scene/object/very generic).
    static let generic: Set<String> = ["food", "dish", "meal", "cuisine", "recipe", "plate", "bowl", "table", "tableware", "dishware",
        "cutlery", "fork", "spoon", "knife", "indoor", "outdoor", "kitchen", "people", "adult", "hand", "wood", "wood_processed",
        "textile", "structure", "container", "breakfast", "lunch", "dinner", "brunch", "snack", "dessert_food", "drinking_glass", "cup", "napkin", "dining_room", "restaurant", "interior_room", "furniture"]

    /// Ordered dish candidates (specific first) from `(identifier, confidence)` labels.
    static func dishes(from labels: [(String, Float)]) -> [String] {
        labels.sorted { $0.1 > $1.1 }
            .map { $0.0.lowercased() }
            .filter { !generic.contains($0) && !PhotoGuess.isNonDishObject($0) }
            .map { $0.replacingOccurrences(of: "_", with: " ") }
    }

    /// True when the labels contain something food-like enough to draft from.
    /// (Was `prompt(labels:ocrText:) != nil` - the prompt string it built was never sent to a model;
    /// MockBackend only used it as this nil-check.)
    static func canDraft(from labels: [(String, Float)]) -> Bool {
        let d = dishes(from: labels)
        let foodish = labels.contains { ["food", "dish", "meal", "cuisine", "baked_goods", "dessert", "fruit", "vegetable"].contains($0.0.lowercased()) }
        return !d.isEmpty && (foodish || d.count >= 2)
    }
}

