import XCTest
@testable import Ate

final class SourcePreparationBoundaryTests: XCTestCase {
    func testSourceContractKeepsUnpunctuatedPrepInWrittenNames() throws {
        let source = "Vegetables. You need 3 carrots grated, 1 onion diced. Fry onion 5 minutes, stir in carrots, then simmer 20 minutes."
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(source))
        XCTAssertEqual(contract.ingredients.map(\.name), ["carrots grated", "onion diced"])
        XCTAssertEqual(contract.ingredients.map(\.notes), [nil, nil])
        XCTAssertEqual(contract.ingredients.map(\.quantity), [3, 1])
        XCTAssertEqual(contract.ingredients.map(\.unit), ["pcs", "pcs"])
        let card = RecipeCard(title: "Vegetables", ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: contract.method, timeSeconds: nil)], source: .appleIntelligence)
        let normalized = RecipeLogic.normalize(card)
        XCTAssertEqual(normalized.ingredients.map(\.name), ["carrots", "onion"])
        XCTAssertEqual(normalized.ingredients.map(\.notes), ["grated", "diced"])
        XCTAssertTrue(contract.issues(normalized).isEmpty)
        XCTAssertEqual(contract.ingredients.map(\.name), ["carrots grated", "onion diced"], "Source contract is not normalized in place")
    }

    func testBothParserModesRetainQuantityUnitsAndExistingPunctuatedNotes() {
        let raw = "3 carrots grated"
        XCTAssertEqual(IngredientParser.parse(raw, preserveSourceName: true),
                       Ingredient(name: "carrots grated", quantity: 3, unit: "pcs"))
        XCTAssertEqual(IngredientParser.parse(raw),
                       Ingredient(name: "carrots", quantity: 3, unit: "pcs", notes: "grated"))
        let clove = "2 cloves garlic, crushed"
        XCTAssertEqual(IngredientParser.parse(clove, preserveSourceName: true), IngredientParser.parse(clove))
        XCTAssertEqual(IngredientParser.parse("1 onion diced"),
                       Ingredient(name: "onion", quantity: 1, unit: "pcs", notes: "diced"))
    }
}
