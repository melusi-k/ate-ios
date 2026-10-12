import XCTest

final class CookingTrackerEntryUITests: XCTestCase {
    private func launchTracker(mockHealth: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        if mockHealth { app.launchArguments += ["-qaMockHealth", "recovery", "-qaHealthRecipes", "-qaHealthPrompt"] }
        app.launch()
        let trackerTab = app.tabBars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 10), "Cooking Tracker should be a first-class tab")
        trackerTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cookingTracker.screen"].waitForExistence(timeout: 10))
        return app
    }

    func testTrackerHasDedicatedTabEntryPoint() {
        let app = launchTracker()
        XCTAssertTrue(app.staticTexts["Today & Journal"].waitForExistence(timeout: 5))
    }

    func testLibraryShortcutOpensTrackerHubRoot() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let shortcut = app.buttons["library.todayJournalHub"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10), "Library should expose the Today & Journal shortcut")
        shortcut.tap()
        XCTAssertTrue(app.staticTexts["Today & Journal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tracker.previousMonth"].exists)
    }

    func testTrackerHubIncludesHealthAndJournalWithoutPromptingOnOpen() {
        let app = launchTracker(mockHealth: true)
        XCTAssertTrue(app.staticTexts["Your body today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your Ate journal"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["insights.cookingCalendar"].exists)
        XCTAssertTrue(app.buttons["insights.connect"].exists, "Health access should be an explicit user action")
        XCTAssertFalse(app.alerts["“ate” would like to access your Health data"].exists,
                       "Opening Tracker must not request Health permission")
        app.buttons["insights.connect"].tap()
        XCTAssertTrue(app.alerts["“ate” would like to access your Health data"].waitForExistence(timeout: 5),
                      "The mock Health prompt should appear only after explicit user intent")
    }

    func testMonthNavigationAndFutureMonthRestriction() {
        let app = launchTracker()
        let month = app.staticTexts["tracker.displayedMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let currentMonth = month.label

        let previous = app.buttons["tracker.previousMonth"]
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        let movedToPreviousMonth = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", currentMonth),
            object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [movedToPreviousMonth], timeout: 3), .completed)

        let next = app.buttons["tracker.nextMonth"]
        XCTAssertTrue(next.isHittable)
        next.tap()
        let returnedToCurrentMonth = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", currentMonth),
            object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returnedToCurrentMonth], timeout: 3), .completed)
        XCTAssertFalse(next.isEnabled, "The calendar must not navigate beyond the current month")
    }

    func testSelectingTodayShowsDayDetailsAndExplicitEmptyState() {
        let app = launchTracker()
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5), "Today should be an accessible calendar button")
        XCTAssertTrue(today.label.contains("today"))
        XCTAssertGreaterThanOrEqual(today.frame.height, 44, "Date hit targets must meet the 44pt accessibility minimum")
        today.tap()

        XCTAssertTrue(app.navigationBars["Cooked that day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing recorded for this day."].waitForExistence(timeout: 5))
    }
}
