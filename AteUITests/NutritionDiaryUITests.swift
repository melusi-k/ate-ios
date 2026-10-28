import XCTest

final class NutritionDiaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFoodDiaryOpensAndExplicitlyLogsFoodWithUnavailableValues() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()

        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        var attempts = 0
        while !(diaryEntry.exists && diaryEntry.isHittable) && attempts < 8 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(diaryEntry.waitForExistence(timeout: 10))
        diaryEntry.tap()
        XCTAssertTrue(app.staticTexts["Nothing logged"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unavailable"].firstMatch.exists)

        let accessoryAdd = app.buttons["accessoryAdd"].firstMatch
        if accessoryAdd.waitForExistence(timeout: 2) {
            XCTAssertEqual(accessoryAdd.label, "Log food")
            accessoryAdd.tap()
        } else {
            app.buttons["nutritionDiary.add"].tap()
        }
        let foodName = app.textFields["nutritionDiary.foodName"]
        XCTAssertTrue(foodName.waitForExistence(timeout: 5))
        foodName.tap()
        foodName.typeText("My lunch")
        app.textFields["nutritionDiary.quantityUnit"].tap()
        app.textFields["nutritionDiary.quantityUnit"].typeText("bowl")
        let sourceName = app.textFields["nutritionDiary.sourceName"]
        sourceName.tap()
        sourceName.typeText("My notes")
        let sourcePicker = app.descendants(matching: .any)["nutritionDiary.source"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 5))
        sourcePicker.tap()
        let externalSource = app.buttons["External record (not verified by Ate)"]
        XCTAssertTrue(externalSource.waitForExistence(timeout: 5))
        externalSource.tap()
        XCTAssertNotEqual(sourceName.value as? String, "You")
        XCTAssertNotEqual(sourceName.value as? String, "My notes")
        sourceName.tap()
        sourceName.typeText("Test food database")
        app.buttons["nutritionDiary.save"].tap()

        XCTAssertTrue(app.staticTexts["My lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unavailable"].firstMatch.exists)
    }
}
