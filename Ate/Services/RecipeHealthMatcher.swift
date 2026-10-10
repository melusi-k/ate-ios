import Foundation

/// Ranks saved recipes for a body state using ingredients, tags, title and time. Heuristic, not nutrition advice.
enum RecipeHealthMatcher {
    static let protein = ["chicken", "beef", "steak", "lamb", "pork", "fish", "salmon", "tuna", "egg", "beans", "lentil",
                          "chickpea", "tofu", "yoghurt", "yogurt", "cottage cheese", "prawn", "mince",
                          "turkey", "quinoa", "protein", "boerewors", "mogodu", "liver"]
    static let light = ["salad", "soup", "broth", "vegetable", "veg", "spinach", "greens", "cucumber", "tomato", "steamed", "grilled",
                        "zucchini", "courgette", "cabbage", "light", "lemon", "herbs", "morogo"]
    static let comfort = ["stew", "soup", "curry", "porridge", "pap", "oats", "broth", "bake", "potjie", "chakalaka", "samp"]
    static let heavy = ["fried", "deep-fried", "cream", "butter", "cheese", "bacon", "sugar", "pastry", "fat cake", "vetkoek"]
    static let energy = ["oats", "rice", "pasta", "sweet potato", "banana", "wholegrain", "grain", "bowl", "fruit"]

    static func suggestions(for state: HealthState, recipes: [RecipeCard], limit: Int = 3) -> [NutritionFitSuggestion] {
        var scored: [NutritionFitSuggestion] = []
        for r in recipes {
            let (sc, why): (Double, String) = score(r, state)
            if sc > 0 { scored.append(NutritionFitSuggestion(recipeID: r.id, title: r.title, why: why, score: sc)) }
        }
        scored.sort { (a: NutritionFitSuggestion, b: NutritionFitSuggestion) -> Bool in
            a.score != b.score ? a.score > b.score : a.title < b.title
        }
        return Array(scored.prefix(limit))
    }

    static func score(_ r: RecipeCard, _ state: HealthState) -> (score: Double, why: String) {
        var parts: [String] = [r.title, r.description ?? "", r.cuisine ?? ""]
        parts += r.tags
        parts += r.ingredients.map { $0.name }
        let text = parts.joined(separator: " ").lowercased()
        func hits(_ words: [String]) -> Int {
            var n = 0
            for w in words where text.range(of: "\\b" + w + "s?\\b", options: .regularExpression) != nil { n += 1 }
            return n
        }
        let p = hits(protein), l = hits(light), c = hits(comfort), h = hits(heavy), e = hits(energy)
        let quick = (r.timeMinutes ?? 99) <= 30
        var s = 0.0; var why = ""
        switch state {
        case .recovery:
            s = Double(p) * 3; s += Double(e); if quick { s += 0.5 }; why = p > 0 ? "Protein for recovery" : "Refuels after training"
        case .lowEnergy:
            s = Double(c) * 2; s += Double(l) * 1.5; s -= Double(h); if quick { s += 2 }; why = quick ? "Quick and comforting" : "Gentle and comforting"
        case .underactive:
            s = Double(l) * 2.5; s += Double(p); s -= Double(h) * 2; why = "Lighter dinner"
        case .performance:
            s = Double(e) * 2; s += Double(p) + Double(l); if r.servings >= 4 { s += 2 }; why = r.servings >= 4 ? "Good for meal prep" : "Energising"
        case .balanced:
            s = 1 + Double(l); s += Double(p) * 0.5; if r.favorite { s += 1 }; why = r.favorite ? "One of your favourites" : "A good fit today"
        }
        if r.favorite { s += 0.5 }
        return (s, why)
    }
}
