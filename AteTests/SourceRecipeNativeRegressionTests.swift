import XCTest
@testable import Ate

final class SourceRecipeNativeRegressionTests: XCTestCase {
    private func source(_ items: String, method: String = "1. Mix and simmer for 20 minutes.") -> String {
        "Chicken Rice Bowl\nIngredients:\n" + items + "\nMethod\n" + method
    }

    func testExplicitSectionMethodsDoNotNeedThreeSocialCaptionKeywords() throws {
        for method in ["1. Mix and simmer for 20 minutes.", "1. Cream the butter and sugar for 5 minutes.\n2. Add the eggs and bake for 30 minutes."] {
            XCTAssertFalse(CaptionAnalysis.hasRecipeSignals(method), "Regression input must hit the old wrong gate")
            let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(source("200 g chicken\n100 g rice", method: method)))
            XCTAssertEqual(contract.ingredients.count, 2)
            XCTAssertEqual(contract.method.trimmingCharacters(in: .whitespacesAndNewlines), method)
        }
        let noAction = source("200 g chicken\n100 g rice", method: "Available for orders. Delivery daily.")
        XCTAssertNil(SourceRecipeFidelity.structuredRecipe(noAction))
        XCTAssertNil(SourceRecipeFidelity.multiPartRecipe(noAction))
    }

    func testFractionPathsRunWithShortExplicitMethod() throws {
        for (token, quantity) in [("1/4", 0.25), ("1 1/2", 1.5), ("¼", 0.25), ("⅓", 0.33)] {
            let contract = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(source("\(token) tsp salt\n200g sugar\n2 eggs")), token)
            XCTAssertEqual(contract.ingredients.first?.quantity, quantity)
        }
        for token in ["1/0", "1 1/0"] {
            XCTAssertNil(SourceRecipeFidelity.multiPartRecipe(source("\(token) tsp salt\n200g sugar\n2 eggs")))
        }
    }

    func testOnlyTerminalExactConversionWidgetPairIsOutsideTheList() throws {
        let items = "200g chicken\n100g rice\nSoy Sauce"
        let pair = "Convert Your Measurements\nView Full Conversion Table"
        let clean = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(source(items)))
        let page = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(source(items + "\n" + pair)))
        XCTAssertEqual(page.ingredients, clean.ingredients)
        XCTAssertEqual(page.ingredients.map(\.name), ["chicken", "rice", "Soy Sauce"])
        for literal in ["Convert Your Measurements", "View Full Conversion Table"] {
            let kept = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(source(items + "\n" + literal)))
            XCTAssertTrue(kept.ingredients.contains { $0.name == literal && $0.quantity == 0 })
        }
        let interior = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(source(pair + "\n" + items)))
        XCTAssertEqual(interior.ingredients.count, 5, "Interior phrases never authorize dropping ingredient rows")
    }

    func testIncompleteMultipartMethodFailsClosedAndCompleteMethodKeepsAllRows() throws {
        let items = "Chicken Sauce\n200g chicken\n100g rice\nSoy Sauce"
        let complete = source(items, method: "1. Mix and simmer for 20 minutes.\n2. Serve with rice.")
        let contract = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(complete))
        XCTAssertEqual(contract.ingredients.count, 4)
        for ending in ["1. Mix and simmer for 20 minutes, then ad", "1. Mix and simmer for 20 minutes.\n2. Serve with ri"] {
            let clipped = source(items, method: ending)
            XCTAssertNil(SourceRecipeFidelity.multiPartRecipe(clipped))
            guard case .unverifiable = SourceRecipeFidelity.extraction(clipped) else {
                return XCTFail("A clipped multipart recipe must not certify or become a creative prompt")
            }
        }
    }
}
