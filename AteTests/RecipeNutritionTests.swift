import XCTest
@testable import Ate

final class RecipeNutritionTests: XCTestCase {
    func testCalculatesPerServingAndSupportsExplicitMassConversions() {
        let calculator = RecipeNutritionCalculator(foods: [food()])
        let recipe = RecipeCard(servings: 2, ingredients: [
            Ingredient(name: "dry lentils", quantity: 200, unit: "g", notes: nil)
        ])

        let result = calculator.calculate(recipe)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.totalRecipe?.energyKcal, 704)
        XCTAssertEqual(result.perServing?.energyKcal, 352)
        XCTAssertEqual(result.perServing?.proteinGrams, 24.6)
        XCTAssertEqual(result.perServing?.fibreGrams, 15.8)
    }

    func testKilogramsNormalizeToGrams() {
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "dry lentils", quantity: 0.2, unit: "kg", notes: nil)
        ])
        let result = RecipeNutritionCalculator(foods: [food()]).calculate(recipe)
        XCTAssertEqual(result.totalRecipe?.energyKcal, 704)
    }

    func testUnknownFoodNeverProducesPartialRecipeTotal() {
        let recipe = RecipeCard(servings: 2, ingredients: [
            Ingredient(name: "dry lentils", quantity: 100, unit: "g", notes: nil),
            Ingredient(name: "mystery greens", quantity: 50, unit: "g", notes: nil)
        ])
        let result = RecipeNutritionCalculator(foods: [food()]).calculate(recipe)
        XCTAssertFalse(result.isComplete)
        XCTAssertNil(result.totalRecipe)
        XCTAssertNil(result.perServing)
        XCTAssertEqual(result.unmappedIngredients, ["mystery greens"])
    }

    func testUnsupportedVolumeToMassConversionIsNotGuessed() {
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "dry lentils", quantity: 1, unit: "cup", notes: nil)
        ])
        let result = RecipeNutritionCalculator(foods: [food()]).calculate(recipe)
        XCTAssertNil(result.totalRecipe)
        XCTAssertEqual(result.incompleteIngredients, ["dry lentils"])
    }

    func testUnverifiedFoodOrUnreviewedRightsAreRejected() {
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "dry lentils", quantity: 100, unit: "g", notes: nil)
        ])
        var unverified = food()
        unverified.verificationStatus = .unverified
        XCTAssertEqual(RecipeNutritionCalculator(foods: [unverified]).calculate(recipe).unmappedIngredients,
                       ["dry lentils"])
        var rightsPending = food()
        rightsPending.usageRightsConfirmed = false
        XCTAssertEqual(RecipeNutritionCalculator(foods: [rightsPending]).calculate(recipe).unmappedIngredients,
                       ["dry lentils"])
    }

    func testMissingNutrientAndInvalidQuantityAreReportedAsIncomplete() {
        var missingNutrient = food()
        missingNutrient.nutrients.fibreGrams = nil
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "dry lentils", quantity: 100, unit: "g", notes: nil)
        ])
        XCTAssertEqual(RecipeNutritionCalculator(foods: [missingNutrient]).calculate(recipe).incompleteIngredients,
                       ["dry lentils"])

        let invalid = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "dry lentils", quantity: .nan, unit: "g", notes: nil)
        ])
        XCTAssertEqual(RecipeNutritionCalculator(foods: [food()]).calculate(invalid).incompleteIngredients,
                       ["dry lentils"])
    }

    func testAliasesAreExactAfterNormalization() {
        let recipe = RecipeCard(servings: 1, ingredients: [
            Ingredient(name: "DRY-LENTILS", quantity: 100, unit: "g", notes: nil)
        ])
        XCTAssertTrue(RecipeNutritionCalculator(foods: [food()]).calculate(recipe).isComplete)
    }

    private func food() -> NutritionFoodRecord {
        NutritionFoodRecord(
            id: "test-lentils",
            name: "Lentils, dry",
            aliases: ["dry lentils"],
            preparationState: "dry, uncooked",
            referenceQuantity: 100,
            referenceBasis: .grams,
            nutrients: NutritionProfile(energyKcal: 352, proteinGrams: 24.6,
                                        carbohydratesGrams: 63.1, fatGrams: 1.1, fibreGrams: 15.8),
            sourceName: "Test fixture source",
            sourceRecordID: "fixture-1",
            sourceVersion: "test-version",
            verificationStatus: .verified,
            usageRightsConfirmed: true
        )
    }
}
