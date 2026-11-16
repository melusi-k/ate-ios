import XCTest

/// Opt-in normal-text captures using the existing CoverageUITests prompt/save and Library routes.
/// Dedicated selector, never added to a standard lane.
final class CookGoldenCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["ATE_COOK_GOLDENS"] == "1" else {
            throw XCTSkip("Manual Cook golden workflow only")
        }
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
    }
    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"] + extra
        app.launch()
    }
    private func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
    }
    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    private func addPrompt(_ prompt: String) {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe")); app.buttons["Prompt"].tap()
        let editor = app.textViews["promptEditor"]
        wait(editor); editor.tap(); editor.typeText(prompt)
        app.buttons["generateButton"].tap()
        XCTAssertTrue(text("Review your card").waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap(); wait(app.buttons["Cook mode"])
    }
    private func tab(_ name: String) {
        for _ in 0..<4 where !app.tabBars.firstMatch.exists {
            let custom = app.buttons["backBar"]
            let back = custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)
            wait(back); XCTAssertTrue(back.isHittable); back.tap()
        }
        let tab = app.tabBars.buttons[name]
        wait(tab); XCTAssertTrue(tab.isHittable); tab.tap()
    }
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<25 where !(element.exists && element.isHittable) { app.swipeUp() }
    }
    private func goldenCook(_ name: String) {
        let cook = app.buttons["Cook mode"]
        wait(cook)
        XCTAssertEqual(app.buttons.matching(identifier: "Cook mode").count, 1)
        XCTAssertTrue(cook.isHittable)
        XCTAssertGreaterThanOrEqual(cook.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(cook.frame), "Entire Cook button must remain on screen")
        shot(name)
    }

    private func goldenSheet(large: Bool) {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        addPrompt("Miso salmon for two")
        tab("Library")
        let card = app.buttons["listCard"].firstMatch
        wait(card); scrollTo(card); XCTAssertTrue(card.isHittable); card.tap()
        let expand = app.buttons["expandRecipeDetails"]
        wait(expand); expand.tap()
        wait(app.segmentedControls["servingsPicker"])
        let fully = app.buttons["recipeSheet.expandFully"]
        wait(fully)
        XCTAssertTrue(fully.isHittable, "Medium detent must expose its explicit large-detent control")
        if large {
            fully.tap()
            XCTAssertTrue(fully.waitForNonExistence(timeout: 5), "Large detent must remove Expand fully")
        }
        goldenCook(large ? "cook-golden-large" : "cook-golden-medium")
        let scroll = app.scrollViews["recipe.detail.scroll"]
        wait(scroll)
        scroll.swipeUp()
        goldenCook(large ? "cook-golden-large-midscroll" : "cook-golden-medium-midscroll")
        goldenFinalAsk(scroll, name: large ? "cook-golden-large-finalAsk" : "cook-golden-medium-finalAsk")
        app.buttons["recipeSheet.close"].tap()
        XCTAssertTrue(expand.waitForNonExistence(timeout: 5))
    }

    private func goldenFinalAsk(_ scroll: XCUIElement, name: String) {
        let ask = app.textFields["askField"]
        let cook = app.buttons["Cook mode"]
        // Scroll the mounted detail, never the sheet chrome or an underlying Library.
        for _ in 0..<12 {
            if ask.exists && ask.isHittable && ask.frame.maxY <= cook.frame.minY { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(ask.exists && ask.isHittable, "Final Ask field must be reachable")
        XCTAssertLessThanOrEqual(ask.frame.maxY, cook.frame.minY, "Final content must clear floating Cook")
        XCTAssertFalse(ask.frame.intersects(cook.frame))
        goldenCook(name)
    }

    func testCookGoldenMediumDetent() { goldenSheet(large: false) }
    func testCookGoldenLargeDetent() { goldenSheet(large: true) }
    func testCookGoldenPushedDetail() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        addPrompt("Miso salmon for two")
        XCTAssertFalse(app.buttons["recipeSheet.close"].exists, "Prompt/save route must remain pushed, not a sheet")
        goldenCook("cook-golden-pushed")
        let scroll = app.scrollViews["recipe.detail.scroll"]
        wait(scroll); scroll.swipeUp()
        goldenCook("cook-golden-pushed-midscroll")
        goldenFinalAsk(scroll, name: "cook-golden-pushed-finalAsk")
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of"))
        shot("cook-golden-pushed-opened-cook")
    }
}
