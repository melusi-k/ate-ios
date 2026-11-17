import XCTest
@testable import Ate

final class CookPlanRecipeChoicesTests: XCTestCase {
    private func recipe(_ id: String, _ title: String) -> RecipeCard {
        var c = RecipeCard(title: title); c.id = id; return c
    }
    func testChooserUsesExistingRecipesOnlyAndStableTitleOrder() {
        let b = recipe("b", "Soup"), a = recipe("a", "Soup"), fish = recipe("f", "Fish")
        XCTAssertEqual(CookPlanRecipeChoices.matches([b, a, fish], query: "").map(\.id), ["f", "a", "b"])
        XCTAssertEqual(CookPlanRecipeChoices.matches([], query: "Fish"), [])
    }
    func testQueryTrimsAndMatchesTitleWithoutChangingStoredRecipe() {
        let original = recipe("x", "Miso salmon")
        XCTAssertEqual(CookPlanRecipeChoices.matches([original], query: " SALMON ").map(\.id), ["x"])
        XCTAssertTrue(CookPlanRecipeChoices.matches([original], query: "chicken").isEmpty)
        XCTAssertEqual(original.title, "Miso salmon")
    }
}
