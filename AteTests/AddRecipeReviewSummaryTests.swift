import XCTest
@testable import Ate

final class AddRecipeReviewSummaryTests: XCTestCase {
    func testSummaryReadsOnlyCurrentDraftWithoutMutationOrAccuracyClaims() {
        let recipe = RecipeCard(id: "source", title: "  Source soup  ", servings: 4, timeMinutes: 35,
            ingredients: [.init(name: "beans", quantity: 1, unit: "can")],
            steps: [.init(order: 1, instruction: "Simmer the beans.", timeSeconds: 600)], createdAt: 0)
        let original = recipe
        let summary = AddRecipeReviewSummary(recipe)
        XCTAssertEqual(summary.title, "Source soup")
        XCTAssertEqual(summary.ingredientCount, 1); XCTAssertEqual(summary.stepCount, 1)
        XCTAssertEqual(summary.servings, 4); XCTAssertEqual(summary.totalMinutes, 35)
        XCTAssertEqual(recipe, original)
    }
    func testUnknownMetadataStaysUnknownAndCountsAreEntriesNotQuality() {
        let recipe = RecipeCard(title: " \n", servings: 0, timeMinutes: nil,
            ingredients: [.init(name: "", quantity: 0, unit: "")], steps: [])
        let summary = AddRecipeReviewSummary(recipe)
        XCTAssertEqual(summary.title, "Untitled recipe")
        XCTAssertNil(summary.servings); XCTAssertNil(summary.totalMinutes)
        XCTAssertEqual(summary.ingredientCount, 1); XCTAssertEqual(summary.stepCount, 0)
        var edited = recipe; edited.timeMinutes = -1; edited.servings = -4
        XCTAssertNil(AddRecipeReviewSummary(edited).servings)
        XCTAssertNil(AddRecipeReviewSummary(edited).totalMinutes)
        edited.title = "Edited"; edited.ingredients = []; edited.steps = [.init(order: 1, instruction: "Rest.", timeSeconds: nil)]
        XCTAssertEqual(AddRecipeReviewSummary(edited).title, "Edited")
        XCTAssertEqual(AddRecipeReviewSummary(edited).ingredientCount, 0)
        XCTAssertEqual(AddRecipeReviewSummary(edited).stepCount, 1)
    }
    func testIndependentDefaultOnFlagAndExplicitOffIgnoreProductionQAArguments() {
        XCTAssertTrue(AddRecipeScanFeature.enabled(configured: nil, isUITesting: false, arguments: []))
        XCTAssertFalse(AddRecipeScanFeature.enabled(configured: false, isUITesting: false, arguments: []))
        XCTAssertTrue(AddRecipeScanFeature.enabled(configured: true, isUITesting: false, arguments: ["-qaStitchAddRecipeScanOff"]))
        XCTAssertFalse(AddRecipeScanFeature.enabled(configured: nil, isUITesting: true, arguments: ["-qaStitchAddRecipeScanOff"]))
    }
}
