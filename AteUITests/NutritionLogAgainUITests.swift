import XCTest

/// Ordinary Settings route, not the dormant canonical diary fixture.
final class NutritionLogAgainUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func openDiary(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let diary = app.buttons["settings.nutritionDiary"]
        reveal(diary, in: app)
        diary.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
    }

    private func openForm(_ app: XCUIApplication) {
        app.buttons["nutritionDiary.add"].tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "nutritionDiary.entry.", "Repeat oats"))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOrdinaryRepeatRequiresSaveCancelKeepsOneAndRelaunchKeepsTwo() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)
        openForm(app)
        XCTAssertFalse(app.buttons["nutritionDiary.frequent.0"].exists)
        let name = app.textFields["nutritionDiary.foodName"]
        name.tap()
        name.typeText("Repeat oats")
        app.navigationBars["Log food"].buttons["nutritionDiary.save"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 5))
        openForm(app)
        app.buttons["nutritionDiary.frequentChoices"].tap()
        let repeatButton = app.buttons["nutritionDiary.frequent.0"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        capture(app, "ordinary-log-again-offer")
        repeatButton.tap()
        XCTAssertEqual(app.textFields["nutritionDiary.foodName"].value as? String, "Repeat oats")
        XCTAssertEqual(app.textFields["nutritionDiary.quantity"].value as? String, "1")
        XCTAssertEqual(app.textFields["nutritionDiary.servings"].value as? String, "1")
        XCTAssertTrue(app.navigationBars["Log food"].exists, "Selecting must not save or dismiss")
        capture(app, "ordinary-log-again-prefilled")
        app.navigationBars["Log food"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 5))
        reveal(rows(app).firstMatch, in: app)
        XCTAssertEqual(rows(app).count, 1, "Cancelling reuse must keep only the original")
        openForm(app)
        app.buttons["nutritionDiary.frequentChoices"].tap()
        app.buttons["nutritionDiary.frequent.0"].tap()
        app.navigationBars["Log food"].buttons["nutritionDiary.save"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 5))
        reveal(rows(app).firstMatch, in: app)
        XCTAssertEqual(rows(app).count, 2, "Explicit Save adds a second identity, not an edit")
        capture(app, "ordinary-log-again-saved-twice")
        app.terminate()
        app.launchArguments = ["-UITesting"]
        app.launch()
        openDiary(app)
        reveal(rows(app).firstMatch, in: app)
        XCTAssertEqual(rows(app).count, 2, "Both entries must survive reload")
        capture(app, "ordinary-log-again-relaunched")
    }
}
