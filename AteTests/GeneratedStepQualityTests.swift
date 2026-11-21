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

final class AdvisoryGapRepairContracts: XCTestCase {
    /// Passes the unchanged structure rules (>=3 ingredients, >=3 steps, timed+cued
    /// heat steps, consistent total) so the ONLY shortfall items are the unused
    /// oil/salt staples.
    private func stapleCard() -> RecipeCard {
        RecipeCard(title: "Beef and rice", servings: 4, timeMinutes: 25,
                   ingredients: ["beef", "rice", "tomatoes", "onion", "oil", "salt", "water"].map { .init(name: $0, quantity: 1, unit: "pcs") },
                   steps: [.init(order: 1, instruction: "Brown the beef and onion over medium heat until golden, 5 min", timeSeconds: 300),
                           .init(order: 2, instruction: "Add the rice, tomatoes and water, cover and simmer until the rice is tender, 20 min", timeSeconds: 1200),
                           .init(order: 3, instruction: "Fluff with a fork and serve", timeSeconds: nil)],
                   source: .appleIntelligence)
    }
    /// Same shape, but the unused items are oil (staple) and beef (main ingredient).
    private func mainIngredientCard() -> RecipeCard {
        RecipeCard(title: "Chicken and rice", servings: 4, timeMinutes: 25,
                   ingredients: ["chicken", "rice", "tomatoes", "onion", "oil", "water", "beef"].map { .init(name: $0, quantity: 1, unit: "pcs") },
                   steps: [.init(order: 1, instruction: "Brown the chicken and onion over medium heat until golden, 5 min", timeSeconds: 300),
                           .init(order: 2, instruction: "Add the rice, tomatoes and water, cover and simmer until the rice is tender, 20 min", timeSeconds: 1200),
                           .init(order: 3, instruction: "Fluff with a fork and serve", timeSeconds: nil)],
                   source: .appleIntelligence)
    }

    func testProducedStapleGapMatchesTheAdvisoryClassifierByteExactly() {
        let gap = GeneratedStepQuality.issues(stapleCard()).first { $0.contains("oil") && $0.contains("never used") }
        XCTAssertNotNil(gap)
        XCTAssertEqual(gap, "Explain when to use oil; \(GeneratedStepQuality.unusedIngredientGapSuffix)")
        XCTAssertTrue(gap.map(GeneratedStepQuality.isImplicitStapleGap) == true)
    }

    func testAdvisoryOnlyGapListNeverTriggersTheAutomaticRepairPass() {
        let gaps = RecipeQuality.shortfall(stapleCard())
        XCTAssertFalse(gaps.isEmpty, "advisory gaps still exist")
        XCTAssertTrue(gaps.allSatisfy(GeneratedStepQuality.isImplicitStapleGap),
                      "fixture must pass the unchanged structure rules: \(gaps)")
        XCTAssertTrue(RecipeQuality.gapsNeedingRepair(gaps).isEmpty,
                      "advisory-only gaps must not spend a second generation")
    }

    func testUnusedMainIngredientKeepsAutomaticRepair() {
        let gaps = RecipeQuality.shortfall(mainIngredientCard())
        XCTAssertTrue(gaps.contains(where: { $0.contains("beef") && $0.contains("never used") }))
        XCTAssertFalse(GeneratedStepQuality.isImplicitStapleGap("Explain when to use beef; \(GeneratedStepQuality.unusedIngredientGapSuffix)"))
        let repair = RecipeQuality.gapsNeedingRepair(gaps)
        XCTAssertTrue(repair.contains(where: { $0.contains("beef") }), "an unused main ingredient still repairs automatically")
        XCTAssertFalse(repair.contains(where: { $0.contains("oil") }), "the staple item is the only one filtered")
    }

    func testEveryListedStapleIsAdvisoryAndMainsAreNot() {
        for staple in GeneratedStepQuality.implicitStaples {
            XCTAssertTrue(GeneratedStepQuality.isImplicitStapleGap("Explain when to use \(staple); \(GeneratedStepQuality.unusedIngredientGapSuffix)"), staple)
        }
        for main in ["beef", "rice", "chicken", "tomatoes", "spinach", "pasta"] {
            XCTAssertFalse(GeneratedStepQuality.isImplicitStapleGap("Explain when to use \(main); \(GeneratedStepQuality.unusedIngredientGapSuffix)"), main)
        }
        XCTAssertTrue(GeneratedStepQuality.isImplicitStapleGap("Explain when to use olive oil; \(GeneratedStepQuality.unusedIngredientGapSuffix)"),
                      "olive oil is on the closed advisory list")
        XCTAssertFalse(GeneratedStepQuality.isImplicitStapleGap("Explain when to use extra virgin olive oil; \(GeneratedStepQuality.unusedIngredientGapSuffix)"),
                       "exact normalized names only: compounds beyond the list are not advisory")
    }

    func testClassifierNormalizesCaseAndWhitespace() {
        XCTAssertTrue(GeneratedStepQuality.isImplicitStapleGap("Explain when to use Salt; \(GeneratedStepQuality.unusedIngredientGapSuffix)"))
        XCTAssertTrue(GeneratedStepQuality.isImplicitStapleGap("Explain when to use OLIVE  OIL; \(GeneratedStepQuality.unusedIngredientGapSuffix)"))
    }

    func testCompoundNamesContainingStapleWordsAreNeverAdvisory() {
        // The closed list matches exact normalized names only: a staple word inside a
        // main food name never makes the gap advisory.
        for name in ["chicken in water", "beef stock with salt", "rice flour", "salt beef", "oil for frying"] {
            let gap = "Explain when to use \(name); \(GeneratedStepQuality.unusedIngredientGapSuffix)"
            XCTAssertFalse(GeneratedStepQuality.isImplicitStapleGap(gap), name)
        }
    }

    /// Passes the unchanged structure rules (same shape as stapleCard) so the ONLY
    /// shortfall item is the unused flour.
    private func cakeCard() -> RecipeCard {
        RecipeCard(title: "Vanilla cake", servings: 4, timeMinutes: 35,
                   ingredients: ["flour", "eggs", "sugar", "milk", "butter", "vanilla"].map { .init(name: $0, quantity: 1, unit: "pcs") },
                   steps: [.init(order: 1, instruction: "Cream the butter, eggs, sugar and vanilla over medium heat until pale, 5 min", timeSeconds: 300),
                           .init(order: 2, instruction: "Stir in the milk, cover and bake until the top springs back, 30 min", timeSeconds: 1800),
                           .init(order: 3, instruction: "Cool in the tin and serve", timeSeconds: nil)],
                   source: .appleIntelligence)
    }

    func testFlourSugarAndButterAreNotAdvisory() {
        // Flour, sugar and butter are main baking ingredients, not shorthand staples:
        // a cake that never uses its flour must still repair automatically.
        for name in ["flour", "sugar", "butter"] {
            let gap = "Explain when to use \(name); \(GeneratedStepQuality.unusedIngredientGapSuffix)"
            XCTAssertFalse(GeneratedStepQuality.isImplicitStapleGap(gap), name)
        }
        let gaps = RecipeQuality.shortfall(cakeCard())
        let flourGap = gaps.first { $0.contains("flour") && $0.contains("never used") }
        XCTAssertNotNil(flourGap, "fixture must isolate the unused flour gap: \(gaps)")
        XCTAssertTrue(RecipeQuality.gapsNeedingRepair(gaps).contains(where: { $0.contains("flour") }),
                      "a cake missing flour in the method still repairs automatically")
    }

    func testRealGapsStillTriggerTheAutomaticRepairPass() {
        let c = RecipeCard(title: "Rice", ingredients: ["rice", "water", "salt"].map { .init(name: $0, quantity: 1, unit: "pcs") },
                           steps: [.init(order: 1, instruction: "Boil rice in water", timeSeconds: nil)], source: .appleIntelligence)
        let repair = RecipeQuality.gapsNeedingRepair(RecipeQuality.shortfall(c))
        XCTAssertTrue(repair.contains(where: { $0.contains("cooking time") }))
        XCTAssertTrue(repair.contains(where: { $0.contains("doneness cue") }))
    }

    func testReviewCardGapListIsUnchangedByTheRepairPartition() {
        // The user still sees the advisory gaps and the manual Repair button:
        // only the automatic pass is narrowed.
        XCTAssertTrue(RecipeQuality.issues(stapleCard()).contains(where: { $0.contains("oil") && $0.contains("never used") }))
        XCTAssertTrue(RecipeQuality.shortfall(stapleCard()).contains(where: { $0.contains("salt") && $0.contains("never used") }))
    }
}
