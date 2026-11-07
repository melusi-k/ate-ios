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

    /// The row may sit below the materialized window: swipe while it is not yet present
    /// and hittable so the lazy Form realizes it (same semantics as CoverageUITests).
    private func scrollTo(_ e: XCUIElement, max: Int = 25) {
        _ = e.waitForExistence(timeout: 2)
        var n = 0
        while !(e.exists && e.isHittable) && n < max { app.swipeUp(); n += 1 }
        n = 0
        while !(e.exists && e.isHittable) && n < max * 2 { app.swipeDown(); n += 1 }
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
        // Retained pixel evidence: the top of Settings before any scrolling.
        let top = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        top.name = "settings-top-hierarchy"; top.lifetime = .keepAlways; add(top)
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
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-ai-availability"; shot.lifetime = .keepAlways; add(shot)
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
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-timer-notifications"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Largest-Dynamic-Type capture (#74): the sync summary must stay fully rendered - no clipped
    /// leading/trailing glyphs - at UICTContentSizeCategoryAccessibilityXXXL. Mirrors the repo's
    /// existing launch-argument convention (AccessibilityAuditUITests.testAuditLargestDynamicType).
    /// The attached PNG is the review surface: presence alone is not proof of unclipped text.
    func testSyncSummaryLargestDynamicType() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tab("Settings")
        let summary = app.staticTexts["settings.syncSummary"]
        scrollTo(summary)
        wait(summary, 10)
        XCTAssertTrue(summary.exists, "Sync summary should exist at the largest accessibility text size")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-sync-summary-largest-dt"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Normal-size coverage, separate from the retained original cross-size case.
    func testSyncSummaryNormalText() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        tab("Settings")
        let summary = app.staticTexts["settings.syncSummary"]
        scrollTo(summary)
        wait(summary, 10)
        XCTAssertTrue(summary.exists, "Sync summary should exist at normal text size")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-sync-summary-normal"; shot.lifetime = .keepAlways; add(shot)
    }
}
