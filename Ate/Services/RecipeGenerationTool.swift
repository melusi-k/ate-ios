import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// No storage, networking or publication. The model supplies typed fields;
/// Swift validates them and returns the exact accepted ingredient/step payload.
@available(iOS 26.0, *)
struct RecipeGenerationTool: Tool {
    let receipt: RecipeStructureReceipt
    let name = "structureRecipe"
    let description = "Validates ingredient amounts, food names, prep and ordered cooking steps; returns the exact accepted structure."
    @Generable
    struct Arguments {
        @Guide(description: "Food belongs in name, units are measurements only, prep is separate", .count(1...30))
        var ingredients: [GenIngredient]
        @Guide(description: "Complete ordered steps, preserving source facts", .count(1...20))
        var steps: [GenStep]
    }
    func call(arguments: Arguments) async throws -> String {
        do {
            try GenerationCancellation.check()
            let result = try Self.validate(ingredients: arguments.ingredients, steps: arguments.steps)
            try await receipt.record(result)
            return result
        } catch {
            await receipt.reject()
            throw error
        }
    }
    static func validate(ingredients: [GenIngredient], steps: [GenStep]) throws -> String {
        // Check raw typed fields before conversion: no overflow or silently
        // ignored negative minutes/temperature is allowed through GenRecipe.
        for step in steps {
            guard step.minutes == nil || (1...720).contains(step.minutes!),
                  step.temperatureC == nil || (50...300).contains(step.temperatureC!) else {
                throw RecipeStructureValidation.Invalid(reason: "step minutes or temperature is outside the supported bounds.")
            }
        }
        let mappedIngredients = ingredients.map {
            Ingredient(name: $0.name, quantity: $0.quantity, unit: $0.unit, notes: $0.prep)
        }
        let mappedSteps = steps.enumerated().map { index, step in
            Step(order: index + 1, instruction: GenRecipe.instruction(step.instruction, temperatureC: step.temperatureC),
                 timeSeconds: step.minutes.map { $0 * 60 })
        }
        return try RecipeStructureValidation.validate(ingredients: mappedIngredients, steps: mappedSteps)
    }

}
#endif
