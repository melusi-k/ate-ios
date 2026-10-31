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

    /// Bottom edge of the tappable band, measured from the chrome actually on screen: the
    /// floating tab bar and, at tab roots, the Add accessory floating above it. A fixed
    /// offset let rows resting behind that chrome count as reachable - on the CI simulator
    /// the Food diary row's centre sat at y=869, inside the tab bar's 791-874 frame, so the
    /// old maxY-4 bound judged it "in band", the nudge swiped the wrong way and the tap was
    /// intercepted by the bar (CI hierarchy + recording, #179).
    private func bottomClearBound(_ app: XCUIApplication, keyboard: XCUIElement?) -> CGFloat {
        var bound = app.windows.firstMatch.frame.maxY - 4
        if let keyboard { bound = min(bound, keyboard.frame.minY - 8) }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && !tabBar.frame.isEmpty && tabBar.isHittable { bound = min(bound, tabBar.frame.minY - 4) }
        let accessory = app.buttons["accessoryAdd"]
        if accessory.exists && !accessory.frame.isEmpty && accessory.isHittable { bound = min(bound, accessory.frame.minY - 4) }
        return bound
    }

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
            let bottomBound = bottomClearBound(app, keyboard: keyboardUp ? keyboard : nil)
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
                // Overshot above the band: nudge back down. blockedUps deliberately keeps
                // counting here - resetting it let a keyboard-blocked field alternate
                // up/down forever without ever dragging the keyboard away (CI: sourceName
                // oscillated swipe-up/swipe-down 12 attempts, #179).
                app.swipeDown(velocity: .slow)
            }
        }
        guard element.exists, !element.frame.isEmpty, element.isHittable else { return false }
        let finalFrame = element.frame
        let finalKeyboard = app.keyboards.firstMatch
        let finalBottom = bottomClearBound(app, keyboard: finalKeyboard.exists ? finalKeyboard : nil)
        return finalFrame.midY >= topBound && finalFrame.midY <= finalBottom
    }

    func testGoalsCanBeConfiguredAndClearedFromSettings() {
        var app = launchSettings()
        let entry = app.buttons["settings.nutritionGoals"]
        // The goals row starts below the fold (dematerialised behind the tab chrome), so a
        // hard existence assert before revealing can never pass on that state. Reveal first:
        // scrollTo swipes up while the row is absent, and reaching it proves presence.
        _ = entry.waitForExistence(timeout: 5)
        XCTAssertTrue(scrollTo(entry, in: app), "Settings should expose Nutrition goals inside the clear band before tapping")
        entry.tap()

        let proteinRow = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(proteinRow.waitForExistence(timeout: 10))
        // SwiftUI merges the Toggle row into a Switch-typed element (370x59 in the CI
        // hierarchy) whose synthesized centre tap lands on the label text, not the control;
        // the old taps changed nothing (row and inner control both still read value 0 in
        // the failure snapshot). The actual UISwitch is the small Switch element inside
        // the row - tap that, and decide any retry from its own value.
        let proteinControl = app.switches.allElementsBoundByIndex.first {
            $0.identifier.isEmpty && $0.frame.width < 120 && $0.frame.height < 60 && proteinRow.frame.contains($0.frame)
        }
        if proteinControl == nil {
            print("[goals] WARN inner switch control not found; falling back to the row element")
        }
        let proteinToggle = proteinControl ?? proteinRow
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
        print("[goals] protein switch after tap 1: value=\(toggleValue ?? "nil") frame=\(NSCoder.string(for: proteinToggle.frame))")
        if toggleValue != "1" {
            proteinToggle.tap()
            toggleValue = proteinToggle.value as? String
            print("[goals] protein switch after tap 2: value=\(toggleValue ?? "nil") frame=\(NSCoder.string(for: proteinToggle.frame))")
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
