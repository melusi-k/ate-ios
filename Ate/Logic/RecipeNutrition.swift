import Foundation

/// Canonical nutrient values for the stated reference quantity. Nil means the source did not provide that nutrient.
struct NutritionProfile: Codable, Equatable {
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?
    
    var isComplete: Bool {
        [energyKcal, proteinGrams, carbohydratesGrams, fatGrams, fibreGrams]
            .allSatisfy { value in value.map { $0.isFinite && $0 >= 0 } ?? false }
    }
}

enum NutritionReferenceBasis: String, Codable {
    case grams
    case millilitres
}

enum NutritionVerificationStatus: String, Codable {
    case verified
    case unverified
}

/// A source-backed food record. The calculator refuses unverified records or records whose usage rights
/// have not been reviewed; source metadata travels with the record for auditing.
struct NutritionFoodRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var aliases: [String]
    var preparationState: String
    var referenceQuantity: Double
    var referenceBasis: NutritionReferenceBasis
    var nutrients: NutritionProfile
    var sourceName: String
    var sourceRecordID: String
    var sourceVersion: String
    var verificationStatus: NutritionVerificationStatus
    var usageRightsConfirmed: Bool
}

struct NutritionIngredientContribution: Equatable, Identifiable {
    /// Source recipe-line position keeps repeated ingredient names distinct in SwiftUI.
    let id: Int
    var ingredientName: String
    var nutrients: NutritionProfile
    var sourceDescription: String
}

struct RecipeNutritionResult: Equatable {
    var perServing: NutritionProfile?
    var totalRecipe: NutritionProfile?
    var contributions: [NutritionIngredientContribution]
    var unmappedIngredients: [String]
    var incompleteIngredients: [String]
    var isComplete: Bool { unmappedIngredients.isEmpty && incompleteIngredients.isEmpty && perServing != nil }
}

/// Pure calculator. Only exact curated aliases and explicit, supported unit conversions are accepted.
/// No fuzzy matching, generic density assumptions, or generated nutrient estimates are used.
struct RecipeNutritionCalculator {
    let foods: [NutritionFoodRecord]

    func calculate(_ recipe: RecipeCard) -> RecipeNutritionResult {
        guard recipe.servings > 0 else {
            return RecipeNutritionResult(perServing: nil, totalRecipe: nil, contributions: [],
                                         unmappedIngredients: [], incompleteIngredients: [recipe.title + " (invalid servings)"])
        }

        var totals = NutrientAccumulator()
        var contributions: [NutritionIngredientContribution] = []
        var unmapped: [String] = []
        var incomplete: [String] = []

        for (ingredientIndex, ingredient) in recipe.ingredients.enumerated() {
            guard ingredient.quantity.isFinite, ingredient.quantity > 0 else {
                incomplete.append(ingredient.name)
                continue
            }
            guard let food = findFood(for: ingredient.name),
                  food.verificationStatus == .verified, food.usageRightsConfirmed else {
                unmapped.append(ingredient.name)
                continue
            }
            guard let amount = normalizedAmount(ingredient.quantity, unit: ingredient.unit, food: food),
                  food.referenceQuantity.isFinite, food.referenceQuantity > 0 else {
                incomplete.append(ingredient.name)
                continue
            }
            guard food.nutrients.isComplete else {
                incomplete.append(ingredient.name)
                continue
            }

            let factor = amount / food.referenceQuantity
            guard factor.isFinite, factor > 0 else {
                incomplete.append(ingredient.name)
                continue
            }
            let scaled = Self.scaled(food.nutrients, by: factor)
            guard scaled.isComplete, totals.add(scaled) else {
                incomplete.append(ingredient.name)
                continue
            }
            contributions.append(NutritionIngredientContribution(
                id: ingredientIndex,
                ingredientName: ingredient.name,
                nutrients: scaled,
                sourceDescription: "\(food.sourceName) · \(food.sourceRecordID) · \(food.preparationState)"
            ))
        }

        // Partial sums are intentionally not exposed as recipe totals: that would look like a complete estimate.
        guard unmapped.isEmpty, incomplete.isEmpty, !recipe.ingredients.isEmpty else {
            return RecipeNutritionResult(perServing: nil, totalRecipe: nil, contributions: contributions,
                                         unmappedIngredients: unmapped, incompleteIngredients: incomplete)
        }
        let total = totals.profile
        let roundedTotal = Self.rounded(total)
        let perServing = Self.rounded(Self.scaled(total, by: 1 / Double(recipe.servings)))
        guard roundedTotal.isComplete, perServing.isComplete else {
            return RecipeNutritionResult(perServing: nil, totalRecipe: nil, contributions: contributions,
                                         unmappedIngredients: [], incompleteIngredients: [recipe.title + " (calculation overflow)"])
        }
        return RecipeNutritionResult(
            perServing: perServing,
            totalRecipe: roundedTotal,
            contributions: contributions,
            unmappedIngredients: [],
            incompleteIngredients: []
        )
    }

    private func findFood(for ingredientName: String) -> NutritionFoodRecord? {
        let query = Self.normalizedName(ingredientName)
        return foods.first { food in
            ([food.name] + food.aliases).contains { Self.normalizedName($0) == query }
        }
    }

    private func normalizedAmount(_ quantity: Double, unit: String, food: NutritionFoodRecord) -> Double? {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let amount: Double?
        switch food.referenceBasis {
        case .grams:
            amount = switch unit {
            case "g", "gram", "grams": quantity
            case "kg", "kilogram", "kilograms": quantity * 1_000
            default: nil
            }
        case .millilitres:
            amount = switch unit {
            case "ml", "millilitre", "millilitres", "milliliter", "milliliters": quantity
            case "l", "litre", "litres", "liter", "liters": quantity * 1_000
            default: nil
            }
        }
        guard let amount, amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    private static func normalizedName(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private static func scaled(_ value: NutritionProfile, by factor: Double) -> NutritionProfile {
        NutritionProfile(
            energyKcal: value.energyKcal.map { $0 * factor },
            proteinGrams: value.proteinGrams.map { $0 * factor },
            carbohydratesGrams: value.carbohydratesGrams.map { $0 * factor },
            fatGrams: value.fatGrams.map { $0 * factor },
            fibreGrams: value.fibreGrams.map { $0 * factor }
        )
    }

    private static func rounded(_ value: NutritionProfile) -> NutritionProfile {
        func r(_ n: Double?) -> Double? {
            n.map { value in
                // Avoid overflowing the intermediate multiplication for very large finite values.
                abs(value) <= Double.greatestFiniteMagnitude / 10
                    ? (value * 10).rounded() / 10
                    : value
            }
        }
        return NutritionProfile(energyKcal: r(value.energyKcal), proteinGrams: r(value.proteinGrams),
                                carbohydratesGrams: r(value.carbohydratesGrams), fatGrams: r(value.fatGrams),
                                fibreGrams: r(value.fibreGrams))
    }
}

private struct NutrientAccumulator {
    private(set) var energyKcal = 0.0
    private(set) var proteinGrams = 0.0
    private(set) var carbohydratesGrams = 0.0
    private(set) var fatGrams = 0.0
    private(set) var fibreGrams = 0.0

    mutating func add(_ p: NutritionProfile) -> Bool {
        let nextEnergy = energyKcal + (p.energyKcal ?? 0)
        let nextProtein = proteinGrams + (p.proteinGrams ?? 0)
        let nextCarbohydrates = carbohydratesGrams + (p.carbohydratesGrams ?? 0)
        let nextFat = fatGrams + (p.fatGrams ?? 0)
        let nextFibre = fibreGrams + (p.fibreGrams ?? 0)
        guard [nextEnergy, nextProtein, nextCarbohydrates, nextFat, nextFibre].allSatisfy({ $0.isFinite }) else {
            return false
        }
        energyKcal = nextEnergy
        proteinGrams = nextProtein
        carbohydratesGrams = nextCarbohydrates
        fatGrams = nextFat
        fibreGrams = nextFibre
        return true
    }

    var profile: NutritionProfile {
        NutritionProfile(energyKcal: energyKcal, proteinGrams: proteinGrams,
                         carbohydratesGrams: carbohydratesGrams, fatGrams: fatGrams, fibreGrams: fibreGrams)
    }
}

