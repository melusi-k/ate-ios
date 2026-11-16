import XCTest
@testable import Ate

final class GeneratedTitleReviewTests: XCTestCase {
    func testRibsWingsConflictOnlyProducesHintAndPreservesDraft() {
        let card = PantryDraftGapTests.screenshot
        XCTAssertEqual(GeneratedTitleReview.warning(card), "The title says wings, but the ingredients and method say ribs. Check which cut is intended; nothing has been renamed.")
        XCTAssertEqual(card.title, "Sticky pork wings")
        XCTAssertTrue(RecipeQuality.issues(card).isEmpty, "This hint is not a new repair gate")
        XCTAssertFalse(RecipeQuality.needsInput(card))
    }

    func testBothDirectionsAndGeneratedSources() {
        var card = PantryDraftGapTests.screenshot
        card.source = .photoGuess
        card.title = "Sticky ribs"
        card.ingredients = [.init(name: "chicken wings", quantity: 1, unit: "kg")]
        card.steps = [.init(order: 1, instruction: "Roast the wings until cooked through")]
        XCTAssertTrue(GeneratedTitleReview.warning(card)?.contains("title says ribs") == true)
        card.source = .manual
        XCTAssertNil(GeneratedTitleReview.warning(card))
    }

    func testAmbiguityAndIngredientsAloneDoNotTriggerWarning() {
        var card = PantryDraftGapTests.screenshot
        card.title = "Ribs and wings"
        XCTAssertNil(GeneratedTitleReview.warning(card))
        card.title = "Sticky pork wings"
        card.ingredients.append(.init(name: "wings", quantity: 1, unit: "kg"))
        XCTAssertNil(GeneratedTitleReview.warning(card))
        card = PantryDraftGapTests.screenshot
        card.steps = [.init(order: 1, instruction: "Roast until tender")]
        XCTAssertNil(GeneratedTitleReview.warning(card))
        card = PantryDraftGapTests.screenshot
        card.title = "Chicken au Poivre"
        XCTAssertNil(GeneratedTitleReview.warning(card))
    }
}
