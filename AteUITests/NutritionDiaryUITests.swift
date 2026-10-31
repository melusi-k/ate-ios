import XCTest

final class NutritionDiaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// SwiftUI Lists materialise below-fold cells in the accessibility hierarchy, and on this
    /// platform isHittable also accepts cells clipped by the sheet's navigation bar or pushed
    /// past the keyboard; taps synthesised at those centres land on the bar or the keyboard
    /// instead of the control (CI evidence: sourceName accepted at y=57.7-62.7, centre inside
    /// the nav-bar band; nutrient.energy accepted with its centre off the bottom edge). Scroll
    /// against the measured frame until the element's centre sits inside the clear band
    /// between the top bar and the keyboard before tapping.
    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, max: Int = 12) -> Bool {
        let topBound: CGFloat = 112 // below the inline navigation bar in these sheets/screens
        var attempts = 0
        var blockedUps = 0
        while attempts < max {
            attempts += 1
            guard element.exists, !element.frame.isEmpty else {
                // Unmaterialised targets in these flows have always been below the fold.
                app.swipeUp(velocity: .slow)
                continue
            }
            let frame = element.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardUp = keyboard.exists
            let bottomBound = keyboardUp ? keyboard.frame.minY - 8 : app.windows.firstMatch.frame.maxY - 4
            if frame.midY >= topBound && frame.midY <= bottomBound {
                if element.isHittable { return true }
                app.swipeDown(velocity: .slow) // nudge within the band and re-measure
            } else if frame.midY > bottomBound {
                if keyboardUp && blockedUps >= 2 {
                    // At the form's end the target cannot rise past the keyboard by scrolling;
                    // drag down once to dismiss it interactively, then re-measure.
                    app.swipeDown(velocity: .fast)
                    blockedUps = 0
                } else {
                    app.swipeUp(velocity: .slow)
                    blockedUps += 1
                }
            } else {
                app.swipeDown(velocity: .slow)
                blockedUps = 0
            }
        }
        return element.exists && element.isHittable
    }

    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication, _ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(scrollToHittable(element, in: app), message ?? "Element should be visible before it is tapped", file: file, line: line)
        element.tap()
    }

    /// Typing before the keyboard finishes its appear animation can drop characters on a
    /// loaded CI simulator. Wait for the keyboard before sending text. When the keyboard was
    /// already up for a previous field, its existence proves nothing about this field's focus,
    /// so a tap that missed (bar/keyboard overlap) is re-centred and retried once before typing.
    private func typeAfterKeyboard(_ element: XCUIElement, in app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let keyboardWasUp = app.keyboards.firstMatch.exists
        tapWhenHittable(element, in: app, file: file, line: line)
        if !keyboardWasUp {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the focused field", file: file, line: line)
        }
        // Retry signal only, never a gate: the keyboard-focus attribute is read when the
        // platform reports it, and an unknown/nil answer simply proceeds to the typeText
        // below, which remains the asserted interaction. A false reading costs one re-centre
        // and re-tap, not a spurious failure.
        if keyboardWasUp, (element.value(forKey: "hasKeyboardFocus") as? Bool) == false {
            _ = scrollToHittable(element, in: app)
            element.tap()
        }
        element.typeText(text)
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
        typeAfterKeyboard(foodName, in: app, "My lunch")
        typeAfterKeyboard(app.textFields["nutritionDiary.quantityUnit"], in: app, "bowl")
        let sourceName = app.textFields["nutritionDiary.sourceName"]
        typeAfterKeyboard(sourceName, in: app, "My notes")
        let sourcePicker = app.descendants(matching: .any)["nutritionDiary.source"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 5))
        tapWhenHittable(sourcePicker, in: app)
        let externalSource = app.buttons["External record (not verified by Ate)"]
        XCTAssertTrue(externalSource.waitForExistence(timeout: 5))
        externalSource.tap()
        XCTAssertNotEqual(sourceName.value as? String, "You")
        XCTAssertNotEqual(sourceName.value as? String, "My notes")
        typeAfterKeyboard(sourceName, in: app, "Test food database")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)

        XCTAssertTrue(diaryRows(app, containing: "My lunch").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unavailable"].firstMatch.exists)
    }

    /// Shared navigation: Settings tab -> Food diary screen.
    private func openDiary(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        XCTAssertTrue(diaryEntry.waitForExistence(timeout: 10), "Settings should expose Food diary")
        tapWhenHittable(diaryEntry, in: app)
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
        typeAfterKeyboard(foodName, in: app, "Bad entry")
        let quantity = app.textFields["nutritionDiary.quantity"]
        tapWhenHittable(quantity, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the quantity field")
        if let existing = quantity.value as? String {
            quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        quantity.typeText("0")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)
        // Error state: visible message, and the form stays open for correction. If the error
        // section renders outside the materialised cells, scroll it into the hierarchy.
        let formError = app.descendants(matching: .any)["nutritionDiary.formError"]
        XCTAssertTrue(scrollToHittable(formError, in: app) || formError.waitForExistence(timeout: 3), "Save error should be visible")
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
        typeAfterKeyboard(foodName, in: app, "My lunch")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)
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
        XCTAssertTrue(app.buttons["nutritionDiary.retryGoals"].waitForExistence(timeout: 5))
    }

    func testRecipeNutritionShowsIncompleteStateForUnmappedIngredient() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaNutritionFixtures"]
        app.launch()
        // Tap the card button itself: tapping the inner label text synthesises an event that
        // does not reach the button's action on a loaded simulator, so the sheet never presents.
        let card = app.buttons.matching(identifier: "listCard")
            .matching(NSPredicate(format: "label CONTAINS %@", "QA pap and rice")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Seeded recipe should appear in the library")
        tapWhenHittable(card, in: app, "Seeded recipe card should be visible before it is tapped")
        // Library cards open a compact sheet; the nutrition card lives in the expanded detail.
        // The sheet's internal controls are not reliably exposed to accessibility (see
        // test32c_ExpandableRecipeSheetOpensExpandsAndDismisses), so accept a detail that is
        // already expanded as well as the compact sheet's expand button.
        let expand = app.buttons["expandRecipeDetails"]
        let nutritionCard = app.descendants(matching: .any)["recipeNutrition"]
        var presentationWait = 0.0
        while !expand.exists && !nutritionCard.exists && presentationWait < 10 {
            Thread.sleep(forTimeInterval: 0.5)
            presentationWait += 0.5
        }
        if expand.exists && !nutritionCard.exists {
            expand.tap()
        }
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
        typeAfterKeyboard(foodName, in: app, "My lunch")
        typeAfterKeyboard(app.textFields["nutritionDiary.quantityUnit"], in: app, "bowl")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)

        let row = diaryRows(app, containing: "My lunch").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(row, in: app), "Saved entry row should be visible before it is swiped")
        row.swipeLeft()
        app.buttons["Edit"].tap()
        // Edit mode: seeded values, Edit title.
        XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 5))
        let quantity = app.textFields["nutritionDiary.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        tapWhenHittable(quantity, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the quantity field")
        if let existing = quantity.value as? String {
            quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        quantity.typeText("2")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)
        XCTAssertTrue(diaryRows(app, containing: "2 bowl").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(diaryRows(app, containing: "My lunch").allElementsBoundByIndex.count, 1,
                       "edit must keep one row with the same identity")
        // Merge-gate evidence: keep a screenshot of the edited diary row in the xcresult.
        scrollToHittable(row, in: app)
        let editShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editShot.name = "diary-row-after-edit"
        editShot.lifetime = .keepAlways
        add(editShot)
    }

    func testThisWeekSectionShowsTotalsForLoggedEntries() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)

        let weeklyEmpty = app.staticTexts["Nothing logged this week yet."]
        var scrolls = 0
        while !weeklyEmpty.exists && scrolls < 8 {
            app.swipeUp(velocity: .slow)
            scrolls += 1
        }
        XCTAssertTrue(weeklyEmpty.waitForExistence(timeout: 5), "This week empty state should be reachable")

        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        XCTAssertTrue(foodName.waitForExistence(timeout: 5))
        typeAfterKeyboard(foodName, in: app, "Week lunch")
        let energy = app.textFields["nutritionDiary.nutrient.energy"]
        // The nutrient fields sit below the fold; scroll until the field is genuinely
        // visible before typing, or the tap is swallowed and the keyboard never focuses.
        typeAfterKeyboard(energy, in: app, "200")
        tapWhenHittable(app.buttons["nutritionDiary.save"], in: app)

        let weeklyEnergy = app.staticTexts["nutritionDiary.weeklyTotal.energy.value"]
        scrolls = 0
        while !weeklyEnergy.exists && scrolls < 8 {
            app.swipeUp(velocity: .slow)
            scrolls += 1
        }
        XCTAssertTrue(weeklyEnergy.waitForExistence(timeout: 5), "This week section should list an energy total")
        XCTAssertEqual(weeklyEnergy.label, "200 kcal")
        XCTAssertFalse(app.staticTexts["Nothing logged this week yet."].exists)
        // Merge-gate evidence: keep a screenshot of the populated This week section.
        scrollToHittable(weeklyEnergy, in: app)
        let weeklyShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        weeklyShot.name = "this-week-section-populated"
        weeklyShot.lifetime = .keepAlways
        add(weeklyShot)
    }
}
