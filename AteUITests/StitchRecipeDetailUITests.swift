import XCTest

final class StitchRecipeDetailUITests: XCTestCase {
    private func launch(off: Bool = false, landscape: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaSavedRecipeForSheet", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if off { app.launchArguments += ["-qaStitchRecipeDetailOff"] }
        app.launch()
        let card = app.buttons[landscape ? "gridCard" : "listCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let expand = app.buttons["expandRecipeDetails"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        XCTAssertTrue(app.segmentedControls["servingsPicker"].waitForExistence(timeout: 5))
        if app.buttons["recipeSheet.expandFully"].exists { app.buttons["recipeSheet.expandFully"].tap() }
        return app
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, earlier: Bool = false) {
        let scroll = app.scrollViews["recipe.detail.scroll"]
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if earlier { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    func testOnHierarchyScalingAndOriginalPlanningSheet() {
        let app = launch()
        let yield = app.descendants(matching: .any)["recipe.detail.yield"].firstMatch
        reveal(yield, in: app, earlier: true)
        XCTAssertTrue(yield.label.contains("2 recipe servings"))
        let servings = app.segmentedControls["servingsPicker"]
        reveal(servings, in: app); servings.buttons["2×"].tap()
        reveal(yield, in: app, earlier: true)
        XCTAssertTrue(yield.label.contains("4 recipe servings"))
        XCTAssertTrue(app.descendants(matching: .any)["recipe.detail.totalTime"].firstMatch.label.contains("21 min total"))
        shot("stitch-detail-on-yield-and-total")
        let ingredients = app.staticTexts["recipe.detail.ingredientCount"]
        reveal(ingredients, in: app)
        XCTAssertEqual(ingredients.label, "5 entries")
        let steps = app.staticTexts["recipe.detail.stepCount"]
        reveal(steps, in: app); XCTAssertEqual(steps.label, "4 steps")
        shot("stitch-detail-on-method-hierarchy")
        let plan = app.buttons["recipe.plan"]
        reveal(plan, in: app); plan.tap()
        XCTAssertTrue(app.navigationBars["Cook this on..."].waitForExistence(timeout: 5))
        shot("stitch-detail-original-plan-sheet")
    }
    func testOffKeepsOriginalDetailAndCookFooter() {
        let app = launch(off: true)
        XCTAssertFalse(app.staticTexts["recipe.detail.ingredientCount"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipe.detail.yield"].firstMatch.exists)
        XCTAssertTrue(app.segmentedControls["servingsPicker"].exists)
        XCTAssertTrue(app.buttons["Cook mode"].isHittable)
        shot("stitch-detail-off-original-footer")
    }
    func testLandscapeHierarchyFooterCollapseAndReturnKeepLibraryContext() {
        let app = launch(landscape: true)
        let metadata = app.descendants(matching: .any)["recipe.detail.yield"].firstMatch
        reveal(metadata, in: app, earlier: true)
        XCTAssertTrue(metadata.exists)
        XCTAssertTrue(app.buttons["Cook mode"].isHittable)
        shot("stitch-detail-landscape-yield-footer")
        app.buttons["recipeSheet.collapse"].tap()
        XCTAssertTrue(app.buttons["expandRecipeDetails"].waitForExistence(timeout: 5))
        app.buttons["expandRecipeDetails"].tap()
        XCTAssertTrue(app.segmentedControls["servingsPicker"].waitForExistence(timeout: 5))
        app.buttons["recipeSheet.close"].tap()
        XCTAssertTrue(app.scrollViews["libraryGrid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gridCard"].firstMatch.exists)
        shot("stitch-detail-return-grid-keeps-saved-recipe")
    }
}
