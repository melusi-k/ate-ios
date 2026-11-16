import XCTest
@testable import Ate

final class PhotoDraftHonestyTests: XCTestCase {
    func testLowConfidencePhotoDropsCuisineAndTagsWithoutChangingRecipeOrConfidence() {
        var card = RecipeCard(title: "Orange juice", tags: ["main", "south african"], source: .photoGuess)
        card.cuisine = "South African"; card.aiConfidence = 0.2
        card.aiNote = "Uncertain photo"; card.aiAlternatives = ["Fruit drink"]
        let result = PhotoDraftHonesty.apply(card)
        XCTAssertNil(result.cuisine); XCTAssertTrue(result.tags.isEmpty)
        var expected = card
        expected.cuisine = nil; expected.tags = []
        expected.aiNote = "Uncertain photo\n\n" + PhotoDraftHonesty.omittedMetadataNote
        XCTAssertEqual(result, expected)
        XCTAssertEqual(PhotoDraftHonesty.apply(result), result, "No repeated note on another pass")
    }
    func testAtThresholdPhotoRetainsItsMetadata() {
        var card = RecipeCard(title: "Chakalaka", tags: ["side"], source: .photoGuess)
        card.cuisine = "South African"; card.aiConfidence = RecipeQuality.threshold
        XCTAssertEqual(PhotoDraftHonesty.apply(card), card)
    }
    func testOtherSourcesAreUntouchedEvenAtLowConfidence() {
        for source in RecipeSource.allCases where source != .photoGuess {
            var card = RecipeCard(title: "Source recipe", tags: ["main"], source: source)
            card.cuisine = "Italian"; card.aiConfidence = 0.1
            XCTAssertEqual(PhotoDraftHonesty.apply(card), card, source.rawValue)
        }
    }
    func testAlreadyEmptyMetadataNeedsNoNewNote() {
        var card = RecipeCard(title: "Drink", source: .photoGuess)
        card.aiConfidence = 0.2
        XCTAssertEqual(PhotoDraftHonesty.apply(card), card)
    }
    func testMissingConfidenceDoesNotRewriteHistoricalPhotoCards() {
        var card = RecipeCard(title: "Juice", tags: ["drink"], source: .photoGuess)
        card.cuisine = "Unspecified"
        XCTAssertNil(card.aiConfidence)
        XCTAssertEqual(PhotoDraftHonesty.apply(card), card)
    }
    func testSpreadQuestionDoesNotClaimThereAreDefinitelySeveralDishes() {
        let error = PhotoNeedsDishError(suggestions: ["Drink", "Soup"], spread: true)
        XCTAssertEqual(error.errorDescription, "There may be more than one dish here. Tell ate what you want to make, or choose one or more below.")
        XCTAssertTrue(error.spread, "Keep the existing multiple-choice route; change only its certainty")
        XCTAssertFalse(error.errorDescription!.contains("spread of several dishes"))
    }
}
