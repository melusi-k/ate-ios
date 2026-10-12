import XCTest

final class CookingTrackerEntryUITests: XCTestCase {
    private func launchTracker() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let trackerTab = app.tabBars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 10), "Cooking Tracker should be a first-class tab")
        trackerTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cookingTracker.screen"].waitForExistence(timeout: 10))
        return app
    }

    func testTrackerHasDedicatedTabEntryPoint() {
        let app = launchTracker()
        XCTAssertTrue(app.staticTexts["Cooking Tracker"].firstMatch.exists)
    }

    func testMonthNavigationAndFutureMonthRestriction() {
        let app = launchTracker()
        let month = app.staticTexts["tracker.displayedMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let currentMonth = month.label

        let previous = app.buttons["tracker.previousMonth"]
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        XCTAssertNotEqual(month.label, currentMonth)

        let next = app.buttons["tracker.nextMonth"]
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertEqual(month.label, currentMonth)
        XCTAssertFalse(next.isEnabled, "The calendar must not navigate beyond the current month")
    }

    func testSelectingTodayShowsDayDetailsAndExplicitEmptyState() {
        let app = launchTracker()
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\\(day)"]
        XCTAssertTrue(today.waitForExistence(timeout: 5), "Today should be an accessible calendar button")
        XCTAssertTrue(today.label.contains("today"))
        today.tap()

        XCTAssertTrue(app.navigationBars["Cooked that day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing recorded for this day."].waitForExistence(timeout: 5))
    }
}
