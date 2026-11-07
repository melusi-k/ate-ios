import XCTest

/// Captures the existing user-facing Food Diary route, NOT the unactivated canonical QA view.
/// Does not reset, seed or save diary records. All sheets are cancelled after inspection.
final class NutritionProductionControlsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExistingFoodDiaryControlsAndSourceMenu() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let diary = app.descendants(matching: .any)["settings.nutritionDiary"].firstMatch
        for _ in 0..<10 {
            if diary.exists && diary.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(diary.exists && diary.isHittable)
        diary.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
        let add = app.buttons["nutritionDiary.add"]
        XCTAssertTrue(add.exists && add.isEnabled)
        // This screen has a Log food action, not a generic overflow menu.
        shot("production-food-diary-controls")
        add.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["nutritionDiary.foodName"].exists)
        shot("production-food-diary-log-form")
        let source = app.descendants(matching: .any)["nutritionDiary.source"].firstMatch
        for _ in 0..<8 {
            if source.exists && source.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(source.exists && source.isHittable)
        source.tap()
        // Assert the actual opened picker actions, not only a route or closed form.
        XCTAssertTrue(app.buttons["Entered by you"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Recipe snapshot"].exists)
        XCTAssertTrue(app.buttons["External record (not verified by Ate)"].exists)
        shot("production-food-diary-source-menu")
        app.buttons["Entered by you"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 5))
    }
}
