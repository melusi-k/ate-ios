import XCTest
@testable import Ate

@MainActor
final class RecipeToolSearchTests: XCTestCase {
    private let recipes = [
        RecipeCard(id: "ccr", title: "Classic Chicken and Rice"),
        RecipeCard(id: "fr", title: "Fried Rice"),
        RecipeCard(id: "mog", title: "Mogodu")
    ]

    func testSearchReturnsOnlyRankedSavedRecipeTitles() {
        XCTAssertEqual(
            RecipeToolSearch.matchingTitles(in: recipes, query: "Mogodu"),
            ["Mogodu"]
        )
    }

    func testAmbiguousSearchDoesNotSelectFirstRecipe() {
        let hits = RecipeToolSearch.matchingTitles(in: recipes, query: "rice")
        XCTAssertEqual(Set(hits), ["Classic Chicken and Rice", "Fried Rice"])
        XCTAssertNil(RecipeToolSearch.confidentMatch(in: recipes, query: "rice"))
        XCTAssertEqual(
            Set(RecipeToolSearch.ambiguousTitles(in: recipes, query: "rice")),
            ["Classic Chicken and Rice", "Fried Rice"]
        )
    }

    func testUnrelatedSearchReturnsNoRecipeAndNoAmbiguity() {
        XCTAssertTrue(RecipeToolSearch.matchingTitles(in: recipes, query: "lasagne").isEmpty)
        XCTAssertNil(RecipeToolSearch.confidentMatch(in: recipes, query: "lasagne"))
        XCTAssertTrue(RecipeToolSearch.ambiguousTitles(in: recipes, query: "lasagne").isEmpty)
    }

    func testExactRecipeNameResolvesConfidently() {
        XCTAssertEqual(
            RecipeToolSearch.confidentMatch(in: recipes, query: "Mogodu")?.id,
            "mog"
        )
    }
}
