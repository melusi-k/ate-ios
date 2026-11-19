import Foundation

/// Presentation derived only from the current editable draft, never OCR calibration.
struct AddRecipeReviewSummary: Equatable {
    let title: String
    let ingredientCount: Int
    let stepCount: Int
    let servings: Int?
    let totalMinutes: Int?

    init(_ recipe: RecipeCard) {
        let trimmed = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Untitled recipe" : trimmed
        ingredientCount = recipe.ingredients.count
        stepCount = recipe.steps.count
        servings = recipe.servings > 0 ? recipe.servings : nil
        totalMinutes = recipe.timeMinutes.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Independent Add screen flag; does not depend on the Library or other Stitch slices.
enum AddRecipeScanFeature {
    static var stitchAddRecipeScanEnabled: Bool {
        enabled(configured: Bundle.main.object(forInfoDictionaryKey: "StitchAddRecipeScanEnabled") as? Bool,
                isUITesting: AppConfig.isUITesting, arguments: ProcessInfo.processInfo.arguments)
    }
    static func enabled(configured: Bool?, isUITesting: Bool, arguments: [String]) -> Bool {
        if isUITesting && arguments.contains("-qaStitchAddRecipeScanOff") { return false }
        return configured ?? true
    }
}
