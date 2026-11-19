import XCTest

final class StitchCookModeUITests: XCTestCase {
    private func launch(off: Bool = false, landscape: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaSavedRecipeForSheet", "-qaResetCookingHistory", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if off { app.launchArguments += ["-qaStitchCookModeOff"] }
        app.launch()
        let card = app.buttons[landscape ? "gridCard" : "listCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let expand = app.buttons["expandRecipeDetails"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        let cook = app.buttons["Cook mode"]
        XCTAssertTrue(cook.waitForExistence(timeout: 5)); cook.tap()
        XCTAssertTrue(app.staticTexts["cookStepText"].waitForExistence(timeout: 5))
        return app
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, earlier: Bool = false) {
        let scroll = app.scrollViews["cook.stitch.scroll"]
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if earlier { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    func testOnStepScrollKeepsExplicitNavigationTimerAndResume() {
        let app = launch()
        XCTAssertTrue(app.scrollViews["cook.stitch.scroll"].exists)
        XCTAssertEqual(app.staticTexts["cook.stitch.recipeTitle"].label, "Miso salmon for two")
        XCTAssertFalse(app.otherElements["voicePanel"].exists)
        XCTAssertTrue(app.buttons["voiceToggle"].label.contains("Start voice control"))
        app.buttons["cookNextStep"].tap(); app.buttons["cookNextStep"].tap()
        let start = app.buttons["Start timer"]
        reveal(start, in: app)
        XCTAssertTrue(start.exists, "A timed step must not start automatically")
        start.tap()
        let pause = app.buttons["Pause timer"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        shot("stitch-cook-on-explicit-running-timer")
        let exit = app.buttons["Exit"]
        app.scrollViews["cook.stitch.scroll"].swipeDown()
        reveal(exit, in: app, earlier: true); exit.tap()
        let cook = app.buttons["Cook mode"]
        XCTAssertTrue(cook.waitForExistence(timeout: 5)); cook.tap()
        XCTAssertTrue(app.staticTexts["cookStepText"].label.contains("Step 3 of 4"))
        reveal(pause, in: app)
        XCTAssertTrue(pause.exists, "Exit/reentry must not pause a running timer")
        app.buttons["cookNextStep"].tap()
        XCTAssertTrue(app.buttons["cookFinish"].exists)
        XCTAssertTrue(app.buttons["cookFinish"].isHittable)
        shot("stitch-cook-on-final-explicit-finish-ready")
    }
    func testOffRetainsOriginalStepWithoutNewScrollSurface() {
        let app = launch(off: true)
        XCTAssertFalse(app.scrollViews["cook.stitch.scroll"].exists)
        XCTAssertFalse(app.staticTexts["cook.stitch.recipeTitle"].exists)
        XCTAssertTrue(app.buttons["cookNextStep"].isHittable)
        app.buttons["cookNextStep"].tap()
        XCTAssertTrue(app.staticTexts["cookStepText"].label.contains("Step 2 of 4"))
        shot("stitch-cook-off-original-step")
    }
    func testLandscapeFullInstructionCanScrollAbovePinnedFooter() {
        let app = launch(landscape: true)
        XCTAssertTrue(app.scrollViews["cook.stitch.scroll"].exists)
        let text = app.staticTexts["cookStepText"]
        reveal(text, in: app)
        XCTAssertTrue(text.label.contains("Heat the oven to 200"))
        XCTAssertTrue(text.label.contains("line a tray."))
        let next = app.buttons["cookNextStep"]
        XCTAssertTrue(next.isHittable)
        for _ in 0..<6 where text.frame.maxY > next.frame.minY {
            app.scrollViews["cook.stitch.scroll"].swipeUp()
        }
        XCTAssertLessThanOrEqual(text.frame.maxY, next.frame.minY, "Instruction must scroll fully above pinned actions")
        shot("stitch-cook-landscape-full-instruction-clear-of-footer")
        next.tap()
        XCTAssertTrue(app.buttons["Back"].isEnabled)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["cookStepText"].label.contains("Step 1 of 4"))
    }
}
