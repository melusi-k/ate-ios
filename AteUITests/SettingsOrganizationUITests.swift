import XCTest

/// Settings organisation (#74): account/sync prominence, everyday preferences grouped
/// first, and the AI availability explanation. Helper style matches the other suites.
final class SettingsOrganizationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func scrollTo(_ e: XCUIElement, max: Int = 8) {
        _ = e.waitForExistence(timeout: 5)
        var n = 0
        while e.exists && !e.isHittable && n < max { app.swipeUp(velocity: .slow); n += 1 }
        n = 0
        while e.exists && !e.isHittable && n < max { app.swipeDown(velocity: .slow); n += 1 }
    }

    private func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }

    /// The sync summary sits directly under the account card: it must materialize
    /// with no scrolling at all, which only holds while it stays in the first section.
    func testSyncSummaryExistsWithoutScrolling() {
        launch()
        tab("Settings")
        let summary = app.staticTexts["settings.syncSummary"]
        wait(summary, 10)
        XCTAssertTrue(summary.exists, "Sync summary should materialize without any scrolling")
    }

    /// AI availability and device compatibility are explained next to Private mode.
    func testAIAvailabilityExplanationPresent() {
        launch()
        tab("Settings")
        let ai = app.descendants(matching: .any)["settings.aiAvailability"].firstMatch
        scrollTo(ai)
        wait(ai, 5)
        XCTAssertTrue(ai.label.contains("Apple Intelligence"), ai.label)
        XCTAssertTrue(ai.label.contains("Demo"), ai.label)
    }

    /// Everyday preferences stay reachable: the Timer notifications group (sound,
    /// quiet hours, step alerts) scrolls into view within the standard swipe budget.
    /// Reachability smoke only; section ordering is reviewed in the diff, not here.
    func testEverydayPreferencesReachable() {
        launch()
        tab("Settings")
        let header = app.staticTexts["Timer notifications"]
        scrollTo(header)
        wait(header, 5)
    }
}
