import XCTest
@testable import Ate

final class RecipeDetailMetadataTests: XCTestCase {
    func testScalingYieldKeepsSourceTimeIngredientsAndMethodUnchanged() {
        let original = RecipeCard(id: "original", title: "Soup", servings: 2, timeMinutes: 35,
            ingredients: [.init(name: "beans", quantity: 1, unit: "can")],
            steps: [.init(order: 1, instruction: "Simmer the beans.", timeSeconds: 600)], createdAt: 0)
        let source = original
        let result = RecipeDetailMetadata(original, factor: 3)
        XCTAssertEqual(result.servings, 6); XCTAssertEqual(result.totalMinutes, 35)
        XCTAssertEqual(result.ingredientCount, 1); XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(source, original)
    }
    func testUnknownInvalidYieldAndOverflowStayExplicitWithoutEstimatedTime() {
        var recipe = RecipeCard(servings: 0, timeMinutes: nil,
            steps: [.init(order: 1, instruction: " ", timeSeconds: nil)])
        XCTAssertNil(RecipeDetailMetadata(recipe, factor: 1).servings)
        XCTAssertNil(RecipeDetailMetadata(recipe, factor: 1).totalMinutes)
        XCTAssertEqual(RecipeDetailMetadata(recipe, factor: 1).stepCount, 0)
        recipe.servings = Int.max; recipe.timeMinutes = -1
        XCTAssertNil(RecipeDetailMetadata(recipe, factor: 3).servings)
        XCTAssertNil(RecipeDetailMetadata(recipe, factor: 3).totalMinutes)
        for invalid in [Double.nan, .infinity, -1, 0, 1.5] {
            XCTAssertNil(RecipeDetailMetadata(recipe, factor: invalid).servings)
        }
    }
    func testIndependentFlagDefaultsOnWithExplicitOffAndGuardedQAOverride() {
        XCTAssertTrue(RecipeDetailFeature.enabled(configured: nil, isUITesting: false, arguments: []))
        XCTAssertFalse(RecipeDetailFeature.enabled(configured: false, isUITesting: false, arguments: []))
        XCTAssertTrue(RecipeDetailFeature.enabled(configured: nil, isUITesting: false, arguments: ["-qaStitchRecipeDetailOff"]))
        XCTAssertFalse(RecipeDetailFeature.enabled(configured: nil, isUITesting: true, arguments: ["-qaStitchRecipeDetailOff"]))
    }
}
