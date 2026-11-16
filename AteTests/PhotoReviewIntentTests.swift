import XCTest
@testable import Ate

final class PhotoReviewIntentTests: XCTestCase {
    private var screenshot: RecipeCard {
        var c = RecipeCard(title: "Chicken au Poivre", servings: 4, timeMinutes: 17,
            ingredients: [.init(name: "chicken pieces", quantity: 1.2, unit: "kg"),
                          .init(name: "oil", quantity: 2, unit: "tbsp"),
                          .init(name: "black pepper", quantity: 1.5, unit: "tsp"),
                          .init(name: "water", quantity: 200, unit: "ml")],
            steps: [.init(order: 1, instruction: "Sear the chicken pieces in oil over medium heat until browned, 5 min at 180°C.", timeSeconds: 300)], source: .photoGuess)
        c.aiNote = "Prep: 12 min. The pepper is infused in water before adding to the chicken."
        c.aiConfidence = 0.6
        return c
    }

    func testScreenshotTotalIsNotPrepAndMethodDoesNotEndAtSearing() {
        let c = RecipeLogic.normalize(screenshot)
        XCTAssertEqual(c.timeMinutes, 17)
        XCTAssertEqual(GeneratedRecipeConsistency.timeLabels(c), ["Total 17 min", "Prep 12 min", "Cook 5 min"])
        let gaps = GeneratedStepQuality.issues(c)
        XCTAssertTrue(gaps.contains { $0.contains("stops after browning") })
        XCTAssertTrue(gaps.contains { $0.contains("black pepper") && $0.contains("never used") })
        XCTAssertTrue(gaps.contains { $0.contains("water") && $0.contains("never used") })
        XCTAssertTrue(RecipeQuality.needsInput(c), "Low-confidence incomplete generated recipe must remain a draft")
        XCTAssertEqual(c.steps.count, 1, "Flag the gap, never manufacture cooking instructions")
        XCTAssertEqual(c.title, "Chicken au Poivre", "Do not rename the named dish from pixels")
        XCTAssertEqual(c.ingredients, screenshot.ingredients)
    }

    func testFieldCleanupDoesNotGuessMeasuresOrDuplicateCrushed() {
        let garlic = IngredientFieldNormalization.normalizeGenerated(.init(name: "crushed", quantity: 1, unit: "garlic", notes: "crushed"))
        XCTAssertEqual(garlic.name, "garlic")
        XCTAssertEqual(garlic.notes, "crushed")
        XCTAssertEqual(IngredientFieldNormalization.normalizeGenerated(garlic), garlic)
        let thyme = Ingredient(name: "thyme", quantity: 1, unit: "herb", notes: "fresh, chopped")
        XCTAssertEqual(IngredientFieldNormalization.displayUnit(thyme, generated: true), "")
        XCTAssertEqual(thyme.unit, "herb", "Keep uncertain source fields editable; do not invent sprigs")
        var c = screenshot; c.ingredients.append(thyme)
        XCTAssertTrue(GeneratedStepQuality.issues(c).contains { $0.contains("Clarify the measure for thyme") })
        XCTAssertEqual(IngredientFieldNormalization.displayUnit(thyme, generated: false), "herb")
        XCTAssertEqual(IngredientFieldNormalization.preparation("crushed", "finely chopped"), "crushed; finely chopped")
    }

    func testNoForcedExtraStepsForColdDishOrSourceRecipe() {
        var c = screenshot
        c.title = "Tomato salad"; c.steps = [.init(order: 1, instruction: "Slice tomatoes and serve", timeSeconds: nil)]
        XCTAssertFalse(GeneratedStepQuality.issues(c).contains { $0.contains("stops after browning") })
        c = screenshot; c.source = .jsonLD
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
        XCTAssertEqual(GeneratedRecipeConsistency.timeLabels(c), ["Total 17 min"])
        c = screenshot; c.aiNote = "Prep: 10-15 min"
        XCTAssertEqual(GeneratedRecipeConsistency.timeLabels(c), ["Total 17 min"], "Do not guess an ambiguous split")
    }
}
