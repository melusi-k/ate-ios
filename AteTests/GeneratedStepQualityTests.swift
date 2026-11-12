import XCTest
@testable import Ate

final class GeneratedStepQualityTests: XCTestCase {
    private func card(_ ingredients: [String], _ steps: [Step], source: RecipeSource = .appleIntelligence) -> RecipeCard {
        RecipeCard(title: "Vegetable curry", ingredients: ingredients.map { .init(name: $0, quantity: 1, unit: "pcs") }, steps: steps, source: source)
    }

    func testListedIngredientNeverUsedIsActionableGap() {
        let c = card(["onions", "garlic", "potatoes"], [.init(order: 1, instruction: "Fry the onion and garlic until golden", timeSeconds: 300)])
        XCTAssertTrue(GeneratedStepQuality.issues(c).contains { $0.contains("potatoes") && $0.contains("never used") })
    }

    func testUnlistedFoodInStepIsReportedNotInvented() {
        let c = card(["onions"], [.init(order: 1, instruction: "Fry the onions in oil until golden, then add tomatoes", timeSeconds: 300)])
        let gaps = GeneratedStepQuality.issues(c)
        XCTAssertTrue(gaps.contains { $0.contains("oil") && $0.contains("not in") })
        XCTAssertTrue(gaps.contains { $0.contains("tomato") && $0.contains("not in") })
        XCTAssertEqual(c.ingredients.count, 1, "Validation must not fabricate ingredient quantities")
    }

    func testCookingNeedsTimeAndDonenessNotJustLongerProse() {
        let missing = card(["rice", "water"], [.init(order: 1, instruction: "Boil rice in water", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(missing).contains { $0.contains("cooking time") })
        XCTAssertTrue(GeneratedStepQuality.issues(missing).contains { $0.contains("doneness cue") })
        let complete = card(["rice", "water"], [.init(order: 1, instruction: "Boil rice in water over low heat for 20 minutes until tender", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(complete).isEmpty)
    }

    func testOvenSettingNeedsTimeButTimedTemperatureKeepsExistingContract() {
        let ovenOnly = card(["chicken"], [.init(order: 1, instruction: "Roast chicken at 180°C", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(ovenOnly).contains { $0.contains("doneness cue") })
        let checked = card(["chicken"], [.init(order: 1, instruction: "Roast chicken until the internal temperature reaches 75°C", timeSeconds: 3600)])
        XCTAssertTrue(GeneratedStepQuality.issues(checked).isEmpty)
    }

    func testCompoundFoodNamesUseTheirHeadWithoutInventingSeparateIngredients() {
        for (ingredient, use) in [("pork ribs", "ribs"), ("chicken wings", "wings"),
                                  ("beef stock", "stock"), ("chicken stock", "stock"),
                                  ("lemon pepper", "pepper")] {
            let c = card([ingredient], [.init(order: 1, instruction: "Add the \(use) and serve", timeSeconds: nil)])
            XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty, ingredient)
        }
        let fullName = card(["beef stock"], [.init(order: 1, instruction: "Add the beef stock and serve", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(fullName).isEmpty)
    }

    func testBrownSugarDoesNotBecomeACookingAction() {
        let c = card(["brown sugar", "garlic"], [.init(order: 1, instruction: "Rub with brown sugar and garlic", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
    }

    func testHeatVerbAfterFifthWordStillNeedsTimeAndCue() {
        let c = card(["pork ribs"], [.init(order: 1, instruction: "Arrange the ribs in the dish, cover and bake", timeSeconds: nil)])
        let gaps = GeneratedStepQuality.issues(c)
        XCTAssertTrue(gaps.contains { $0.contains("cooking time") })
        XCTAssertTrue(gaps.contains { $0.contains("doneness cue") })
    }

    func testExistingGoodRibsWingsFixtureRemainsAccepted() {
        let c = card(["pork ribs", "chicken wings", "lemon pepper", "garlic"], [
            .init(order: 1, instruction: "Rub the ribs with garlic and lemon pepper, cover and bake at 160°C for 2 hours", timeSeconds: nil),
            .init(order: 2, instruction: "Roast the wings at 220 °C until golden and crisp, 30 minutes", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
        XCTAssertTrue(RecipeQuality.issues(c).isEmpty)
    }

    func testNoForcedCookingRestingOrStepCountForColdDish() {
        let c = card(["tomatoes", "cheese"], [.init(order: 1, instruction: "Slice the tomatoes, scatter over the cheese and serve", timeSeconds: nil)])
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
    }

    func testCollectiveUseAndInflectedNamesAreNotFalseUnusedIngredients() {
        let c = card(["tomatoes", "potatoes", "onions"], [.init(order: 1, instruction: "Simmer all ingredients until tender", timeSeconds: 1800)])
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
        let named = card(["tomatoes", "onions"], [.init(order: 1, instruction: "Simmer the tomato and onion until soft", timeSeconds: 1800)])
        XCTAssertTrue(GeneratedStepQuality.issues(named).isEmpty)
    }

    func testImportedAndManualSourceFactsRemainUntouched() {
        for source: RecipeSource in [.manual, .jsonLD, .imported] {
            let c = card(["garlic"], [.init(order: 1, instruction: "Boil rice", timeSeconds: nil)], source: source)
            XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
        }
    }

    func testBunnyScreenshotGetsStepReconciliationGaps() {
        let c = GeneratedRecipeConsistencyTests.screenshot
        let gaps = GeneratedStepQuality.issues(c)
        XCTAssertTrue(gaps.contains { $0.contains("oil") })
        XCTAssertTrue(gaps.contains { $0.contains("water") })
        let prompt = RecipePrompt.retryInstruction(gaps: gaps, visibleLabels: [])
        XCTAssertTrue(prompt.contains("Fill only genuine gaps"))
        XCTAssertTrue(prompt.contains("no filler or invented ingredients"))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func testFullerExamplePassesStepValidation() {
        var c = GenRecipe.exampleMogodu.card; c.source = .appleIntelligence
        XCTAssertTrue(GeneratedStepQuality.issues(c).isEmpty)
        XCTAssertTrue(c.steps.first!.instruction.contains("chop"))
        XCTAssertTrue(c.steps.last!.instruction.contains("serve"))
        XCTAssertEqual(c.steps.compactMap(\.timeSeconds).reduce(0, +), 188 * 60)
    }
    #endif
}
