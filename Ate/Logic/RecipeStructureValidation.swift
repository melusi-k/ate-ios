import Foundation

/// Enabled for prompt/social by default. DEBUG opt-out supports paired device eval.
enum RecipeGenerationToolGate {
    static var enabled: Bool {
#if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-qaDisableRecipeGenerationTool")
#else
        true
#endif
    }
    static func applies(enabled: Bool, input: RecipePrompt.Input) -> Bool {
        enabled && (input == .prompt || input == .social)
    }
}

/// Deterministic validation shared by the Tool and unit tests. Model-provided
/// schemas are shape constraints, not trusted semantic validation or source proof.
enum RecipeStructureValidation {
    struct Invalid: LocalizedError {
        let reason: String
        var errorDescription: String? { "Recipe structuring was not accepted: " + reason }
    }
    private struct Structure: Codable {
        let ingredients: [Ingredient]
        let steps: [Step]
    }
    static func signature(ingredients: [Ingredient], steps: [Step]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(Structure(ingredients: ingredients, steps: steps)), as: UTF8.self)
    }
    static func validate(ingredients: [Ingredient], steps: [Step]) throws -> String {
        guard (1...30).contains(ingredients.count), (1...20).contains(steps.count) else {
            throw Invalid(reason: "ingredient or step count is outside the supported bounds.")
        }
        for ingredient in ingredients {
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let toTaste = (ingredient.notes ?? "").lowercased().contains("to taste") || unit.lowercased() == "to taste"
            guard !name.isEmpty, name.count <= 160,
                  !IngredientFieldNormalization.isPreparationOnly(name),
                  name.rangeOfCharacter(from: .letters) != nil,
                  ingredient.quantity.isFinite, ingredient.quantity >= 0, ingredient.quantity <= 5000,
                  ingredient.quantity > 0 || toTaste,
                  (ingredient.notes ?? "").count <= 300 else {
                throw Invalid(reason: "an ingredient needs a food name and a finite supported amount.")
            }
            guard unit.isEmpty || unit == "to taste" || IngredientParser.units[unit] != nil || IngredientParser.units[unit.lowercased()] != nil,
                  IngredientFieldNormalization.normalizeGenerated(ingredient) == ingredient else {
                throw Invalid(reason: "put food in name, a measurement in unit, and preparation in prep.")
            }
        }
        for (index, step) in steps.enumerated() {
            guard step.order == index + 1, !RecipeLogic.nonBlank([step]).isEmpty,
                  step.instruction.count <= 2000,
                  step.timeSeconds == nil || (1...43_200).contains(step.timeSeconds!) else {
                throw Invalid(reason: "steps need ordered non-empty instructions and supported durations.")
            }
        }
        let card = RecipeCard(ingredients: ingredients, steps: steps, source: .appleIntelligence)
        let gaps = GeneratedStepQuality.issues(card)
        guard gaps.isEmpty else { throw Invalid(reason: gaps.joined(separator: " ")) }
        return try signature(ingredients: ingredients, steps: steps)
    }
}

/// Tools can be called zero, once, repeatedly or concurrently. Store only bounded
/// validated signatures, reject invalid calls, and require final output to match.
actor RecipeStructureReceipt {
    private var signatures = Set<String>()
    private var calls = 0
    private var rejected = false
    func reject() { rejected = true }
    func record(_ signature: String) throws {
        calls += 1
        guard calls <= 8, !rejected else {
            rejected = true
            throw RecipeStructureValidation.Invalid(reason: "tool-call limit exceeded or a tool call was invalid.")
        }
        signatures.insert(signature)
    }
    func require(_ signature: String) throws {
        guard !rejected, signatures.contains(signature) else {
            throw RecipeStructureValidation.Invalid(reason: "the final structure did not match a valid tool result.")
        }
    }
}
