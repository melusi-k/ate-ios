import XCTest

final class InsightsReorderAccessibilityUITests: XCTestCase {
    func testReorderArrowsHaveFortyFourPointTargetsAndKeepBoundarySemantics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let shortcut = app.buttons["library.todayJournalHub"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10)); shortcut.tap()
        let edit = app.buttons["insights.order.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); edit.tap()
        let up = app.buttons["insights.order.up.tracker"]
        let down = app.buttons["insights.order.down.tracker"]
        for arrow in [up, down] {
            XCTAssertTrue(arrow.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(arrow.frame.width, 44)
            XCTAssertGreaterThanOrEqual(arrow.frame.height, 44)
        }
        XCTAssertEqual(up.label, "Move Cooking tracker up")
        XCTAssertEqual(down.label, "Move Cooking tracker down")
        let startedAtTop = !up.isEnabled
        if startedAtTop {
            XCTAssertTrue(down.isEnabled); XCTAssertTrue(down.isHittable); down.tap()
            XCTAssertTrue(up.isEnabled, "Moving down must make the up action available")
            up.tap()
            XCTAssertFalse(up.isEnabled, "The inverse move must restore the first boundary")
        } else {
            XCTAssertTrue(up.isHittable); up.tap()
            XCTAssertTrue(down.isEnabled, "Moving up must make the down action available")
            down.tap()
            XCTAssertEqual(up.isEnabled, !startedAtTop, "Restore the user's previous position")
        }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "insights-reorder-44pt-controls"; image.lifetime = .keepAlways; add(image)
        edit.tap()
        XCTAssertFalse(up.exists, "Done must hide reorder controls")
    }
}
