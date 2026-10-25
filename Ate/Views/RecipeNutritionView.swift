import SwiftUI

struct RecipeNutritionView: View {
    let recipe: RecipeCard

    private var result: RecipeNutritionResult {
        RecipeNutritionCalculator(foods: NutritionFoodCatalogue.records).calculate(recipe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition").font(AteFont.body(17, .semibold))
                Spacer()
                Text("Estimated per serving")
                    .font(AteFont.body(11))
                    .foregroundStyle(Theme.mutedForeground)
            }

            if let profile = result.perServing, result.isComplete {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    nutrient("Energy", value: profile.energyKcal, unit: "kcal", precision: 0)
                    nutrient("Protein", value: profile.proteinGrams, unit: "g")
                    nutrient("Carbohydrates", value: profile.carbohydratesGrams, unit: "g")
                    nutrient("Fat", value: profile.fatGrams, unit: "g")
                    nutrient("Fibre", value: profile.fibreGrams, unit: "g")
                }
                Text("Calculated from verified ingredient records. Actual values may vary by brand and preparation.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                if !result.contributions.isEmpty {
                    DisclosureGroup("Ingredient contributions") {
                        ForEach(result.contributions) { contribution in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contribution.ingredientName).font(AteFont.body(13, .medium))
                                Text(contribution.sourceDescription)
                                    .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }
                    .font(AteFont.body(13, .medium))
                }
            } else {
                Label("Nutrition estimate unavailable", systemImage: "info.circle")
                    .font(AteFont.body(14, .semibold))
                Text(incompleteDescription)
                    .font(AteFont.body(13))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if !result.unmappedIngredients.isEmpty {
                    Text("No verified food match: " + result.unmappedIngredients.joined(separator: ", "))
                        .font(AteFont.body(12))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.incompleteIngredients.isEmpty {
                    Text("Needs a supported quantity or complete nutrient record: " + result.incompleteIngredients.joined(separator: ", "))
                        .font(AteFont.body(12))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardSurface(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeNutrition")
    }

    private var incompleteDescription: String {
        if NutritionFoodCatalogue.records.isEmpty {
            return "Verified food-composition data is not available in this build yet. Ate won't guess nutrient values."
        }
        return "A complete estimate needs verified nutrient data and supported quantities for every ingredient. Partial totals are not presented as a complete recipe estimate."
    }

    @ViewBuilder
    private func nutrient(_ title: String, value: Double?, unit: String, precision: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            if let value, value.isFinite {
                Text("\(value.formatted(.number.precision(.fractionLength(precision == 0 ? 0 : 0...precision)))) \(unit)")
                    .font(AteFont.body(16, .semibold))
                    .monospacedDigit()
            } else {
                Text("Unavailable").font(AteFont.body(14, .medium))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
