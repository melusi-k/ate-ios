import XCTest
@testable import Ate

final class VerifiedPasteHeadingTests: XCTestCase {
    func testColonlessForAndToHeadingsNeverConsumeAnIngredientSlot() throws {
        for heading in ["To Garnish", "For Garnish", "To Garnish:", "For Garnish:"] {
            let source = VerifiedPasteFixture.trifle.replacingOccurrences(of: "To Garnish", with: heading)
            guard case .verified(let contract) = SourceRecipeFidelity.extraction(source) else { return XCTFail("Source verifies before conversion") }
            let card = try VerifiedPasteImport.card(from: source, contract: contract)
            XCTAssertEqual(contract.ingredients.count, 28)
            XCTAssertEqual(card.ingredients, contract.ingredients)
            XCTAssertEqual(card.steps.count, 27)
            XCTAssertEqual(card.pastedSource?.writtenTime, "40-60 Minutes")
            XCTAssertTrue(card.pastedSource?.ingredientLines.contains(heading + "\n30g chopped toasted hazelnuts") == true)
            XCTAssertTrue(contract.issues(card).isEmpty)
            XCTAssertTrue(card.pastedSource?.matches(card) == true)
            XCTAssertEqual(RecipeLogic.text(for: card), source)
        }
    }
}
