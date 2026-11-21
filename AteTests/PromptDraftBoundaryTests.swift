import XCTest
@testable import Ate

final class PromptDraftBoundaryTests: XCTestCase {
    func testOddAndNormalIdeaTextReachPromptUnchangedAndConfirmationIsIncluded() {
        // These test deterministic routing, not real-model success for either input.
        for text in ["Escargot with cheese", "A quick weeknight miso salmon for two"] {
            if case .none = SourceRecipeFidelity.extraction(text) {} else {
                XCTFail("Short ideas must not be misclassified as pasted recipe imports")
            }
            XCTAssertEqual(RecipeIdeaPrompt.build(text, confirmedDish: nil), RecipePrompt.prompt(text))
            XCTAssertEqual(RecipeIdeaPrompt.build(text, confirmedDish: "  \n"), RecipePrompt.prompt(text))
            let confirmed = RecipeIdeaPrompt.build(text, confirmedDish: "  Garlic butter salmon  ")
            XCTAssertTrue(confirmed.hasPrefix(RecipePrompt.prompt(text)))
            XCTAssertTrue(confirmed.contains("The cook confirmed the dish: Garlic butter salmon."))
            XCTAssertTrue(confirmed.contains("Do not substitute a different dish"))
            XCTAssertTrue(confirmed.contains("explain the uncertainty"))
        }
    }

    func testDeviceOvenRemovalIsNotAHeatingStepButActualHeatingStillNeedsTemperature() {
        let removal = "Remove from oven, let cool slightly, then slice and serve warm"
        XCTAssertFalse(RecipeQuality.requiresOvenTemperature(removal))
        XCTAssertFalse(RecipeQuality.requiresOvenTemperature("Take the tray out of the oven and let cool."))
        for instruction in ["Bake the bread until golden.", "Preheat the oven.", "Roast until tender.",
                            "Remove from oven; then bake the next tray.",
                            "Remove from oven, then return to the oven for five minutes."] {
            XCTAssertTrue(RecipeQuality.requiresOvenTemperature(instruction), instruction)
            XCTAssertFalse(RecipeQuality.hasTemperature(instruction))
        }
        XCTAssertTrue(RecipeQuality.requiresOvenTemperature("Bake at 180°C until golden."))
        XCTAssertTrue(RecipeQuality.hasTemperature("Bake at 180°C until golden."))
    }

    private func deviceCard() -> RecipeCard {
        var card = RecipeCard(title: "Unknown dish", description: "A cheese-stuffed bread dish.", servings: 6, timeMinutes: 42,
            ingredients: [.init(name: "bread", quantity: 250, unit: "g"), .init(name: "cheese", quantity: 150, unit: "g"),
                          .init(name: "eggs", quantity: 2, unit: "pcs"), .init(name: "milk", quantity: 30, unit: "ml"),
                          .init(name: "butter", quantity: 2, unit: "tbsp"), .init(name: "salt", quantity: 1, unit: "tsp"),
                          .init(name: "paprika", quantity: 1, unit: "tsp")],
            steps: [.init(order: 1, instruction: "Slice bread into thick pieces and place on a baking tray", timeSeconds: nil),
                    .init(order: 2, instruction: "Mix grated cheese, beaten eggs, milk, salt and paprika in a bowl until well combined (5 min)", timeSeconds: 300),
                    .init(order: 3, instruction: "Spread the cheese mixture evenly over each slice of bread (2 min)", timeSeconds: 120),
                    .init(order: 4, instruction: "Dot the bread with butter and bake at 180°C until golden brown and the cheese is melted, 25 min", timeSeconds: 1500),
                    .init(order: 5, instruction: "Remove from oven, let cool slightly, then slice and serve warm", timeSeconds: nil)],
            source: .appleIntelligence, cuisine: "South African")
        card.aiConfidence = 0.2
        card.aiNote = "Prep: 10 min. Bread is sliced and buttered before baking."
        return card
    }

    func testActualQualityListDoesNotFlagRemovalButStillFlagsUnheatedBake() {
        var card = deviceCard()
        XCTAssertFalse(RecipeQuality.issues(card).contains { $0.contains("gives no temperature") })
        card.steps[3].instruction = "Dot the bread with butter and bake until golden for 25 min"
        XCTAssertTrue(RecipeQuality.issues(card).contains("Step 4 uses the oven but gives no temperature."))
    }

    func testDevice42MinutesIsStepSumPlusExplicitPrepAndConfidenceRemainsLow() {
        let result = RecipeLogic.normalize(deviceCard())
        XCTAssertEqual(result.timeMinutes, 42)
        XCTAssertEqual(result.steps.compactMap(\.timeSeconds).reduce(0, +), 32 * 60)
        XCTAssertFalse(GeneratedRecipeConsistency.issues(result).contains { $0.contains("Total time") })
        XCTAssertEqual(result.title, "Unknown dish")
        XCTAssertEqual(result.aiConfidence, 0.2)
        XCTAssertTrue(RecipeQuality.needsInput(result), "Fixing an oven warning must not force Save")
    }

    func testUnrelatedRepairCannotReplaceTheSelectedDraftOrInflateConfidence() {
        let original = deviceCard()
        var unrelated = original
        unrelated.title = "Escargot with cheese"
        unrelated.aiConfidence = 1
        XCTAssertFalse(RecipeDraftRepair.automaticImproves(unrelated, over: original, labels: []))
        XCTAssertThrowsError(try RecipeDraftRepair.accept(unrelated, replacing: original))
        XCTAssertEqual(original.title, "Unknown dish")
        XCTAssertEqual(original.aiConfidence, 0.2)
    }
}
