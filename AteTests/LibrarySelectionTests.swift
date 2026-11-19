import XCTest
@testable import Ate

final class LibrarySelectionTests: XCTestCase {
    private var recipes: [RecipeCard] {
        [RecipeCard(id: "b", title: "Soup", servings: 2, timeMinutes: 40, createdAt: 0),
         RecipeCard(id: "a", title: "Bread", servings: 3, timeMinutes: nil, createdAt: 0)]
    }
    func testSelectionIsExplicitDeterministicAndNeverChangesSavedRecipes() {
        let saved = recipes
        var selection = LibrarySelection()
        selection.toggle("a")
        XCTAssertTrue(selection.selectedIDs.isEmpty)
        selection.enter(); selection.toggle("b"); selection.toggle("a")
        XCTAssertEqual(selection.selectedRecipes(in: saved).map(\.id), ["a", "b"])
        XCTAssertEqual(saved, recipes)
        selection.toggle("a")
        XCTAssertEqual(selection.selectedIDs, ["b"])
        selection.deselectAll()
        XCTAssertTrue(selection.isSelecting); XCTAssertTrue(selection.selectedIDs.isEmpty)
        selection.toggle("a"); selection.cancel()
        XCTAssertFalse(selection.isSelecting); XCTAssertTrue(selection.selectedIDs.isEmpty)
    }
    func testSummaryUsesSavedServingsAndPreservesUnknownTime() {
        var selection = LibrarySelection(); selection.enter()
        selection.toggle("a"); selection.toggle("b")
        let result = selection.summary(in: recipes)
        XCTAssertEqual(result.count, 2); XCTAssertEqual(result.knownServings, 5)
        XCTAssertEqual(result.unknownServingsCount, 0); XCTAssertEqual(result.unknownTimeCount, 1)
        let invalid = [RecipeCard(id: "a", title: "Unknown", servings: 0, timeMinutes: -5)]
        XCTAssertEqual(selection.summary(in: invalid).unknownServingsCount, 1)
        XCTAssertEqual(selection.summary(in: invalid).unknownTimeCount, 1)
        let overflow = [RecipeCard(id: "a", title: "A", servings: Int.max), RecipeCard(id: "b", title: "B", servings: 1)]
        XCTAssertNil(selection.summary(in: overflow).knownServings)
    }
    func testRemovedRecipesArePrunedAndDuplicateIDsNeverInflateSummary() {
        var selection = LibrarySelection(); selection.enter()
        selection.toggle("a"); selection.toggle("b"); selection.toggle("missing")
        XCTAssertEqual(selection.summary(in: recipes + recipes).count, 2)
        selection.reconcile(savedIDs: ["b"])
        XCTAssertEqual(selection.selectedIDs, ["b"])
        XCTAssertEqual(selection.summary(in: recipes).knownServings, 2)
        selection.reconcile(savedIDs: [])
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }
    func testSelectionDoesNotMutateFilterCollectionLayoutOrHiddenSelection() {
        var filter = RecipeFilter()
        filter.collection = .quick
        var layout = LibraryLayout(); layout.group = .cookTime; layout.sort = .az
        let originalFilter = filter, originalLayout = layout
        var selection = LibrarySelection(); selection.enter(); selection.toggle("a")
        // Filtering can hide an ID but cannot silently change the selected share set.
        XCTAssertTrue(filter.apply(recipes, query: "no match").isEmpty)
        XCTAssertEqual(selection.selectedRecipes(in: recipes).map(\.id), ["a"])
        selection.cancel()
        XCTAssertEqual(filter, originalFilter); XCTAssertEqual(layout, originalLayout)
    }
    func testFlagDefaultsOnAndOffFallbackIgnoresProductionQAArguments() {
        XCTAssertTrue(StitchFeatureFlags.libraryMultiSelectEnabled(configured: nil, isUITesting: false, arguments: []))
        XCTAssertFalse(StitchFeatureFlags.libraryMultiSelectEnabled(configured: false, isUITesting: false, arguments: []))
        XCTAssertTrue(StitchFeatureFlags.libraryMultiSelectEnabled(configured: nil, isUITesting: false, arguments: ["-qaStitchLibraryMultiSelectOff"]))
        XCTAssertFalse(StitchFeatureFlags.libraryMultiSelectEnabled(configured: nil, isUITesting: true, arguments: ["-qaStitchLibraryMultiSelectOff"]))
    }
}
