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

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, max: Int = 8) {
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < max {
            app.swipeUp(velocity: .slow)
            attempts += 1
        }
    }

    func testGoalsCanBeConfiguredAndClearedFromSettings() {
        var app = launchSettings()
        let entry = app.buttons["settings.nutritionGoals"]
        scrollTo(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Settings should expose Nutrition goals")
        XCTAssertTrue(entry.isHittable, "Nutrition goals should be reachable in the Settings form")
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
        // swallowed on a loaded simulator. Confirm the effect - switching on reveals the
        // goal's value row - before retrying, so a retry can never toggle an already-on
        // goal back off because of a stale value observation.
        proteinToggle.tap()
        var revealed = app.textFields["nutritionGoals.value.protein"].waitForExistence(timeout: 5)
        if !revealed {
            proteinToggle.tap()
            revealed = app.textFields["nutritionGoals.value.protein"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(revealed, "Protein toggle should turn on")

        let proteinValue = app.textFields["nutritionGoals.value.protein"]
        proteinValue.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard should appear for the goal value")
        proteinValue.typeText("100")

        // Persist a non-empty value, then relaunch without the reset hook. This proves
        // reopening reads saved goals instead of a fresh test-seeded draft.
        let initialSave = app.buttons["nutritionGoals.save"]
        scrollTo(initialSave, in: app)
        initialSave.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.terminate()
        app = launchSettings(resetGoals: false)
        let savedEntry = app.buttons["settings.nutritionGoals"]
        scrollTo(savedEntry, in: app)
        savedEntry.tap()
        let savedProtein = app.textFields["nutritionGoals.value.protein"]
        XCTAssertTrue(savedProtein.waitForExistence(timeout: 10))
        XCTAssertEqual(savedProtein.value as? String, "100", "Saved goals should survive a fresh launch without reset")

        let clearAll = app.buttons["nutritionGoals.clearAll"]
        scrollTo(clearAll, in: app)
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()
        XCTAssertTrue(app.textFields["nutritionGoals.value.protein"].waitForNonExistence(timeout: 5), "Clear all should turn off every goal in the draft")
        XCTAssertTrue(app.staticTexts["Clearing goals changes this draft only until you tap Save goals."].exists)

        let save = app.buttons["nutritionGoals.save"]
        scrollTo(save, in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        app.terminate()
        app = launchSettings(resetGoals: false)
        let reopenedEntry = app.buttons["settings.nutritionGoals"]
        scrollTo(reopenedEntry, in: app)
        reopenedEntry.tap()
        let reopenedProteinToggle = app.switches["nutritionGoals.enabled.protein"]
        XCTAssertTrue(reopenedProteinToggle.waitForExistence(timeout: 10))
        let reopenedEnabled = NSPredicate(format: "enabled == true")
        let reopenedReady = XCTNSPredicateExpectation(predicate: reopenedEnabled, object: reopenedProteinToggle)
        XCTAssertEqual(XCTWaiter.wait(for: [reopenedReady], timeout: 5), .completed, "Reopened goals must finish loading before checking persistence")
        XCTAssertEqual(reopenedProteinToggle.value as? String, "0", "Cleared goals should remain cleared after reopening")
    }
}
