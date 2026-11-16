import XCTest
@testable import Ate

final class NamedDishProvenanceTests: XCTestCase {
    private let menu = "88 likes, 3 comments - kasi_kitchen on 1 October 2026: \"Saturday special 🔥 Mogodu, ujeqe and morogo R85. Order on WhatsApp 071 234 5678 #mogodu #kasifood @kasi_kitchen\""
    func testOriginalF3MenuRequiresSourceAbsenceNotice() {
        XCTAssertTrue(NamedDishProvenance.needsNotice(source: menu))
    }
    func testMeasuredRecipeAndUnrelatedPromptDoNotGainMenuClaim() {
        for source in ["Mogodu", "Make pasta", "", "Saturday special. Order on WhatsApp", "Mogodu ingredients: 2 cups water. Boil and simmer for 120 minutes. Order the dish on WhatsApp"] {
            XCTAssertFalse(NamedDishProvenance.needsNotice(source: source), source)
        }
    }
    func testNoticePreservesRecipeAndCalibratedDishConfidence() {
        var card = RecipeCard(title: "Mogodu", servings: 4, timeMinutes: 160, tags: ["main"], source: .appleIntelligence)
        card.aiConfidence = 0.9; card.aiNote = "Prep: 10 min"
        card.aiAlternatives = ["Ulusu"]; card.cuisine = "South African"
        let result = NamedDishProvenance.apply(card)
        var expected = card
        expected.aiNote = NamedDishProvenance.notice + "\n\nPrep: 10 min"
        expected.description = NamedDishProvenance.descriptionNotice
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.aiConfidence, card.aiConfidence)
        XCTAssertTrue(result.aiNote!.contains("did not provide a source recipe"))
        XCTAssertEqual(NamedDishProvenance.apply(result), result)
    }
    func testAlreadyLowerConfidenceIsNotInflated() {
        var card = RecipeCard(title: "Mogodu"); card.aiConfidence = 0.2
        XCTAssertEqual(NamedDishProvenance.apply(card).aiConfidence, 0.2)
    }
    func testConfidenceCopyDistinguishesDishNameFromSourceRecipeAccuracy() {
        var card = RecipeCard(title: "Mogodu"); card.aiConfidence = 0.9
        let result = NamedDishProvenance.apply(card)
        let label = NamedDishProvenance.confidenceLabel(0.9, card: result)
        XCTAssertTrue(label.contains("Dish-name confidence 90%"))
        XCTAssertTrue(label.contains("no source recipe"))
        XCTAssertTrue(label.contains("suggestions"))
        XCTAssertFalse(RecipeQuality.shouldAskDish(result, alreadyConfirmed: false),
            "Recipe provenance must not manufacture a new dish-identification question")
    }
    func testMissingConfidenceIsNotInvented() {
        let result = NamedDishProvenance.apply(RecipeCard(title: "Mogodu"))
        XCTAssertNil(result.aiConfidence)
        XCTAssertTrue(result.description!.hasPrefix("Best-effort traditional version"))
    }
    func testTemplateIsNotCopiedFromAdvertAsSourceFacts() {
        XCTAssertFalse(NamedDishProvenance.notice.contains("kasi_kitchen"))
        XCTAssertFalse(NamedDishProvenance.notice.contains("071"))
        XCTAssertTrue(NamedDishProvenance.notice.contains("suggestions to review"))
    }
}
