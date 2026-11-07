import XCTest
@testable import Ate

final class CookingTrackerPresentationTests: XCTestCase {
    func testDeletedRecipeUsesClearFallbackLabel() {
        XCTAssertEqual(
            CookingTrackerPresentation.recipeTitle(for: "deleted-recipe-id", recipes: []),
            "Recipe no longer in your library"
        )
    }

    func testOnlyLibraryRecipesAreOpenable() {
        var kept = RecipeCard()
        kept.id = "kept-recipe-id"
        var other = RecipeCard()
        other.id = "other-recipe-id"
        XCTAssertTrue(CookingTrackerPresentation.isInLibrary("kept-recipe-id", recipes: [other, kept]),
                      "a recipe still in the library is openable")
        XCTAssertFalse(CookingTrackerPresentation.isInLibrary("deleted-recipe-id", recipes: [other, kept]),
                       "a deleted recipe keeps the plain non-tappable fallback")
        XCTAssertFalse(CookingTrackerPresentation.isInLibrary("deleted-recipe-id", recipes: []))
    }
}
