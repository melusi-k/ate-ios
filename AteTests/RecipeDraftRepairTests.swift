import XCTest
@testable import Ate

final class RecipeDraftRepairTests: XCTestCase {
    private func missingBread() -> RecipeCard {
        var card = RecipeCard(id: "retained-draft", title: "Tomato bread salad", servings: 2,
            ingredients: [.init(name: "onion", quantity: 1, unit: "pcs"),
                          .init(name: "tomato", quantity: 2, unit: "pcs"),
                          .init(name: "oil", quantity: 1, unit: "tbsp")],
            steps: [.init(order: 1, instruction: "Chop the onion and tomato.", timeSeconds: nil),
                    .init(order: 2, instruction: "Cut the bread into cubes.", timeSeconds: nil),
                    .init(order: 3, instruction: "Toss the onion, tomato and bread with oil.", timeSeconds: nil)],
            source: .appleIntelligence)
        card.aiConfidence = 0.7
        card.favorite = true
        card.coverImage = "fixture.jpg"
        return card
    }

    func testRepairInstructionCarriesExactFailedDraftAndNamedMissingIngredient() throws {
        let card = missingBread()
        let prompt = try RecipeDraftRepair.instruction(for: card)
        XCTAssertTrue(prompt.contains("retained-draft"))
        XCTAssertTrue(prompt.contains("Tomato bread salad"))
        XCTAssertTrue(prompt.contains("bread"))
        XCTAssertTrue(prompt.contains("not in the ingredients"))
        XCTAssertTrue(prompt.contains("not a new recipe"))
    }

    func testMeasuredMissingIngredientFixPreservesIdentityAndDoesNotRaiseConfidence() throws {
        let original = missingBread()
        var candidate = original
        candidate.id = "new-model-id"
        candidate.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        candidate.aiConfidence = 0.99
        candidate.favorite = false
        let result = try RecipeDraftRepair.accept(candidate, replacing: original)
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.createdAt, original.createdAt)
        XCTAssertTrue(result.favorite)
        XCTAssertEqual(result.coverImage, original.coverImage)
        XCTAssertEqual(result.aiConfidence, original.aiConfidence)
        XCTAssertTrue(RecipeQuality.shortfall(result).isEmpty)
    }

    func testSameGapRerollAndNewFailureCannotReplaceOriginal() {
        let original = missingBread()
        XCTAssertThrowsError(try RecipeDraftRepair.accept(original, replacing: original))
        var unrelated = original
        unrelated.title = "Tomato soup"
        unrelated.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        XCTAssertThrowsError(try RecipeDraftRepair.accept(unrelated, replacing: original))
        var traded = original
        traded.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        traded.steps[2].instruction += " Add butter."
        XCTAssertThrowsError(try RecipeDraftRepair.accept(traded, replacing: original))
    }

    func testAutomaticRepairCannotTradeBreadForAnotherGapOrChangeDish() {
        let original = missingBread()
        var fixed = original
        fixed.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        XCTAssertTrue(RecipeDraftRepair.automaticImproves(fixed, over: original, labels: []))
        var traded = fixed
        traded.steps[2].instruction += " Add butter."
        XCTAssertFalse(RecipeDraftRepair.automaticImproves(traded, over: original, labels: []))
        fixed.title = "Different salad"
        XCTAssertFalse(RecipeDraftRepair.automaticImproves(fixed, over: original, labels: []))
    }

    func testNonGeneratedAndGapFreeCardsCannotRequestGenericQualityRewrite() throws {
        var card = missingBread()
        card.source = .manual
        XCTAssertThrowsError(try RecipeDraftRepair.instruction(for: card))
        card.source = .appleIntelligence
        card.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        XCTAssertThrowsError(try RecipeDraftRepair.instruction(for: card))
    }

    func testBunnyChowMissingBreadStaysARealGapUntilMeasuredBreadExists() {
        var card = GeneratedRecipeConsistencyTests.screenshot
        card.steps.append(.init(order: 4, instruction: "Hollow six bread loaves, fill with curry and serve.", timeSeconds: nil))
        XCTAssertTrue(RecipeQuality.shortfall(card).contains { $0.lowercased().contains("bread") })
        card.ingredients.append(.init(name: "bread loaves", quantity: 6, unit: "pcs"))
        XCTAssertFalse(GeneratedRecipeConsistency.issues(card).contains { $0.lowercased().contains("bread") })
    }
}
