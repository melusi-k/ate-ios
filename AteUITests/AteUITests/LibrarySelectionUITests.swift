import XCTest

final class LibrarySelectionUITests: XCTestCase {
    private func launch(off: Bool = false, landscape: Bool = false, empty: Bool = false, rediscovery: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        if !empty && !rediscovery { app.launchArguments += ["-qaSavedRecipesForGroupSort"] }
        if rediscovery { app.launchArguments += ["-qaLibrarySelectionRediscovery"] }
        if off { app.launchArguments += ["-qaStitchLibraryMultiSelectOff"] }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        let content = app.scrollViews["libraryGrid"].exists ? app.scrollViews["libraryGrid"] : list
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if towardTop { content.swipeDown() } else { content.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testOnSelectToggleDeselectCancelAndOriginalDetailRoute() {
        let app = launch()
        let enter = app.buttons["library.selection.enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20)); enter.tap()
        let first = app.buttons["library.selection.recipe.qa-dogfood-first"]
        let second = app.buttons["library.selection.recipe.qa-dogfood-second"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        reveal(first, in: app); first.tap()
        reveal(second, in: app); second.tap()
        reveal(app.staticTexts["library.selection.count"], in: app, towardTop: true)
        XCTAssertEqual(app.staticTexts["library.selection.count"].label, "2 recipes selected")
        XCTAssertEqual(app.staticTexts["library.selection.servings"].label, "4 total saved recipe servings")
        XCTAssertEqual(first.value as? String, "Selected")
        XCTAssertFalse(app.buttons["expandRecipeDetails"].exists)
        XCTAssertTrue(app.buttons["library.selection.share"].isEnabled)
        shot("library-selection-on-two-saved-recipes")
        app.buttons["library.selection.share"].tap()
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 8) || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2))
        shot("library-selection-native-share-sheet")
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
        else { (activity.exists ? activity : app.navigationBars["UIActivityContentView"]).swipeDown() }
        XCTAssertTrue(app.buttons["library.selection.cancel"].waitForExistence(timeout: 5))
        reveal(first, in: app); first.tap()
        reveal(app.staticTexts["library.selection.count"], in: app, towardTop: true)
        XCTAssertEqual(app.staticTexts["library.selection.count"].label, "1 recipe selected")
        app.buttons["library.selection.deselectAll"].tap()
        XCTAssertEqual(app.staticTexts["library.selection.count"].label, "0 recipes selected")
        XCTAssertFalse(app.buttons["library.selection.share"].isEnabled)
        app.buttons["library.selection.cancel"].tap()
        XCTAssertTrue(enter.exists)
        XCTAssertFalse(app.buttons["library.selection.share"].exists)
        let card = app.buttons.matching(identifier: "listCard").firstMatch
        reveal(card, in: app); card.tap()
        XCTAssertTrue(app.buttons["expandRecipeDetails"].waitForExistence(timeout: 5))
        shot("library-selection-cancel-keeps-original-detail-route")
    }
    func testOffHasOriginalCardsWithoutSelectionControls() {
        let app = launch(off: true)
        XCTAssertTrue(app.buttons.matching(identifier: "listCard").firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["library.selection.enter"].exists)
        let card = app.buttons.matching(identifier: "listCard").firstMatch
        reveal(card, in: app); card.tap()
        XCTAssertTrue(app.buttons["expandRecipeDetails"].waitForExistence(timeout: 5))
        shot("library-selection-off-original-route")
    }
    func testLandscapeSelectionAndAccessibilityLabels() {
        let app = launch(landscape: true)
        XCTAssertTrue(app.scrollViews["libraryGrid"].waitForExistence(timeout: 20), "Landscape must reach the grid surface")
        let enter = app.buttons["library.selection.enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20)); enter.tap()
        let first = app.buttons["library.selection.recipe.qa-dogfood-first"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Zesty tacos")
        XCTAssertEqual(first.value as? String, "Not selected")
        reveal(first, in: app); first.tap()
        let share = app.buttons["library.selection.share"]
        XCTAssertTrue(share.isEnabled); XCTAssertTrue(share.isHittable)
        XCTAssertTrue(app.buttons["library.selection.cancel"].isHittable)
        shot("library-selection-landscape-accessibility")
        XCUIDevice.shared.orientation = .portrait
    }
    func testCollectionWithNoMatchesKeepsSelectionAndCancelPreservesFilter() {
        let app = launch()
        let enter = app.buttons["library.selection.enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20)); enter.tap()
        let first = app.buttons["library.selection.recipe.qa-dogfood-first"]
        reveal(first, in: app); first.tap()
        app.buttons["libraryBrowseMenu"].tap()
        let favourites = app.buttons["library.collection.Favourites"]
        XCTAssertTrue(favourites.waitForExistence(timeout: 5)); favourites.tap()
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["library.selection.count"].label, "1 recipe selected")
        XCTAssertTrue(app.buttons["library.selection.share"].isEnabled)
        shot("library-selection-no-matches-keeps-hidden-selected-recipe")
        app.buttons["library.selection.cancel"].tap()
        XCTAssertTrue(app.staticTexts["No matches"].exists)
        XCTAssertTrue(app.navigationBars["Favourites"].exists)
        XCTAssertFalse(app.buttons["library.selection.share"].exists)
    }
    func testGridSelectionHidesSavedFavouritesAndRecentlyCookedRediscovery() {
        let app = launch(landscape: true, rediscovery: true)
        XCTAssertTrue(app.scrollViews["libraryGrid"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["library.rediscovery.Recently cooked"].exists)
        XCTAssertTrue(app.buttons["library.rediscovery.Favourites"].exists)
        app.buttons["library.selection.enter"].tap()
        XCTAssertFalse(app.buttons["library.rediscovery.Recently cooked"].exists)
        XCTAssertFalse(app.buttons["library.rediscovery.Favourites"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "listCard").firstMatch.exists)
        let first = app.buttons["library.selection.recipe.qa-dogfood-first"]
        XCTAssertEqual(app.buttons.matching(identifier: first.identifier).count, 1)
        reveal(first, in: app); first.tap()
        XCTAssertEqual(first.value as? String, "Selected")
        XCTAssertFalse(app.buttons["expandRecipeDetails"].exists)
        XCTAssertTrue(app.buttons["library.selection.share"].isEnabled)
        shot("library-selection-grid-rediscovery-cannot-bypass-selection")
        app.buttons["library.selection.cancel"].tap()
        XCTAssertTrue(app.buttons["library.rediscovery.Recently cooked"].exists)
        XCTAssertTrue(app.buttons["library.rediscovery.Favourites"].exists)
    }
    func testEmptyLibraryHasNoSelectionOrShare() {
        let app = launch(empty: true)
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["library.selection.enter"].exists)
        XCTAssertFalse(app.buttons["library.selection.share"].exists)
        shot("library-selection-empty-safe-fallback")
    }
}
