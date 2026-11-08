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

    /// Explicit caller-owned screen context. Do not infer the active screen from a
    /// global identifier search while another sheet may be present.
    private enum GeometrySurface {
        case settings, diary, library, logFood, editFood

        var navigationTitle: String? {
            switch self {
            case .settings: return "Settings"
            case .diary: return "Food diary"
            case .library: return nil // Library may show a collection title.
            case .logFood: return "Log food"
            case .editFood: return "Edit food"
            }
        }

        var isEntryForm: Bool {
            switch self {
            case .logFood, .editFood: return true
            case .settings, .diary, .library: return false
            }
        }
    }

    /// Bottom edge of the tappable band, measured from the chrome actually on screen: the
    /// floating tab bar and, at tab roots, the Add accessory floating above it. A fixed
    /// offset let rows resting behind that chrome count as reachable - on the CI simulator
    /// the Food diary row's centre sat at y=869, inside the tab bar's 791-874 frame, so the
    /// old maxY-4 bound judged it "in band", the nudge swiped the wrong way and the tap was
    /// intercepted by the bar (CI hierarchy + recording, #179).
    private func bottomClearBound(_ app: XCUIApplication, keyboard: XCUIElement?, surface: GeometrySurface) -> CGFloat {
        var bound = app.windows.firstMatch.frame.maxY - 4
        if let keyboard { bound = min(bound, keyboard.frame.minY - 8) }
        // The verified Log/Edit food navigation stack is a presented sheet. Its
        // keyboard and window bound its content; the underlying tab/accessory are
        // not part of that sheet. Keep both live checks for non-form screens,
        // including pushed diary content where an accessory can still be present.
        if surface.isEntryForm { return bound }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            let frame = tabBar.frame
            if !frame.isEmpty && tabBar.isHittable { bound = min(bound, frame.minY - 4) }
        }
        let accessory = app.buttons["accessoryAdd"]
        if accessory.exists {
            let frame = accessory.frame
            if !frame.isEmpty && accessory.isHittable { bound = min(bound, frame.minY - 4) }
        }
        return bound
    }

    /// Read the element's frame only once it stops moving: two equal reads ~0.2s apart.
    /// XCTest's isHittable is unreliable mid-bounce (CI: sourceName read not-hittable while
    /// fully visible during scroll settling, #179).
    private func settledFrame(of element: XCUIElement) -> CGRect {
        var last = element.frame
        var stable = 0
        var polls = 0
        while stable < 2 && polls < 10 {
            Thread.sleep(forTimeInterval: 0.2)
            let f = element.frame
            if f.equalTo(last) { stable += 1 } else { stable = 0; last = f }
            polls += 1
        }
        return last
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, surface: GeometrySurface, max: Int = 12) -> Bool {
        // Clear band top: measured from the on-screen navigation bar when one is present;
        // the 120pt fallback matches the pinned CI simulator (402x874) inline-bar sheets.
        let navBar: XCUIElement
        if let title = surface.navigationTitle {
            navBar = app.navigationBars[title]
            // A missing expected screen is a miss, never permission to ignore its
            // chrome or use a background navigation bar's geometry.
            guard navBar.exists, !navBar.frame.isEmpty, navBar.isHittable else { return false }
        } else {
            navBar = app.navigationBars.firstMatch
        }
        let navFrame = navBar.exists ? navBar.frame : .zero
        let topBound: CGFloat = !navFrame.isEmpty ? navFrame.maxY + 4 : 120
        var attempts = 0
        var blockedUps = 0
        var blockedInBand = 0
        var dismissedKeyboardForOcclusion = false
        while attempts < max {
            attempts += 1
            // A bounded wait allows a just-inserted SwiftUI row to materialise before
            // choosing a scroll direction. The outer attempt count remains the bound.
            guard element.waitForExistence(timeout: 0.5), !element.frame.isEmpty else {
                // Unmaterialised targets in these flows have always been below the fold.
                app.swipeUp(velocity: .slow)
                continue
            }
            // Never judge mid-bounce: after any scroll the frame must settle before band
            // and hittability are read (CI: not-hittable verdict on a fully visible field
            // during scroll settling fed the sourceName oscillation, #179).
            let frame = settledFrame(of: element)
            // Save is the only navigation-chrome target passed by these journeys.
            // Verify REAL membership in the expected active form navigation bar,
            // not app-wide navigation/toolbar matches for every content button.
            // A coincident content frame is never evidence of chrome membership.
            if element.elementType == .button && element.identifier == "nutritionDiary.save" {
                guard surface.isEntryForm,
                      navBar.buttons["nutritionDiary.save"].exists else { return false }
                return element.isHittable
            }
            let keyboard = app.keyboards.firstMatch
            let keyboardUp = keyboard.exists
            let bottomBound = bottomClearBound(app, keyboard: keyboardUp ? keyboard : nil, surface: surface)
            if frame.midY >= topBound && frame.midY <= bottomBound {
                if element.isHittable { return true }
                blockedInBand += 1
                if keyboardUp && !dismissedKeyboardForOcclusion && blockedInBand >= 3 {
                    // A settled in-band frame that never becomes hittable is a phantom
                    // position: the cell renders under the keyboard while the AX tree
                    // serves its pre-keyboard layout (CI recording: 37s of re-measures on
                    // nutritionDiary.sourceName with the cell hidden, #179). Drop the
                    // keyboard and re-measure against honest geometry. Decimal pads have
                    // no Return key; without one, keep re-measuring and fail with evidence.
                    let returnKey = app.keyboards.buttons["return"]
                    if returnKey.waitForExistence(timeout: 2) {
                        returnKey.tap()
                        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Return should dismiss the keyboard")
                    }
                    dismissedKeyboardForOcclusion = true
                    blockedInBand = 0
                } else {
                    // In band but not tappable after settling: re-measure instead of
                    // swiping. A downward swipe on a sheet whose scroll view is at its
                    // top is the sheet-dismiss gesture (CI: Log-food sheet dismissed
                    // with an orphaned keyboard left over the diary, #179).
                    Thread.sleep(forTimeInterval: 0.3)
                }
            } else if frame.midY > bottomBound {
                if keyboardUp && blockedUps >= 4 {
                    // The form cannot rise the target past the keyboard by scrolling. This
                    // keyboard shows a Return key (CI recording, #179); tap it and require
                    // observable dismissal rather than assuming the gesture works.
                    let returnKey = app.keyboards.buttons["return"]
                    if returnKey.waitForExistence(timeout: 2) {
                        returnKey.tap()
                        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Return should dismiss the keyboard")
                    }
                    blockedUps = 0
                } else {
                    app.swipeUp(velocity: .slow)
                    blockedUps += 1
                }
            } else {
                // Overshot above the band: the scroll view is past its top, so a slow
                // down-swipe scrolls content back and cannot engage sheet dismissal -
                // that only triggers at scroll-top, which overshoot rules out.
                app.swipeDown(velocity: .slow)
            }
        }
        // Exhaustion is a miss: honour the element only when its measured centre is inside
        // the clear band AND it is hittable. isHittable alone is never sufficient - it also
        // reports true for cells clipped by the bar or past the keyboard (the original CI
        // failure shape), so it must not be returned unvalidated.
        guard element.exists, !element.frame.isEmpty, element.isHittable else { return false }
        let finalFrame = element.frame
        let finalKeyboard = app.keyboards.firstMatch
        let finalBottom = bottomClearBound(app, keyboard: finalKeyboard.exists ? finalKeyboard : nil, surface: surface)
        return finalFrame.midY >= topBound && finalFrame.midY <= finalBottom
    }

    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication, surface: GeometrySurface, _ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(scrollToHittable(element, in: app, surface: surface), message ?? "Element should be visible before it is tapped", file: file, line: line)
        element.tap()
    }

    /// Typing before the keyboard finishes its appear animation can drop characters on a
    /// loaded CI simulator. Wait for the keyboard before sending text. When the keyboard was
    /// already up for a previous field, its existence proves nothing about THIS field's focus,
    /// so the typed text is checked against the field's own value - the documented outcome of
    /// the interaction. A miss (tap eaten by the bar/keyboard, previous field still focused)
    /// costs one measured re-centre, re-tap and retype, then fails loudly with a screenshot in
    /// the diagnostics artifact.
    private func typeAfterKeyboard(_ element: XCUIElement, in app: XCUIApplication, surface: GeometrySurface, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenHittable(element, in: app, surface: surface, file: file, line: line)
        // scrollToHittable may have dismissed a keyboard that occluded this field, so
        // prior existence proves nothing: always wait for the keyboard before typing.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the focused field", file: file, line: line)
        // Clear any default value first: typeText inserts at the cursor, so typing into a
        // prefilled field appends (CI: "servingbowl" passed a substring check for "bowl",
        // #179). The shipped defaults are single tokens; a double-tap selects the word so
        // typing replaces it, and the outcome is checked by exact equality below.
        if let current = element.value as? String, !current.isEmpty {
            element.doubleTap()
        }
        element.typeText(text)
        if (element.value as? String) != text {
            _ = scrollToHittable(element, in: app, surface: surface)
            element.tap()
            element.doubleTap()
            element.typeText(text)
        }
        let landed = (element.value as? String) ?? ""
        if landed != text {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "typeAfterKeyboard-missed"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("Typed text did not land in the field (value after retry: \"\(landed)\")", file: file, line: line)
        }
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
        XCTAssertTrue(scrollToHittable(app.staticTexts["Nothing logged"], in: app, surface: .diary), "Empty diary state should be reachable below totals")
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
        typeAfterKeyboard(foodName, in: app, surface: .logFood, "My lunch")
        typeAfterKeyboard(app.textFields["nutritionDiary.quantityUnit"], in: app, surface: .logFood, "bowl")
        let sourceName = app.textFields["nutritionDiary.sourceName"]
        typeAfterKeyboard(sourceName, in: app, surface: .logFood, "My notes")
        let sourcePicker = app.descendants(matching: .any)["nutritionDiary.source"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 5))
        tapWhenHittable(sourcePicker, in: app, surface: .logFood)
        let externalSource = app.buttons["External record (not verified by Ate)"]
        XCTAssertTrue(externalSource.waitForExistence(timeout: 5))
        let sourcePageCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sourcePageCapture.name = "nutrition-source-choice-sheet"
        sourcePageCapture.lifetime = .keepAlways
        add(sourcePageCapture)
        externalSource.tap()
        XCTAssertNotEqual(sourceName.value as? String, "You")
        XCTAssertNotEqual(sourceName.value as? String, "My notes")
        typeAfterKeyboard(sourceName, in: app, surface: .logFood, "Test food database")
        tapWhenHittable(app.navigationBars["Log food"].buttons["nutritionDiary.save"], in: app, surface: .logFood)

        XCTAssertTrue(app.staticTexts["Unavailable"].firstMatch.exists)
        let savedRow = diaryRows(app, containing: "My lunch").firstMatch
        // Daily and weekly totals precede meal rows; a successful save can leave the
        // new row below the viewport. Reveal the actual entry rather than matching totals.
        XCTAssertTrue(scrollToHittable(savedRow, in: app, surface: .diary), "Saved meal should be reachable below totals")
        XCTAssertTrue(savedRow.waitForExistence(timeout: 5))
    }

    /// DIAGNOSTIC variant only (#179): mirrors the source-picker segment of the required
    /// test above, but resigns the keyboard via Return before interacting with the picker.
    /// The original keyboard-up path is the gate and stays untouched; it times out
    /// deterministically (app never idles 60s+, v3+v5 artifacts). This variant only
    /// isolates whether the keyboard is implicated in that non-idle state. A green result
    /// here cannot satisfy the original gate and proves nothing about the underlying
    /// cause; any app-side fix must verify the real keyboard + picker user flow.
    func testFoodDiarySourcePickerKeyboardResignedDiagnostic() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let sourceName = app.textFields["nutritionDiary.sourceName"]
        typeAfterKeyboard(sourceName, in: app, surface: .logFood, "My notes")
        sourceName.typeText("\n")
        let sourcePicker = app.descendants(matching: .any)["nutritionDiary.source"].firstMatch
        XCTAssertTrue(sourcePicker.waitForExistence(timeout: 5))
        tapWhenHittable(sourcePicker, in: app, surface: .logFood)
        let externalSource = app.buttons["External record (not verified by Ate)"]
        XCTAssertTrue(externalSource.waitForExistence(timeout: 30),
                      "picker option should be reachable after keyboard resign (diagnostic)")
    }

    /// Shared navigation: Settings tab -> Food diary screen.
    private func openDiary(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        // SwiftUI does not materialise this below-fold cell until Settings is scrolled.
        // Reveal it before asserting presence, then keep the actual screen assertion below.
        XCTAssertTrue(scrollToHittable(diaryEntry, in: app, surface: .settings), "Settings should expose Food diary inside the clear band")
        tapWhenHittable(diaryEntry, in: app, surface: .settings)
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
        XCTAssertTrue(scrollToHittable(app.staticTexts["Nothing logged"], in: app, surface: .diary), "Empty diary state should be reachable below totals")
        XCTAssertTrue(app.staticTexts["Nothing logged"].exists)
    }

    func testLogFoodRejectsNonPositiveQuantityWithVisibleError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        typeAfterKeyboard(foodName, in: app, surface: .logFood, "Bad entry")
        let quantity = app.textFields["nutritionDiary.quantity"]
        typeAfterKeyboard(quantity, in: app, surface: .logFood, "0")
        XCTAssertEqual(quantity.value as? String, "0", "Validation must submit zero, not a positive value with zero inserted before it")
        tapWhenHittable(app.navigationBars["Log food"].buttons["nutritionDiary.save"], in: app, surface: .logFood)
        // Error state: visible message, and the form stays open for correction. If the error
        // section renders outside the materialised cells, scroll it into the hierarchy.
        let formError = app.descendants(matching: .any)["nutritionDiary.formError"]
        XCTAssertTrue(scrollToHittable(formError, in: app, surface: .logFood) || formError.waitForExistence(timeout: 3), "Save error should be visible")
        XCTAssertTrue(app.staticTexts["Enter a quantity and servings greater than zero."].exists)
        XCTAssertTrue(app.buttons["nutritionDiary.save"].exists)
        captureNutritionState(app, name: "nutrition-invalid-quantity-visible-error")
    }

    func testLogFoodSurfacesSaveFailure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-resetNutritionDiary", "-failDiarySaves"]
        app.launch()
        openDiary(app)
        openLogForm(app)
        let foodName = app.textFields["nutritionDiary.foodName"]
        typeAfterKeyboard(foodName, in: app, surface: .logFood, "My lunch")
        tapWhenHittable(app.navigationBars["Log food"].buttons["nutritionDiary.save"], in: app, surface: .logFood)
        // Save-failure state: the diary-level error is shown. The entry exists only in memory,
        // so after a relaunch without the fault argument the diary is empty again.
        let saveError = app.descendants(matching: .any)["nutritionDiary.error"]
        XCTAssertTrue(scrollToHittable(saveError, in: app, surface: .diary), "Failed save should show the diary error")
        XCTAssertTrue(saveError.waitForExistence(timeout: 5))
        captureNutritionState(app, name: "nutrition-disk-save-error")
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-UITesting"]
        relaunched.launch()
        openDiary(relaunched)
        XCTAssertTrue(diaryRows(relaunched, containing: "My lunch").allElementsBoundByIndex.isEmpty,
                      "a failed save must not persist the entry")
        XCTAssertTrue(scrollToHittable(relaunched.staticTexts["Nothing logged"], in: relaunched, surface: .diary), "Failed save should leave the relaunched diary empty")
        XCTAssertTrue(relaunched.staticTexts["Nothing logged"].exists)
    }

    func testCorruptDiaryShowsErrorAndRecoversAfterBackupReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-seedCorruptNutritionDiary"]
        app.launch()
        openDiary(app)
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.corruptDataError"].waitForExistence(timeout: 5))
        tapWhenHittable(app.buttons["nutritionDiary.recoverCorruptData"], in: app, surface: .diary)
        let confirm = app.buttons["Back up and reset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nutritionDiary.recoveryNotice"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(app.staticTexts["Nothing logged"], in: app, surface: .diary), "Empty diary state should be reachable below totals")
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
        tapWhenHittable(card, in: app, surface: .library, "Seeded recipe card should be visible before it is tapped")
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
        } else if !nutritionCard.exists {
            // The compact quick-look sheet renders "Expand recipe details" but its controls
            // were absent from the accessibility tree in this presentation (CI recording
            // 2026-10-31: sheet visibly presented >10s, no AX exposure; matches the caveat
            // in test32c). Capture the true hierarchy and the rendered sheet as evidence
            // for that exposure gap, then use the real user gesture the sheet is built
            // for: drag its content up (presentationContentInteraction(.resizes)) so the
            // 260pt compact detent grows and the real detail loads. The drag endpoints
            // come from LIVE window bounds and the production detent constant, not from
            // any recorded coordinate.
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "quicklook-ax-tree"
            tree.lifetime = .keepAlways
            add(tree)
            let sheetShot = XCTAttachment(screenshot: app.screenshot())
            sheetShot.name = "quicklook-before-expand"
            sheetShot.lifetime = .keepAlways
            add(sheetShot)
            let window = app.windows.firstMatch.frame
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.midX, dy: window.maxY - 130)) // centre of the 260pt compact sheet
            let end = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: window.midX, dy: window.maxY * 0.3))
            start.press(forDuration: 0.2, thenDragTo: end)
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
        captureNutritionState(app, name: "nutrition-add-entry")
        let foodName = app.textFields["nutritionDiary.foodName"]
        typeAfterKeyboard(foodName, in: app, surface: .logFood, "My lunch")
        typeAfterKeyboard(app.textFields["nutritionDiary.quantityUnit"], in: app, surface: .logFood, "bowl")
        tapWhenHittable(app.navigationBars["Log food"].buttons["nutritionDiary.save"], in: app, surface: .logFood)

        let row = diaryRows(app, containing: "My lunch").firstMatch
        XCTAssertTrue(scrollToHittable(row, in: app, surface: .diary), "Saved meal should be reachable below totals")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        captureNutritionState(app, name: "nutrition-diary-list")
        row.swipeLeft()
        app.buttons["Edit"].tap()
        // Edit mode: seeded values, Edit title.
        XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 5))
        let quantity = app.textFields["nutritionDiary.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        captureNutritionState(app, name: "nutrition-edit-entry")
        tapWhenHittable(quantity, in: app, surface: .editFood)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the quantity field")
        // The centre tap places the caret before the seeded decimal on native iOS.
        // Tap past its trailing glyph, then clear with slack before replacing it.
        quantity.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let existingQuantity = quantity.value as? String ?? ""
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingQuantity.count + 2))
        quantity.typeText("2")
        XCTAssertEqual(quantity.value as? String, "2", "Edit must replace the seeded quantity, not append to it")
        tapWhenHittable(app.navigationBars["Edit food"].buttons["nutritionDiary.save"], in: app, surface: .editFood)
        let editedRow = diaryRows(app, containing: "2 bowl").firstMatch
        XCTAssertTrue(scrollToHittable(editedRow, in: app, surface: .diary), "Edited meal should remain reachable below totals")
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5))
        XCTAssertEqual(diaryRows(app, containing: "My lunch").allElementsBoundByIndex.count, 1,
                       "edit must keep one row with the same identity")
        captureNutritionState(app, name: "nutrition-saved-edit-single-two-bowl-row")
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
        typeAfterKeyboard(foodName, in: app, surface: .logFood, "Week lunch")
        let energy = app.textFields["nutritionDiary.nutrient.energy"]
        scrolls = 0
        while !energy.exists && scrolls < 8 {
            app.swipeUp(velocity: .slow)
            scrolls += 1
        }
        XCTAssertTrue(energy.waitForExistence(timeout: 5))
        typeAfterKeyboard(energy, in: app, surface: .logFood, "200")
        tapWhenHittable(app.navigationBars["Log food"].buttons["nutritionDiary.save"], in: app, surface: .logFood)

        let weeklyEnergy = app.staticTexts["nutritionDiary.weeklyTotal.energy.value"]
        scrolls = 0
        while !weeklyEnergy.exists && scrolls < 8 {
            app.swipeUp(velocity: .slow)
            scrolls += 1
        }
        XCTAssertTrue(weeklyEnergy.waitForExistence(timeout: 5), "This week section should list an energy total")
        XCTAssertEqual(weeklyEnergy.label, "200 kcal")
        captureNutritionState(app, name: "nutrition-weekly-totals")
        XCTAssertFalse(app.staticTexts["Nothing logged this week yet."].exists)
    }

    /// Retain real passing-run evidence for the repaired diary journeys.
    private func captureNutritionState(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
