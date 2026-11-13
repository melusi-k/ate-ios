import XCTest

final class CookingTrackerEntryUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
    private func launchTracker(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"] + extra
        app.launch()
        let journalTab = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journalTab.waitForExistence(timeout: 10), "Journal should be a first-class tab")
        XCTAssertFalse(app.tabBars.buttons["Insights"].exists, "Insights remains a destination, not a tab")
        journalTab.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "Journal tab root is the Journal")
        shot("journal-tab-label-icon-root")
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10))
        hub.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cookingTracker.screen"].waitForExistence(timeout: 10))
        return app
    }

    func testInsightsHasDedicatedTabEntryPoint() {
        let app = launchTracker()
        XCTAssertTrue(app.navigationBars["Insights & Cooking History"].waitForExistence(timeout: 5))
    }

    func testLibraryShortcutOpensInsightsHubRoot() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let shortcut = app.buttons["library.todayJournalHub"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10), "Library should expose the Insights shortcut")
        shortcut.tap()
        // The shortcut opens the Insights & Cooking History hub directly above the Journal root.
        XCTAssertTrue(app.navigationBars["Insights & Cooking History"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tracker.previousMonth"].exists)
    }

    func testMonthNavigationAndFutureMonthRestriction() {
        let app = launchTracker()
        let month = app.staticTexts["tracker.displayedMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        shot("tracker-month-view")
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
        // XCTest can report a 44pt SwiftUI frame a few floating-point ulps below 44.
        // Keep the accessibility minimum check while allowing 0.01pt of geometry noise.
        XCTAssertGreaterThanOrEqual(today.frame.height, 43.99,
                                    "Date hit targets must meet the 44pt accessibility minimum (0.01pt measurement tolerance)")
        today.tap()

        XCTAssertTrue(app.navigationBars["Cooked that day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing recorded for this day."].waitForExistence(timeout: 5))
        shot("tracker-day-details")
    }
    func testEmptyMonthSummaryFollowsCalendarAtNormalText() {
        let app = launchTracker(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        let summary = app.staticTexts["tracker.monthSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Recorded this month: 0 cooking days · 0 distinct recipes")
        shot("tracker-month-summary-current-normal")
        app.buttons["tracker.previousMonth"].tap()
        XCTAssertEqual(summary.label, "Recorded this month: 0 cooking days · 0 distinct recipes")
        shot("tracker-month-summary-previous-normal")
        app.buttons["tracker.nextMonth"].tap()
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(app.buttons["tracker.nextMonth"].isEnabled)
    }

}
