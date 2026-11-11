import Foundation

/// Bounded, deterministic gaps for the generated-card repair loop. Never changes
/// imported/user recipes or fabricates quantities to make a check pass.
enum GeneratedRecipeConsistency {
    static func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { CoverLogic.matches(text.lowercased(), $0) }
    }

    static func issues(_ card: RecipeCard) -> [String] {
        guard RecipeQuality.isGenerated(card) else { return [] }
        var gaps: [String] = []
        let ingredients = card.ingredients.filter { $0.quantity.isFinite && $0.quantity > 0 }
            .map(\.name).joined(separator: " ").lowercased()
        let steps = RecipeLogic.nonBlank(card.steps).map(\.instruction).joined(separator: " ").lowercased()
        // Deliberately limited vocabulary, not an unreliable general food-name parser.
        // A source has already supplied its facts; these checks apply only to generated cards.
        let staples: [(String, [String])] = [
            ("salt", ["salt", "salted"]), ("oil", ["oil"]), ("water", ["water"])
        ]
        for (name, uses) in staples where contains(steps, uses) && !contains(ingredients, [name]) {
            gaps.append("Steps use \(name), but no measured \(name) ingredient is listed.")
        }
        if contains(card.title, ["bunny chow", "bunny-chow"]) {
            if !contains(ingredients, ["bread", "loaf", "loaves"]) {
                gaps.append("Bunny chow needs measured bread portions for the curry-filled hollowed loaf.")
            }
            if !contains(steps, ["hollow", "hollowed", "hollowing"]) ||
                !contains(steps, ["fill", "filled", "filling", "spoon", "ladle"]) {
                gaps.append("Bunny chow needs a step to hollow the bread and fill it with curry.")
            }
        }
        let seconds = RecipeLogic.nonBlank(card.steps).compactMap(\.timeSeconds).filter { $0 > 0 }.reduce(0, +)
        if seconds > 0, let total = card.timeMinutes {
            let stepMinutes = Int(ceil(Double(seconds) / 60))
            let note = card.aiNote ?? ""
            let expression = try? NSRegularExpression(pattern: #"\bprep:\s*(\d+)\s*min\b"#, options: .caseInsensitive)
            let ns = note as NSString
            let match = expression?.firstMatch(in: note, range: NSRange(location: 0, length: ns.length))
            let prep = match.flatMap { Int(ns.substring(with: $0.range(at: 1))) }
            let timingMismatch = prep.map { total != stepMinutes + $0 } ?? (total < stepMinutes)
            if timingMismatch {
                gaps.append("Total time must equal the step sum plus stated prep minutes.")
            } else if total > stepMinutes && prep == nil {
                gaps.append("Explain the extra \(total - stepMinutes) minutes as Prep: N min in the note; total time is steps plus prep.")
            }
        }
        return gaps
    }
}
