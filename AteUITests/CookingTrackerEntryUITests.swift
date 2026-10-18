import XCTest

final class CookingTrackerEntryUITests: XCTestCase {
    private func launchTracker(mockHealth: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        if mockHealth { app.launchArguments += ["-qaMockHealth", "recovery", "-qaHealthRecipes", "-qaHealthPrompt"] }
        app.launch()
        let insightsTab = app.tabBars.buttons["Insights"]
        XCTAssertTrue(insightsTab.waitForExistence(timeout: 10), "Insights should be a first-class tab")
        insightsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cookingTracker.screen"].waitForExistence(timeout: 10))
        return app
    }

    func testInsightsHasDedicatedTabEntryPoint() {
        let app = launchTracker()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }

    func testLibraryShortcutOpensInsightsHubRoot() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let shortcut = app.buttons["library.todayJournalHub"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10), "Library should expose the Insights shortcut")
        shortcut.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tracker.previousMonth"].exists)
    }

    func testTrackerHubIncludesHealthAndJournalWithoutPromptingOnOpen() {
        let app = launchTracker(mockHealth: true)
        XCTAssertTrue(app.staticTexts["Your body today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your Ate journal"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["insights.cookingCalendar"].exists)
        XCTAssertTrue(app.buttons["insights.connect"].exists, "Health access should be an explicit user action")
        XCTAssertFalse(app.alerts["“ate” would like to access your Health data"].exists,
                       "Opening Insights must not request Health permission")
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
        let today = app.buttons["tracker.day.\\(day)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5), "Today should be an accessible calendar button")
        XCTAssertTrue(today.label.contains("today"))
        // XCTest can report a 44pt SwiftUI frame a few floating-point ulps below 44.
        // Keep the accessibility minimum check while allowing 0.01pt of geometry noise.
        XCTAssertGreaterThanOrEqual(today.frame.height, 43.99,
                                    "Date hit targets must meet the 44pt accessibility minimum (0.01pt measurement tolerance)")
        today.tap()

        XCTAssertTrue(app.navigationBars["Cooked that day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing recorded for this day."].waitForExistence(timeout: 5))
    }
}
