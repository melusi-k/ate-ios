import XCTest

final class ExploreUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        if name.contains("testExploreDismissPreservesSelectedCollection") {
            app.launchArguments += ["-qaExploreRetentionSaved"]
        } else if name.contains("testExploreDismissPreservesCollectionAndSearchQuery") {
            app.launchArguments += ["-qaExploreRetentionSaved", "-qaExploreRetentionFavourites"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["library.explore"].waitForExistence(timeout: 20))
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; app.terminate() }
    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    private func open() {
        app.buttons["library.explore"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["explore.source"].exists)
    }
    private func libraryFromDetail() {
        // RecipeDetailView uses NavigationStack's system Back, not the legacy
        // BackBar component. Match the existing system-back regression journey.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.buttons["library.explore"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Cook mode"].exists, "System Back must leave recipe detail")
    }
    private func saveRecipe() {
        app.buttons["Add recipe"].tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].waitForExistence(timeout: 10))
        app.buttons["Prompt"].tap()
        let prompt = app.textViews["promptEditor"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap(); prompt.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap()
        XCTAssertTrue(app.buttons["Cook mode"].waitForExistence(timeout: 10))
        libraryFromDetail()
    }
    func testExploreLocalSourceAndDismissPreservesLibrary() {
        open(); shot("explore-local-discovery-portrait")
        app.buttons["explore.done"].tap()
        XCTAssertTrue(app.buttons["library.explore"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Explore"].exists)
    }
    func testLandscapeExploreRemainsReadableAndDismisses() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["library.explore"].waitForExistence(timeout: 10))
        open()
        let done = app.buttons["explore.done"]
        XCTAssertTrue(done.isHittable)
        shot("explore-local-discovery-landscape")
        done.tap()
        XCTAssertTrue(app.buttons["library.explore"].waitForExistence(timeout: 10))
    }
    func testEmptyExploreAddHandoffUsesExistingAddRecipe() {
        open()
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
        XCTAssertTrue(app.buttons["explore.add"].isHittable)
        shot("explore-empty-add-available")
        app.buttons["explore.add"].tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Explore"].exists)
        XCTAssertTrue(app.textFields["linkField"].waitForExistence(timeout: 5))
        shot("explore-empty-add-handoff")
    }
    func testExploreSelectionOpensSavedRecipePreviewAndDetail() {
        saveRecipe(); open()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore.recipe.quick."))
        XCTAssertEqual(cards.count, 1, "One saved mock recipe in quick discovery")
        cards.element(boundBy: 0).tap()
        let title = app.staticTexts["recipeQuickLookTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.localizedCaseInsensitiveContains("Miso salmon"))
        XCTAssertFalse(app.navigationBars["Explore"].exists)
        shot("explore-selected-recipe-preview")
        app.buttons["expandRecipeDetails"].tap()
        XCTAssertTrue(app.segmentedControls["servingsPicker"].waitForExistence(timeout: 10))
        shot("explore-selected-recipe-detail")
    }
    /// Menu coverage has its own budget, not the Search retention test's budget.
    func testExploreDismissPreservesSelectedCollection() {
        app.buttons["libraryBrowseMenu"].tap()
        let menu = app.collectionViews.containing(NSPredicate(format: "label == %@", "Collections")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let favourite = menu.buttons.matching(NSPredicate(format: "label == %@", "Favourites"))
        XCTAssertEqual(favourite.count, 1)
        favourite.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 10))
        open(); shot("explore-menu-selected-collection")
        app.buttons["explore.done"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 10))
    }

    func testExploreDismissPreservesCollectionAndSearchQuery() {
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let keyboard = app.keyboards.firstMatch
        // A keyboard may already exist while Search is still acquiring focus.
        // XCTest exposes keyboard ownership through this iOS-only attribute,
        // not a public Swift property. Fail closed if the runner lacks it.
        let focusSelector = NSSelectorFromString("hasKeyboardFocus")
        XCTAssertTrue(search.responds(to: focusSelector),
                      "This runner must expose Search keyboard focus")
        let readyForInput = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let field = object as? XCUIElement,
                  field.responds(to: focusSelector),
                  (field.value(forKey: "hasKeyboardFocus") as? Bool) == true else { return false }
            return keyboard.exists
        }, object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [readyForInput], timeout: 5), .completed,
                       "Search must own keyboard focus before entering the query")
        search.typeText("miso")
        // typeText returning and a visible keyboard do not guarantee that the
        // final character has reached Search's accessibility value. Wait for
        // this single input event to settle; never retype or accept a prefix.
        let fullQuery = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "miso"), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [fullQuery], timeout: 5), .completed,
                       "Search must finish receiving the single typed query")
        shot("explore-search-query-before-submit")
        XCTAssertEqual(search.value as? String, "miso",
                       "The full Search query must land before testing retention")
        search.typeText("\n")
        XCTAssertEqual(search.value as? String, "miso",
                       "Submitting Search must keep the full query before opening Explore")
        shot("explore-search-query-before-library")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 10))
        open(); shot("explore-over-filtered-library")
        app.buttons["explore.done"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "miso", "Explore must not clear the Search tab query")
        shot("explore-dismiss-keeps-search-query")
    }
}
