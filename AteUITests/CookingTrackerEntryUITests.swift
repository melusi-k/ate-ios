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
        let summary = app.descendants(matching: .any)["tracker.monthSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Recorded this month: 0 days cooked · 0 recipes")
        let rows = app.otherElements.matching(identifier: "tracker.monthSummaryRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "Measure the unique padded summary row, not combined text")
        let row = rows.firstMatch
        XCTAssertGreaterThanOrEqual(row.frame.height, 43.99,
                                    "Body-size summary has 12pt vertical breathing room on each side")
        XCTAssertGreaterThanOrEqual(row.frame.minY, app.staticTexts["tracker.displayedMonth"].frame.maxY)
        XCTAssertGreaterThanOrEqual(summary.frame.minY, row.frame.minY)
        XCTAssertLessThanOrEqual(summary.frame.maxY, row.frame.maxY)
        shot("tracker-month-summary-current-normal")
        app.buttons["tracker.previousMonth"].tap()
        XCTAssertEqual(summary.label, "Recorded this month: 0 days cooked · 0 recipes")
        shot("tracker-month-summary-previous-normal")
        app.buttons["tracker.nextMonth"].tap()
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(app.buttons["tracker.nextMonth"].isEnabled)
    }

    /// #68: native push/Back and the interactive edge gesture share one header owner.
    /// No custom Back implementation, gesture fallback, re-tap or navigation retry.
    func testJournalAndInsightsHeadersPreserveNativeBackAndEdgeSwipeAtNormalText() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let journalTab = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journalTab.waitForExistence(timeout: 10))
        journalTab.tap()
        let rootBar = app.navigationBars["Journal"]
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        let rootLogo = app.images["journal.logo"]
        XCTAssertTrue(rootBar.waitForExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertTrue(rootLogo.exists)
        XCTAssertTrue(hub.waitForExistence(timeout: 5))
        XCTAssertTrue(hub.isHittable)
        shot("68-journal-root-normal")

        hub.tap()
        let pushedBar = app.navigationBars["Insights & Cooking History"]
        XCTAssertTrue(pushedBar.waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertFalse(app.images["insights.logo"].exists, "Pushed Insights must not install root chrome")
        XCTAssertFalse(rootLogo.exists, "Root logo must not compete with the pushed Back button")
        let back = pushedBar.buttons["Journal"]
        XCTAssertTrue(back.exists && back.isHittable, "System Back must retain the parent title")
        shot("68-insights-native-back-normal")
        back.tap()
        XCTAssertTrue(rootBar.waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertTrue(rootLogo.exists)
        XCTAssertTrue(hub.exists && hub.isHittable, "Back must restore the original Journal content")
        shot("68-journal-after-native-back-normal")

        hub.tap()
        XCTAssertTrue(pushedBar.waitForExistence(timeout: 5))
        XCTAssertTrue(pushedBar.buttons["Journal"].isHittable)
        // Start at the real leading edge and finish well inside the same window.
        // This is the interactive pop gesture, not an app swipe or a Back fallback.
        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let finish = window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.1, thenDragTo: finish)
        XCTAssertTrue(rootBar.waitForExistence(timeout: 5), "Interactive edge swipe must restore Journal")
        XCTAssertFalse(pushedBar.exists)
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertTrue(rootLogo.exists)
        XCTAssertTrue(hub.exists && hub.isHittable)
        XCTAssertTrue(journalTab.isSelected)
        shot("68-journal-after-edge-swipe-normal")
    }

}
