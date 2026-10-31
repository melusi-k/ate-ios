import XCTest

/// Cook Mode ingredient checklist sheet: opens from a cook step, shows amounts scaled to the
/// servings factor chosen on the recipe detail, rescales in place, and keeps gathered checks
/// for the life of the cook session (including leaving and resuming Cook Mode).
final class CookIngredientsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"] + extra
        app.launch()
        return app
    }

    func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Prompt flow ends on the recipe detail with the deterministic mock card
    /// (2 servings; rice 150 g; garlic "2 cloves — finely chopped"; 4 steps).
    func addPromptRecipe() {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        wait(text("Review your card"), 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
    }

    func testCookIngredientSheetScalesChecksAndPersists() {
        launch()
        addPromptRecipe()

        // Choose 2x servings on the detail; Cook Mode must inherit that factor.
        let detailPicker = app.segmentedControls["servingsPicker"]
        wait(detailPicker, 5)
        detailPicker.buttons["2×"].tap()

        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))

        let open = app.buttons["cookIngredientsButton"]
        wait(open, 5)
        open.tap()
        wait(app.buttons["cookIngredientsDone"], 5)
        shot("cook-ingredients-sheet")

        // The sheet pins the current step's instruction above the list (metric units here).
        let currentStep = app.descendants(matching: .any)["cookIngredientsCurrentStep"]
        wait(currentStep, 5)
        XCTAssertTrue(currentStep.label.contains("Step 1 of 4"), currentStep.label)
        XCTAssertTrue(currentStep.label.contains("Heat the oven to 200"), currentStep.label)

        // Amounts reflect the detail factor: rice 150 g x 2, notes preserved.
        let rice = app.buttons["cookIngredient.4"]
        wait(rice, 5)
        XCTAssertTrue(rice.label.contains("300 g"), rice.label)
        XCTAssertTrue(rice.label.contains("rice"), rice.label)
        let garlic = app.buttons["cookIngredient.3"]
        XCTAssertTrue(garlic.label.contains("finely chopped"), garlic.label)

        // VoiceOver content: each row announces amount + name (label) and gathered state (value).
        XCTAssertEqual(rice.value as? String, "Not gathered")
        // Check the first row (always on screen), close, reopen: the session keeps the check.
        let first = app.buttons["cookIngredient.0"]
        wait(first, 5)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44, "row tap target too small")
        first.tap()
        wait(text("1 of 5 gathered"), 5)
        XCTAssertEqual(first.value as? String, "Gathered")
        app.buttons["cookIngredientsDone"].tap()
        wait(text("Step 1 of 4"), 5)
        open.tap()
        wait(text("1 of 5 gathered"), 5)

        // Rescaling inside the sheet updates amounts: rice 150 g x 3.
        let sheetPicker = app.segmentedControls["cookServingsPicker"]
        wait(sheetPicker, 5)
        sheetPicker.buttons["3×"].tap()
        let rice3 = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "cookIngredient.4", "450 g")).firstMatch
        wait(rice3, 5)
        shot("cook-ingredients-sheet-3x")
        app.buttons["cookIngredientsDone"].tap()

        // Leaving Cook Mode and re-entering from the detail keeps the check, and the active
        // session owns its factor: the in-sheet 3x survives re-entry (the detail's 2x applies
        // only to a genuinely new session).
        app.buttons["Exit"].tap()
        wait(app.buttons["Cook mode"], 5)
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"), 5)
        open.tap()
        wait(text("1 of 5 gathered"), 5)
        let rice2 = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "cookIngredient.4", "450 g")).firstMatch
        wait(rice2, 5)
        app.buttons["cookIngredientsDone"].tap()

        // The pinned instruction follows the cook screen's current step.
        wait(text("Step 1 of 4"), 5)
        app.buttons["cookNextStep"].tap()
        wait(text("Step 2 of 4"), 5)
        open.tap()
        let stepTwo = app.descendants(matching: .any)["cookIngredientsCurrentStep"]
        wait(stepTwo, 5)
        XCTAssertTrue(stepTwo.label.contains("Step 2 of 4"), stepTwo.label)
        XCTAssertTrue(stepTwo.label.contains("Mix miso, honey and garlic"), stepTwo.label)
        app.buttons["cookIngredientsDone"].tap()
    }

    /// Accessibility evidence at an accessibility text size, with imperial units: rows keep
    /// name + quantity + gathered state, stay tappable without clipping, and the sheet scrolls.
    func testCookIngredientSheetLargeTextAccessibilityAndImperial() {
        launch(["-UITestLargeText", "-qaImperialUnits"])
        addPromptRecipe()

        let detailPicker = app.segmentedControls["servingsPicker"]
        wait(detailPicker, 5)
        detailPicker.buttons["2\u{00D7}"].tap()

        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        let open = app.buttons["cookIngredientsButton"]
        wait(open, 5)
        open.tap()
        wait(app.buttons["cookIngredientsDone"], 5)
        shot("cook-ingredients-sheet-large-text")

        // The pinned current-step header is readable at this size and shows imperial units.
        let stepHeader = app.descendants(matching: .any)["cookIngredientsCurrentStep"]
        wait(stepHeader, 5)
        XCTAssertTrue(stepHeader.label.contains("Step 1 of 4"), stepHeader.label)
        XCTAssertTrue(stepHeader.label.contains("390"), stepHeader.label)
        shot("cook-ingredients-sheet-with-instruction-large-text")

        // First row: full VoiceOver content and a usable tap target at accessibility size.
        let first = app.buttons["cookIngredient.0"]
        wait(first, 5)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44, "row tap target too small at AX text size")
        XCTAssertEqual(first.value as? String, "Not gathered")
        first.tap()
        wait(text("1 of 5 gathered"), 5)
        XCTAssertEqual(first.value as? String, "Gathered")

        // Imperial conversion in the checklist: rice 150 g x 2 renders in ounces.
        // At this text size the last row can be offscreen; scroll the sheet to reach it.
        let scroll = app.scrollViews["cookIngredientsScroll"]
        let riceQuery = NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "cookIngredient.4", "oz")
        var rice = app.buttons.matching(riceQuery).firstMatch
        // A row can exist in the hierarchy while still clipped at the scroll edge, and
        // isHittable alone has proven unreliable; keep scrolling until the row is fully
        // inside the sheet's visible frame and tappable, as a user would.
        let visibleFrame = { scroll.frame.insetBy(dx: 0, dy: -2) }
        for _ in 0..<8 where !(rice.exists && rice.isHittable && visibleFrame().contains(rice.frame)) {
            scroll.swipeUp()
            rice = app.buttons.matching(riceQuery).firstMatch
        }
        wait(rice, 5)
        XCTAssertTrue(rice.label.contains("11 oz"), rice.label)
        XCTAssertTrue(rice.label.contains("rice"), rice.label)
        XCTAssertTrue(rice.isHittable, "rice row not tappable at AX text size")
        XCTAssertTrue(visibleFrame().contains(rice.frame), "rice row not fully within the sheet's visible frame: \(rice.frame) vs \(scroll.frame)")
        shot("cook-ingredients-sheet-large-text-imperial")
    }

    /// Timer pixel evidence at an accessibility text size: step 3 of the mock card carries a
    /// 600 s timer, so Cook Mode shows its timer card there. Captures the card before start
    /// and while running, with the ingredient sheet dismissed.
    func testCookTimerCardLargeText() {
        launch(["-UITestLargeText"])
        addPromptRecipe()

        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        app.buttons["cookNextStep"].tap()
        wait(text("Step 2 of 4"))
        app.buttons["cookNextStep"].tap()
        wait(text("Step 3 of 4"))

        // Timer card before start: 10:00 for the step's 600 s, start control present.
        let value = app.staticTexts["cookTimerValue"]
        wait(value, 5)
        XCTAssertTrue(value.label.contains("10:00"), value.label)
        let start = app.buttons["Start timer"]
        wait(start, 5)
        shot("cook-timer-card-step3-large-text")

        // Running state: control flips to Pause and the value leaves 10:00.
        start.tap()
        wait(app.buttons["Pause timer"], 5)
        shot("cook-timer-running-step3-large-text")
    }
}
