import XCTest

final class NutritionGoalsUITests: XCTestCase {
    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings should be a first-class tab")
        settings.tap()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, max: Int = 8) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < max {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
    }

    func testGoalsCanBeConfiguredAndClearedFromSettings() {
        let app = launchSettings()
        let entry = app.buttons["settings.nutritionGoals"]
        scrollTo(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Settings should expose Nutrition goals")
        XCTAssertTrue(entry.isHittable, "Nutrition goals should be reachable in the Settings form")
        entry.tap()

        let proteinToggle = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(proteinToggle.waitForExistence(timeout: 10))
        proteinToggle.tap()

        let proteinValue = app.textFields["nutritionGoals.value.protein"]
        XCTAssertTrue(proteinValue.waitForExistence(timeout: 5))
        proteinValue.tap()
        proteinValue.typeText("100")

        let clearAll = app.buttons["nutritionGoals.clearAll"]
        scrollTo(clearAll, in: app)
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()
        XCTAssertFalse(proteinToggle.isSelected, "Clear all should turn off every goal in the draft")
        XCTAssertTrue(app.staticTexts["Clearing goals changes this draft only until you tap Save goals."].exists)

        let save = app.buttons["nutritionGoals.save"]
        scrollTo(save, in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        let reopenedEntry = app.buttons["settings.nutritionGoals"]
        scrollTo(reopenedEntry, in: app)
        reopenedEntry.tap()
        let reopenedProteinToggle = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(reopenedProteinToggle.waitForExistence(timeout: 10))
        XCTAssertFalse(reopenedProteinToggle.isSelected, "Cleared goals should remain cleared after reopening")
    }
}
