import XCTest

final class NutritionGoalsUITests: XCTestCase {
    private func launchSettings(resetGoals: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // Reset leftover goal state (including a corrupt store seeded by another suite) so
        // this suite starts from a clean, loadable configuration.
        app.launchArguments = ["-UITesting"]
        if resetGoals { app.launchArguments.append("-resetNutritionGoals") }
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings should be a first-class tab")
        settings.tap()
        return app
    }

    /// Scroll against the measured frame, not isHittable: on this platform cells clipped by
    /// the navigation bar or pushed past the keyboard still report hittable, and taps
    /// synthesised at those centres land on the bar or keyboard instead of the control - or
    /// on the WRONG control entirely when the centre lands on a different row. Returns true
    /// only when the measured centre sits inside the clear band and the element is hittable;
    /// callers assert before tapping, so exhaustion fails loudly instead of tapping blind.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, max: Int = 12) -> Bool {
        // Measured from the on-screen navigation bar when present; 120pt fallback matches
        // the pinned CI simulator (402x874).
        let navBar = app.navigationBars.firstMatch
        let topBound: CGFloat = (navBar.exists && !navBar.frame.isEmpty) ? navBar.frame.maxY + 4 : 120
        var attempts = 0
        var blockedUps = 0
        while attempts < max {
            attempts += 1
            guard element.exists, !element.frame.isEmpty else {
                app.swipeUp(velocity: .slow)
                continue
            }
            let frame = element.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardUp = keyboard.exists
            let bottomBound = keyboardUp ? keyboard.frame.minY - 8 : app.windows.firstMatch.frame.maxY - 4
            if frame.midY >= topBound && frame.midY <= bottomBound {
                if element.isHittable { return true }
                app.swipeDown(velocity: .slow)
            } else if frame.midY > bottomBound {
                if keyboardUp && blockedUps >= 2 {
                    app.swipeDown(velocity: .fast) // drag the keyboard away, then re-measure
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
        guard element.exists, !element.frame.isEmpty, element.isHittable else { return false }
        let finalFrame = element.frame
        let finalKeyboard = app.keyboards.firstMatch
        let finalBottom = finalKeyboard.exists ? finalKeyboard.frame.minY - 8 : app.windows.firstMatch.frame.maxY - 4
        return finalFrame.midY >= topBound && finalFrame.midY <= finalBottom
    }

    func testGoalsCanBeConfiguredAndClearedFromSettings() {
        var app = launchSettings()
        let entry = app.buttons["settings.nutritionGoals"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Settings should expose Nutrition goals")
        XCTAssertTrue(scrollTo(entry, in: app), "Nutrition goals should be reachable inside the visible band before tapping")
        entry.tap()

        let proteinToggle = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(proteinToggle.waitForExistence(timeout: 10))
        // The goals draft loads asynchronously and every control stays disabled until it
        // finishes; a tap on a disabled switch is silently ignored. Wait for a live control.
        var toggleEnabled = false
        let enableDeadline = Date().addingTimeInterval(5)
        while Date() < enableDeadline && !toggleEnabled {
            toggleEnabled = proteinToggle.exists && proteinToggle.isEnabled
            if !toggleEnabled { usleep(200_000) }
        }
        XCTAssertTrue(toggleEnabled, "Protein toggle should become tappable once goals load")
        // A tap synthesised while the navigation transition is still settling can be
        // swallowed on a loaded simulator. Decide the retry from the switch's own value, not
        // from the value row's existence: the row render can race the query, and a blind
        // second tap would toggle an already-on goal back off. Value and frame go to the test
        // log so CI artifacts carry the discriminator if this ever fails again.
        proteinToggle.tap()
        var toggleValue = proteinToggle.value as? String
        print("[goals] protein switch after tap 1: value=\(toggleValue ?? "nil") frame=\(NSStringFromCGRect(proteinToggle.frame))")
        if toggleValue != "1" {
            proteinToggle.tap()
            toggleValue = proteinToggle.value as? String
            print("[goals] protein switch after tap 2: value=\(toggleValue ?? "nil") frame=\(NSStringFromCGRect(proteinToggle.frame))")
        }
        XCTAssertEqual(toggleValue, "1", "Protein toggle should turn on")

        let proteinValue = app.textFields["nutritionGoals.value.protein"]
        XCTAssertTrue(proteinValue.waitForExistence(timeout: 5), "Enabled protein goal should reveal its value field")
        proteinValue.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the goal value")
        proteinValue.typeText("100")

        // Persist a non-empty value, then relaunch without the reset hook. This proves
        // reopening reads saved goals instead of a fresh test-seeded draft.
        let initialSave = app.buttons["nutritionGoals.save"]
        XCTAssertTrue(scrollTo(initialSave, in: app), "Save goals should reveal inside the visible band before tapping")
        initialSave.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.terminate()
        app = launchSettings(resetGoals: false)
        let savedEntry = app.buttons["settings.nutritionGoals"]
        XCTAssertTrue(scrollTo(savedEntry, in: app), "Saved goals entry should reveal inside the visible band before tapping")
        savedEntry.tap()
        let savedProtein = app.textFields["nutritionGoals.value.protein"]
        XCTAssertTrue(savedProtein.waitForExistence(timeout: 10))
        XCTAssertEqual(savedProtein.value as? String, "100", "Saved goals should survive a fresh launch without reset")

        let clearAll = app.buttons["nutritionGoals.clearAll"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollTo(clearAll, in: app), "Clear all should reveal inside the visible band before tapping")
        clearAll.tap()
        XCTAssertTrue(app.textFields["nutritionGoals.value.protein"].waitForNonExistence(timeout: 5), "Clear all should turn off every goal in the draft")
        XCTAssertTrue(app.staticTexts["Clearing goals changes this draft only until you tap Save goals."].exists)

        let save = app.buttons["nutritionGoals.save"]
        XCTAssertTrue(scrollTo(save, in: app), "Save goals should reveal inside the visible band before tapping")
        save.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        app.terminate()
        app = launchSettings(resetGoals: false)
        let reopenedEntry = app.buttons["settings.nutritionGoals"]
        XCTAssertTrue(scrollTo(reopenedEntry, in: app), "Reopened goals entry should reveal inside the visible band before tapping")
        reopenedEntry.tap()
        let reopenedProteinToggle = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(reopenedProteinToggle.waitForExistence(timeout: 10))
        let reopenedEnabled = NSPredicate(format: "enabled == true")
        let reopenedReady = XCTNSPredicateExpectation(predicate: reopenedEnabled, object: reopenedProteinToggle)
        XCTAssertEqual(XCTWaiter.wait(for: [reopenedReady], timeout: 5), .completed, "Reopened goals must finish loading before checking persistence")
        XCTAssertEqual(reopenedProteinToggle.value as? String, "0", "Cleared goals should remain cleared after reopening")
    }
}
