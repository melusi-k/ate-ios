import Foundation

/// Bounded no-op detection and fail-closed checks for a simple vegan request.
/// This is not a general dietary certification or a semantic rewrite verifier.
enum RecipeRewriteScope {
    static func simpleVeganRequest(_ text: String) -> Bool {
        ["make this vegan", "make it vegan", "make this recipe vegan"].contains(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".!")))
    }
    private static let knownPlantIngredients: Set<String> = ["oil", "olive oil", "vegetable oil", "sunflower oil", "onion", "onions", "carrot", "carrots", "green pepper", "green peppers", "red pepper", "red peppers", "bell pepper", "bell peppers", "green bell pepper", "green bell peppers", "red bell pepper", "red bell peppers", "curry powder", "baked beans", "tinned baked beans", "canned baked beans", "salt", "water", "garlic", "tomato", "tomatoes", "black pepper", "paprika", "chilli", "cumin"]
    private static let animalOrUnclearCues = ["butter", "milk", "cream", "egg", "eggs", "chicken", "beef", "pork", "bacon", "fish", "honey", "cheese", "ham", "ghee", "lard", "stock", "meat", "gelatin", "gelatine", "whey", "casein", "yogurt", "yoghurt", "prawn", "shrimp", "anchovy", "anchovies"]
    static func hasResidualAnimalCue(_ card: RecipeCard) -> Bool {
        var text = card.steps.map(\.instruction).joined(separator: " ") + " " + card.ingredients.compactMap(\.notes).joined(separator: " ")
        // Only explicit approved plant phrases suppress their embedded animal
        // word. Removing 'vegan butter' must not hide a later 'milk' or stock.
        for phrase in ["vegan butter", "oat milk", "soy milk", "flax eggs", "flax egg", "vegetable stock"] {
            text = text.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b", with: "plant substitute", options: [.regularExpression, .caseInsensitive])
        }
        return animalOrUnclearCues.contains { CoverLogic.matches(text, $0) }
    }

    static func noOpMessage(for card: RecipeCard, request: String) -> String? {
        guard simpleVeganRequest(request), !card.ingredients.isEmpty,
              card.ingredients.allSatisfy({ knownPlantIngredients.contains($0.name.lowercased().trimmingCharacters(in: .whitespaces)) }),
              !card.steps.isEmpty else { return nil }
        guard !hasResidualAnimalCue(card) else { return nil }
        return "This card already uses plant-based ingredients. No changes made. Check packaged ingredients are vegan."
    }

    static func accept(_ candidate: RecipeCard, original: RecipeCard, request: String) throws -> RecipeCard {
        let rejection = BackendError(message: "The rewrite changed more than you asked. Your recipe is unchanged. Try a specific edit or use Repair these gaps separately.")
        // A vegan edit has no authority to add cooking temperatures or repair all
        // validator bullets. Only bounded ingredient substitutions are admitted.
        if simpleVeganRequest(request) {
            guard candidate.title == original.title, candidate.description == original.description,
                  candidate.servings == original.servings, candidate.timeMinutes == original.timeMinutes,
                  candidate.ingredients.count == original.ingredients.count,
                  candidate.steps.count == original.steps.count else { throw rejection }
            let replacements: [String: Set<String>] = ["butter": ["vegan butter", "olive oil"], "milk": ["oat milk", "soy milk"],
                "chicken": ["firm tofu", "tofu"], "beef": ["firm tofu", "tofu"], "egg": ["flax egg"], "eggs": ["flax eggs"]]
            var edits: [(String, String)] = []
            for (before, after) in zip(original.ingredients, candidate.ingredients) {
                guard before.quantity == after.quantity, before.unit == after.unit, before.notes == after.notes else { throw rejection }
                if before.name != after.name {
                    guard replacements[before.name.lowercased()]?.contains(after.name.lowercased()) == true else { throw rejection }
                    edits.append((before.name, after.name))
                }
            }
            for (before, after) in zip(original.steps, candidate.steps) {
                var expected = before.instruction
                for (from, to) in edits {
                    expected = expected.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b", with: to, options: [.regularExpression, .caseInsensitive])
                }
                guard after.order == before.order, after.timeSeconds == before.timeSeconds, after.instruction == expected else { throw rejection }
            }
            let acceptedPlantNames = knownPlantIngredients.union(replacements.values.reduce(into: Set<String>()) { $0.formUnion($1) })
            guard !edits.isEmpty, candidate.ingredients.allSatisfy({ acceptedPlantNames.contains($0.name.lowercased()) }),
                  !hasResidualAnimalCue(candidate) else { throw rejection }
        } else {
            // For other requests, never admit a new oven-style cue unless the
            // request itself asks for a temperature/oven method change.
            let asksHeat = request.range(of: #"\boven|\bbake|\broast|\btemperature|\bdegrees"#, options: [.regularExpression, .caseInsensitive]) != nil
            if !asksHeat {
                guard candidate.steps.count == original.steps.count else { throw rejection }
                for (before, after) in zip(original.steps, candidate.steps) where !RecipeQuality.hasTemperature(before.instruction) {
                    if RecipeQuality.hasTemperature(after.instruction) { throw rejection }
                }
            }
        }
        let vegan = simpleVeganRequest(request)
        var result = vegan ? original : candidate
        result.ingredients = candidate.ingredients
        result.steps = candidate.steps
        if vegan, !result.tags.contains("vegan") { result.tags.append("vegan") }
        // Provenance/identity/media are not part of an asked recipe edit.
        result.id = original.id; result.createdAt = original.createdAt
        result.favorite = original.favorite; result.sortIndex = original.sortIndex
        result.lastCookedAt = original.lastCookedAt; result.coverImage = original.coverImage
        result.imageURL = original.imageURL; result.sourceURL = original.sourceURL
        result.source = original.source; result.origin = original.origin
        result.aiConfidence = original.aiConfidence; result.aiAlternatives = original.aiAlternatives
        return result
    }
}
