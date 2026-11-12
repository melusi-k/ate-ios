import Foundation

/// Conservative repair hints, not a claim to understand every food or method.
/// Never adds ingredients, rewrites source text, or requires more steps by count.
enum GeneratedStepQuality {
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map {
            let word = String($0)
            if word == "salted" { return "salt" }
            if ["loaf", "loaves"].contains(word) { return "bread" }
            if word == "leaves" { return "leaf" }
            if word == "tomatoes" { return "tomato" }
            if word == "potatoes" { return "potato" }
            return word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
        })
    }

    // Head food nouns only; avoid adjectives/prep terms such as fresh, crushed,
    // ground, red, powder. Unknown vocabulary stays a human/model review gap.
    static let foods: Set<String> = ["salt", "oil", "water", "butter", "milk", "cream", "egg", "flour", "sugar", "honey", "rice", "bread", "onion", "garlic", "ginger", "tomato", "potato", "carrot", "cabbage", "bean", "lentil", "chicken", "mutton", "lamb", "beef", "pork", "tripe", "fish", "salmon", "cheese", "spinach", "pasta", "noodle", "vinegar", "stock", "rib", "wing", "curry", "cumin", "turmeric", "paprika", "coriander", "cinnamon", "pepper", "chilli"]
    static let heatActions: Set<String> = ["simmer", "boil", "fry", "sauté", "saute", "bake", "roast", "braise", "steam", "grill", "brown", "sear"]
    static let cues: Set<String> = ["tender", "soft", "softened", "golden", "browned", "thick", "thickened", "crisp", "crispy", "translucent", "fragrant", "bubbling", "sizzling", "melted", "dissolved", "reduced", "set", "flaky", "opaque", "wilted"]

    static func anchors(_ ingredient: String) -> Set<String> {
        let tokens = words(ingredient)
        // Do not require every descriptor of a compound: beef stock is used as
        // stock, chicken wings as wings, lemon pepper as pepper. Never infer meat
        // from stock or require a cook to repeat the full ingredient name.
        for head in ["stock", "rib", "wing", "bread", "oil", "milk", "cheese", "pepper"] where tokens.contains(head) {
            return [head]
        }
        return tokens.intersection(foods)
    }

    static func issues(_ card: RecipeCard) -> [String] {
        guard RecipeQuality.isGenerated(card) else { return [] }
        let steps = RecipeLogic.nonBlank(card.steps)
        let allStepWords = words(steps.map(\.instruction).joined(separator: " "))
        let ingredientWords = words(card.ingredients.map(\.name).joined(separator: " "))
        var gaps: [String] = []
        // Explicit collective use can be legitimate (dressings, batter, spice mixes).
        // Do not pretend to prove individual usage when the wording is collective.
        let collective = steps.contains { $0.instruction.lowercased().contains("all ingredients") || $0.instruction.lowercased().contains("remaining ingredients") }
        if !collective {
            for ingredient in card.ingredients {
                let ingredientAnchors = anchors(ingredient.name)
                if !ingredientAnchors.isEmpty && ingredientAnchors.isDisjoint(with: allStepWords) {
                    gaps.append("Explain when to use \(ingredient.name); it is listed but never used in the steps.")
                }
            }
        }
        // Report only known food nouns, with two common morphological aliases.
        var listed = ingredientWords
        if listed.contains("salt") { listed.insert("salted") }
        if listed.contains("bread") { listed.formUnion(["loaf", "loave"]) }
        for food in allStepWords.intersection(foods).subtracting(listed).sorted() {
            // 'oil' used as a verb still requires a listed cooking fat.
            if food == "oil", !listed.isDisjoint(with: ["butter", "ghee", "fat"]) { continue }
            gaps.append("Step mentions \(food), but it is not in the ingredients; reconcile it without inventing source facts.")
        }
        for step in steps {
            let tokens = words(step.instruction)
            // 'brown sugar' is an ingredient, not a command to brown it.
            let actionText = step.instruction.lowercased().replacingOccurrences(of: "brown sugar", with: "sugar")
            guard !words(actionText).isDisjoint(with: heatActions) else { continue }
            // Scan the complete instruction: compound actions such as rub,
            // cover and bake must not evade the check after the fifth word.
            if (step.timeSeconds ?? 0) <= 0 && Durations.seconds(in: step.instruction) == nil {
                gaps.append("Step \(step.order) needs a cooking time or range, not an unexplained wait.")
            }
            // Preserve the established oven time+temperature acceptance contract.
            // Explicit doneness remains preferred by the prompt, not a new rejection
            // of otherwise accepted oven instructions with time and temperature.
            let timed = (step.timeSeconds ?? 0) > 0 || Durations.seconds(in: step.instruction) != nil
            let checkedTemperature = RecipeQuality.hasTemperature(step.instruction) &&
                (!tokens.isDisjoint(with: ["internal", "centre", "center"]) ||
                 (timed && !tokens.isDisjoint(with: ["bake", "roast"])))
            if tokens.isDisjoint(with: cues) && !checkedTemperature {
                gaps.append("Step \(step.order) needs a doneness cue or a checked temperature, not time alone.")
            }
        }
        return gaps
    }
}
