import XCTest
@testable import Ate

final class AchariIngredientIdentityTests: XCTestCase {
    private var screenshot: RecipeCard {
        var card = RecipeCard(title: "Achari Murgh", servings: 6, timeMinutes: 66,
            ingredients: [.init(name: "chicken pieces", quantity: 1.2, unit: "kg", notes: "cut into chunks"),
                          .init(name: "diced", quantity: 1, unit: "onion", notes: "chopped"),
                          .init(name: "garlic", quantity: 2, unit: "cloves", notes: "crushed"),
                          .init(name: "curry powder", quantity: 2, unit: "tsp"),
                          .init(name: "vegetable oil", quantity: 300, unit: "ml"),
                          .init(name: "water", quantity: 400, unit: "ml"),
                          .init(name: "salt", quantity: 1, unit: "tsp")],
            steps: [.init(order: 1, instruction: "Brown the chicken pieces in oil over medium heat until golden (10 min)", timeSeconds: 600),
                    .init(order: 2, instruction: "Add the onion and garlic to the pot, sauté until soft and fragrant (6 min)", timeSeconds: 360),
                    .init(order: 3, instruction: "Stir in the curry powder and achari paste, then add the water and salt and simmer gently until the chicken is tender and the sauce thickens (40 min)", timeSeconds: 2400)],
            source: .appleIntelligence)
        card.aiConfidence = 0.85
        card.aiNote = "Prep: 10 min."
        return card
    }

    func testExactUnnormalizedScreenshotHasNoFalseOnionGapButFindsMissingPaste() {
        let gaps = GeneratedStepQuality.issues(screenshot)
        XCTAssertFalse(gaps.contains { $0.contains("mentions onion") })
        XCTAssertEqual(gaps.filter { $0.contains("achari paste") }.count, 1)
        XCTAssertTrue(RecipeQuality.needsInput(screenshot), "Real missing paste must still gate Save")
    }

    func testNormalizeMovesFoodFromUnitAndPrepFromNameWithoutInventingFacts() {
        let original = screenshot
        let fixed = RecipeLogic.normalize(original)
        XCTAssertEqual(fixed.ingredients[1], Ingredient(name: "onion", quantity: 1, unit: "pcs", notes: "diced; chopped"))
        XCTAssertEqual(fixed.ingredients.count, original.ingredients.count)
        XCTAssertEqual(fixed.ingredients[0], original.ingredients[0])
        XCTAssertEqual(fixed.steps, original.steps)
        XCTAssertEqual(fixed.aiConfidence, original.aiConfidence)
        XCTAssertFalse(RecipeQuality.issues(fixed).contains { $0.contains("mentions onion") })
        XCTAssertTrue(RecipeQuality.issues(fixed).contains { $0.contains("achari paste") })
        XCTAssertTrue(RecipeQuality.needsInput(fixed))
        XCTAssertEqual(RecipeLogic.normalize(fixed).ingredients, fixed.ingredients, "Normalization must be idempotent")
    }

    func testRawOnionParsingSeparatesUnpunctuatedPrepAndKeepsCloveMeasure() {
        XCTAssertEqual(IngredientParser.parse("1 onion diced"), Ingredient(name: "onion", quantity: 1, unit: "pcs", notes: "diced"))
        XCTAssertEqual(IngredientParser.parse("1 onion, diced"), Ingredient(name: "onion", quantity: 1, unit: "pcs", notes: "diced"))
        XCTAssertEqual(IngredientParser.parse("2 cloves garlic, crushed"), Ingredient(name: "garlic", quantity: 2, unit: "cloves", notes: "crushed"))
        let measure = Ingredient(name: "diced", quantity: 1, unit: "cup", notes: "chopped")
        XCTAssertNil(IngredientFieldNormalization.foodInUnit(measure))
        XCTAssertEqual(IngredientFieldNormalization.normalizeGenerated(measure), measure, "Do not invent a food from a measure")
        let ambiguous = Ingredient(name: "garlic", quantity: 1, unit: "onion")
        XCTAssertEqual(IngredientFieldNormalization.normalizeGenerated(ambiguous), ambiguous, "Do not choose between two foods")
    }

    func testUnrelatedRecipesAreNotRewrittenAndPasteMustBeExplicit() throws {
        var manual = screenshot
        manual.source = .manual
        XCTAssertEqual(RecipeLogic.normalize(manual).ingredients, manual.ingredients)
        var fixed = RecipeLogic.normalize(screenshot)
        let original = fixed
        fixed.ingredients.append(.init(name: "achari paste", quantity: 2, unit: "tbsp"))
        XCTAssertFalse(GeneratedStepQuality.issues(fixed).contains { $0.contains("achari paste") })
        XCTAssertNoThrow(try RecipeDraftRepair.accept(fixed, replacing: original))
        fixed.ingredients[fixed.ingredients.count - 1].name = "curry paste"
        XCTAssertTrue(GeneratedStepQuality.issues(fixed).contains { $0.contains("achari paste") }, "Another paste is not achari paste")
        fixed.steps[2].instruction = "Stir the sauce into a smooth paste, then simmer for 40 minutes until tender."
        XCTAssertFalse(GeneratedStepQuality.issues(fixed).contains { $0.contains("mentions smooth paste") })
    }
}
