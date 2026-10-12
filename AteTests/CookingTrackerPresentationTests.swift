import XCTest
@testable import Ate

final class CookingTrackerPresentationTests: XCTestCase {
    func testDeletedRecipeUsesClearFallbackLabel() {
        XCTAssertEqual(
            CookingTrackerPresentation.recipeTitle(for: "deleted-recipe-id", recipes: []),
            "Recipe no longer in your library"
        )
    }
}
