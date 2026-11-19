import Foundation

/// Read-only detail metadata. Scaling yield never scales time or rewrites the source.
struct RecipeDetailMetadata: Equatable {
    let ingredientCount: Int
    let stepCount: Int
    let servings: Int?
    let totalMinutes: Int?

    init(_ recipe: RecipeCard, factor: Double) {
        ingredientCount = recipe.ingredients.count
        stepCount = RecipeLogic.nonBlank(recipe.steps).count
        if [1.0, 2.0, 3.0].contains(factor), recipe.servings > 0 {
            let scaled = recipe.servings.multipliedReportingOverflow(by: Int(factor))
            servings = scaled.overflow ? nil : scaled.partialValue
        } else { servings = nil }
        totalMinutes = recipe.timeMinutes.flatMap { $0 > 0 ? $0 : nil }
    }
}

enum RecipeDetailFeature {
    static var stitchRecipeDetailEnabled: Bool {
        enabled(configured: Bundle.main.object(forInfoDictionaryKey: "StitchRecipeDetailEnabled") as? Bool,
                isUITesting: AppConfig.isUITesting, arguments: ProcessInfo.processInfo.arguments)
    }
    static func enabled(configured: Bool?, isUITesting: Bool, arguments: [String]) -> Bool {
        if isUITesting && arguments.contains("-qaStitchRecipeDetailOff") { return false }
        return configured ?? true
    }
}
