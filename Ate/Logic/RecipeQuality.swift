import Foundation

/// The 80% rule and output-quality checks for AI-generated cards (C-AI-01…03).
/// Below 80% confidence (or with quality gaps) a generated card is a DRAFT that needs the user, never a recipe
/// that is quietly saved.
enum RecipeQuality {
    static let threshold = 0.8

    static func isGenerated(_ c: RecipeCard) -> Bool { [.appleIntelligence, .photoGuess].contains(c.source) }

    /// Should the sheet ask "What dish is this?" before showing the card at all?
    static func shouldAskDish(_ c: RecipeCard, alreadyConfirmed: Bool) -> Bool {
        isGenerated(c) && !alreadyConfirmed && (c.aiConfidence ?? 1) < threshold
    }

    /// Top guesses for the question, model's own name first (pre-filled).
    static func guesses(_ c: RecipeCard) -> [String] {
        var seen = Set<String>()
        return ([c.title] + (c.aiAlternatives ?? [])).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Unknown dish" && seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }

    static let ovenWords = ["bake", "roast", "oven", "grill in the oven", "broil"]
    static let mainWords = ["ribs", "wings", "chicken", "beef", "lamb", "pork", "stew", "curry", "steak", "fish", "mogodu", "nyama",
                            "oxtail", "pasta", "chops", "braai", "potjie", "casserole", "roast"]
    static let genericVerbs: Set<String> = ["cook", "prepare", "make", "finish", "serve", "do"]

    static func isMainDish(_ c: RecipeCard) -> Bool {
        let hay = ([c.title] + c.tags).joined(separator: " ").lowercased()
        return mainWords.contains { CoverLogic.matches(hay, $0) }
    }
    static func hasTemperature(_ s: String) -> Bool {
        s.range(of: #"\d{2,3}\s*°?\s*(c|f)\b|\d{2,3}\s*°|gas mark|degrees"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    /// "cook ribs", "prepare the chicken": a bare verb plus 1–2 words says nothing about how.
    static func isGenericStep(_ s: String) -> Bool {
        let w = s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { !["the", "a", "an"].contains($0) }
        guard let first = w.first else { return true }
        return w.count <= 3 && genericVerbs.contains(first)
    }

    /// Human-readable gaps; empty means the card meets the bar.
    static func issues(_ c: RecipeCard) -> [String] {
        var out: [String] = []
        let real = c.ingredients.filter { $0.quantity > 0 && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if isMainDish(c) && real.count < 4 { out.append("Needs at least 4 ingredients with quantities (has \(real.count)).") }
        let steps = RecipeLogic.nonBlank(c.steps)
        if steps.isEmpty { out.append("No steps.") }
        for s in steps where ovenWords.contains(where: { s.instruction.lowercased().contains($0) }) && !hasTemperature(s.instruction) {
            out.append("Step \(s.order) uses the oven but gives no temperature."); break
        }
        if let g = steps.first(where: { isGenericStep($0.instruction) }) { out.append("Step \(g.order) (“\(g.instruction)”) is too vague.") }
        if steps.contains(where: { s in s.timeSeconds == nil && (Durations.minimumSeconds(for: s.instruction) ?? 0) >= 15 * 60 && Durations.seconds(in: s.instruction) == nil }) {
            out.append("A long cooking step has no believable time.")
        }
        return out
    }

    /// "Draft, needs your input": Save stays disabled until the user edits or confirms.
    static func needsInput(_ c: RecipeCard) -> Bool {
        isGenerated(c) && ((c.aiConfidence ?? 1) < threshold || !issues(c).isEmpty)
    }
}
