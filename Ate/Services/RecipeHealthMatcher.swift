import Foundation

/// Ranks saved recipes for a body state using ingredients, tags, title and time. Heuristic, not nutrition advice.
enum RecipeHealthMatcher {
    static let protein = ["chicken", "beef", "steak", "lamb", "pork", "fish", "salmon", "tuna", "egg", "eggs", "beans", "lentil", "lentils",
                          "chickpea", "chickpeas", "tofu", "yoghurt", "yogurt", "greek yogurt", "cottage cheese", "prawn", "prawns", "mince",
                          "turkey", "quinoa", "protein", "boerewors", "mogodu", "liver"]
    static let light = ["salad", "soup", "broth", "vegetable", "veg", "spinach", "greens", "cucumber", "tomato", "steamed", "grilled",
                        "zucchini", "courgette", "cabbage", "light", "lemon", "herbs", "morogo"]
    static let comfort = ["stew", "soup", "curry", "porridge", "pap", "oats", "broth", "bake", "potjie", "chakalaka", "samp"]
    static let heavy = ["fried", "deep-fried", "cream", "butter", "cheese", "bacon", "sugar", "pastry", "fat cake", "vetkoek"]
    static let energy = ["oats", "rice", "pasta", "sweet potato", "banana", "wholegrain", "grain", "bowl", "fruit"]

    static func suggestions(for state: HealthState, recipes: [RecipeCard], limit: Int = 3) -> [NutritionFitSuggestion] {
        recipes.map { r in (r, score(r, state)) }
            .filter { $0.1.score > 0 }
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0.title < $1.0.title }
            .prefix(limit)
            .map { NutritionFitSuggestion(recipeID: $0.0.id, title: $0.0.title, why: $0.1.why, score: $0.1.score) }
    }

    static func score(_ r: RecipeCard, _ state: HealthState) -> (score: Double, why: String) {
        let text = ([r.title, r.description ?? "", r.cuisine ?? ""] + r.tags + r.ingredients.map(\.name)).joined(separator: " ").lowercased()
        func hits(_ words: [String]) -> Int { words.filter { text.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }.count }
        let p = hits(protein), l = hits(light), c = hits(comfort), h = hits(heavy), e = hits(energy)
        let quick = (r.timeMinutes ?? 99) <= 30
        var s = 0.0; var why = ""
        switch state {
        case .recovery:
            s = Double(p) * 3 + Double(e) + (quick ? 0.5 : 0); why = p > 0 ? "Protein for recovery" : "Refuels after training"
        case .lowEnergy:
            s = Double(c) * 2 + Double(l) * 1.5 + (quick ? 2 : 0) - Double(h); why = quick ? "Quick and comforting" : "Gentle and comforting"
        case .underactive:
            s = Double(l) * 2.5 + Double(p) - Double(h) * 2; why = "Lighter dinner"
        case .performance:
            s = Double(e) * 2 + Double(p) + ((r.servings >= 4) ? 2 : 0) + Double(l); why = r.servings >= 4 ? "Good for meal prep" : "Energising"
        case .balanced:
            s = 1 + Double(l) + Double(p) * 0.5 + (r.favorite ? 1 : 0); why = r.favorite ? "One of your favourites" : "A good fit today"
        }
        if r.favorite { s += 0.5 }
        return (s, why)
    }
}
