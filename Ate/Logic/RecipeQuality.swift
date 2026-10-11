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

    static let minIngredients = 3, minSteps = 3

    /// Visible things (Vision labels) that should be ingredients but aren't, e.g. bread/lettuce on a sandwich photo.
    static let nonIngredientLabels: Set<String> = ["sandwich", "burger", "plate", "dish", "meal", "food", "snack", "lunch", "breakfast",
                                                   "dinner", "baked goods", "fast food", "produce", "fried food", "cuisine"]
    static func missingVisible(_ c: RecipeCard, labels: [String]) -> [String] {
        let have = c.ingredients.map { $0.name.lowercased() }.joined(separator: " ")
        let hw = CoverLogic.words(have)
        return labels.map { $0.lowercased() }.filter { l in
            !nonIngredientLabels.contains(l) && !hw.contains(l) && !hw.contains(l + "s") && !have.contains(l)
                && !CoverLogic.words(c.title).contains(l)
        }
    }

    /// Too thin to show: fewer than 3 ingredients or 3 steps, or visible items missing. Triggers one regeneration.
    static func shortfall(_ c: RecipeCard, labels: [String] = []) -> [String] {
        var out = issues(c)
        if c.ingredients.filter({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }).count < minIngredients { out.append("Needs at least \(minIngredients) ingredients.") }
        if RecipeLogic.nonBlank(c.steps).count < minSteps { out.append("Needs at least \(minSteps) steps.") }
        let miss = missingVisible(c, labels: labels)
        if !miss.isEmpty { out.append("Missing what's visible in the photo: \(miss.joined(separator: ", ")).") }
        return out
    }

    /// One plated item in a photo (one sandwich, burger, wrap, bowl) serves 1 unless the model saw several.
    static let singleItems = ["sandwich", "burger", "wrap", "toastie", "sub", "bowl", "omelette", "taco", "hotdog", "smoothie"]
    static func inferredServings(_ c: RecipeCard, fromPhoto: Bool) -> Int {
        guard fromPhoto, singleItems.contains(where: { CoverLogic.matches(c.title, $0) }),
              !CoverLogic.words(c.title).contains(where: { ["sandwiches", "burgers", "wraps", "platter", "tray"].contains($0) }) else { return c.servings }
        return 1
    }

    /// "cheese and polony sandwich" → "Cheese and Polony Sandwich" (only when the model wrote it all lowercase).
    static func titleCased(_ t: String) -> String {
        guard t == t.lowercased(), t.contains(where: \.isLetter) else { return t }
        let small: Set<String> = ["and", "or", "with", "of", "the", "a", "an", "in", "on", "en", "na", "ne", "le"]
        return t.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { i, w in
            let s = String(w)
            return (i > 0 && small.contains(s)) ? s : s.prefix(1).uppercased() + s.dropFirst()
        }.joined(separator: " ")
    }

    /// "Draft, needs your input": Save stays disabled until the user edits or confirms.
    static func needsInput(_ c: RecipeCard) -> Bool {
        isGenerated(c) && ((c.aiConfidence ?? 1) < threshold || !issues(c).isEmpty)
    }
}

/// Live, partially generated card shown while Foundation Models streams (built from GenRecipe.PartiallyGenerated).
struct RecipeStreamPreview: Equatable {
    var title: String?
    var cuisine: String?
    var confidence: Double?
    var ingredients: [String] = []
    var steps: [String] = []
}

/// One clear message per LanguageModelSession.GenerationError case (mapped in OnDeviceBackend).
enum GenerationFailure: Equatable, CaseIterable {
    case tooLong, assetsUnavailable, guardrail, unsupportedGuide, language, decoding, rateLimited, other
    var message: String {
        switch self {
        case .tooLong: return "That page or caption is too long for on-device AI. Paste just the recipe part and try again."
        case .assetsUnavailable: return "Apple Intelligence is still getting ready on this iPhone. Try again in a few minutes."
        case .guardrail: return "Apple Intelligence wouldn't write this one. Try describing the dish differently."
        case .unsupportedGuide: return "Ate asked the model for something it can't do. Please report this from Beta testing."
        case .language: return "On-device AI doesn't support this language yet. Try the recipe in English."
        case .decoding: return "AI returned an unreadable recipe. Try again."
        case .rateLimited: return "Apple Intelligence is busy. Wait a moment and try again."
        case .other: return "Something went wrong generating the recipe. Try again."
        }
    }
}
