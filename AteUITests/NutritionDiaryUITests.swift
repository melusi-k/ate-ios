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

        XCTAssertTrue(diaryRows(app, containing: "My lunch").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unavailable"].firstMatch.exists)
    }

    /// Shared navigation: Settings tab -> Food diary screen.
    private func openDiary(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        var attempts = 0
        while !(diaryEntry.exists && diaryEntry.isHittable) && attempts < 8 {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(diaryEntry.waitForExistence(timeout: 10), "Settings should expose Food diary")
        diaryEntry.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10), "Food diary screen should open")
    }

    private func openLogForm(_ app: XCUIApplication) {
        let accessoryAdd = app.buttons["accessoryAdd"].firstMatch
        if accessoryAdd.waitForExistence(timeout: 2) {
            accessoryAdd.tap()
        } else {
            app.buttons["nutritionDiary.add"].tap()
        }
        XCTAssertTrue(app.textFields["nutritionDiary.foodName"].waitForExistence(timeout: 5), "Log form should open")
    }

    /// Diary entry rows carry a per-entry identifier; scope presence, absence and swipe
    /// queries to actual rows so a matching label elsewhere cannot satisfy or void them.
    private func diaryRows(_ app: XCUIApplication, containing label: String) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "nutritionDiary.entry."))
            .matching(NSPredicate(format: "label CONTAINS %@", label))
    }

    func testDiaryShowsGoalPromptWhenGoalsUnconfiguredAndEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary", "-resetNutritionGoals"]
        app.launch()
        openDiary(app)
        // Goal-unconfigured and empty states are both visible without any setup.
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.configureGoals"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing logged"].exists)
    }

    func testLogFoodRejectsNonPositiveQuantityWithVisibleError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        foodName.tap()
        foodName.typeText("Bad entry")
        let quantity = app.textFields["nutritionDiary.quantity"]
        quantity.tap()
        if let existing = quantity.value as? String {
            quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        quantity.typeText("0")
        app.buttons["nutritionDiary.save"].tap()
        // Error state: visible message, and the form stays open for correction.
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.formError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Enter a quantity and servings greater than zero."].exists)
        XCTAssertTrue(app.buttons["nutritionDiary.save"].exists)
    }

    func testLogFoodSurfacesSaveFailure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary", "-failDiarySaves"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        foodName.tap()
        foodName.typeText("My lunch")
        app.buttons["nutritionDiary.save"].tap()
        // Save-failure state: the diary-level error is shown. The entry exists only in memory,
        // so after a relaunch without the fault argument the diary is empty again.
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.error"].waitForExistence(timeout: 5))
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-UITesting"]
        relaunched.launch()
        openDiary(relaunched)
        XCTAssertTrue(diaryRows(relaunched, containing: "My lunch").allElementsBoundByIndex.isEmpty,
                      "a failed save must not persist the entry")
        XCTAssertTrue(relaunched.staticTexts["Nothing logged"].exists)
    }

    func testCorruptDiaryShowsErrorAndRecoversAfterBackupReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-seedCorruptNutritionDiary"]
        app.launch()
        openDiary(app)
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.corruptDataError"].waitForExistence(timeout: 5))
        app.buttons["nutritionDiary.recoverCorruptData"].tap()
        let confirm = app.buttons["Back up and reset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.recoveryNotice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing logged"].waitForExistence(timeout: 5))
    }

    func testCorruptGoalsShowLoadErrorWithRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary", "-seedCorruptNutritionGoals"]
        app.launch()
        openDiary(app)
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.goalsLoadError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nutritionDiary.retryGoals"].exists)
    }

    func testRecipeNutritionShowsIncompleteStateForUnmappedIngredient() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaNutritionFixtures"]
        app.launch()
        let card = app.staticTexts["QA pap and rice"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Seeded recipe should appear in the library")
        card.tap()
        // Library cards open a compact sheet; the nutrition card lives in the expanded detail.
        let expand = app.buttons["expandRecipeDetails"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "Compact recipe sheet should offer expand")
        expand.tap()
        let nutrition = app.descendants(matching: .any)["recipeNutrition"]
        var scrolls = 0
        while !(nutrition.exists && nutrition.isHittable) && scrolls < 8 {
            app.scrollViews.firstMatch.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5), "Recipe detail should show the nutrition card")
        XCTAssertTrue(app.staticTexts["Nutrition estimate unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No verified food match: pap"].exists)
    }

    func testLoggedEntryCanBeEditedAndShowsUpdatedValues() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        foodName.tap()
        foodName.typeText("My lunch")
        app.textFields["nutritionDiary.quantityUnit"].tap()
        app.textFields["nutritionDiary.quantityUnit"].typeText("bowl")
        app.buttons["nutritionDiary.save"].tap()

        let row = diaryRows(app, containing: "My lunch").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Edit"].tap()
        // Edit mode: seeded values, Edit title.
        XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 5))
        let quantity = app.textFields["nutritionDiary.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        if let existing = quantity.value as? String {
            quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        quantity.typeText("2")
        app.buttons["nutritionDiary.save"].tap()
        XCTAssertTrue(diaryRows(app, containing: "2 bowl").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(diaryRows(app, containing: "My lunch").allElementsBoundByIndex.count, 1,
                       "edit must keep one row with the same identity")
    }
}
