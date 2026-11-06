import XCTest

/// Captures the real Journal / Insights action menus on the current head:
/// the journal entry detail "More" menu (Edit / Delete) and the Insights
/// entry long-press context menu. The store is NOT assumed isolated, so the
/// seed entry carries unique text, every selection is by that exact text,
/// and the delete only runs after the open detail is verified to be the
/// seed entry itself. Nothing pre-existing is selected or removed.
///
/// Navigation discipline: Journal is the Insights tab root and the Insights hub is pushed.
/// Every menu dismissal is asserted gone before back or tab navigation.
final class JournalMenuCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var seed = ""

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        seed = "Menu capture seed " + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaMockHealth", "recovery", "-qaHealthRecipes"]
        app.launch()
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func gone(_ element: XCUIElement, _ timeout: TimeInterval = 5,
                      file: StaticString = #filePath, line: UInt = #line) {
        let pred = NSPredicate(format: "exists == false")
        expectation(for: pred, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
        XCTAssertFalse(element.exists, "element must be gone", file: file, line: line)
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The exact seed entry's visible text, never a positional row.
    private func seedText(_ file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let t = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", seed)).firstMatch
        wait(t, 10, file: file, line: line)
        return t
    }

    /// Return from the pushed Insights hub to the Journal tab root before another journey.
    private func returnToJournalRoot(_ file: StaticString = #filePath, line: UInt = #line) {
        let hub = any("journal.insightsHistory")
        if !hub.exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            wait(back, 10, file: file, line: line)
            back.tap()
        }
        wait(app.navigationBars["Journal"], 10, file: file, line: line)
        wait(hub, 10, file: file, line: line)
    }

    /// Pushed Insights hub: connect mock Health and save one uniquely-texted seed entry.
    private func seedEntryViaInsights() {
        app.tabBars.buttons["Journal"].tap()
        wait(app.navigationBars["Journal"])
        let hub = any("journal.insightsHistory")
        wait(hub); hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        let field = any("insights.journalText")
        wait(field); field.tap(); field.typeText(seed)
        let save = app.buttons["insights.save"]; wait(save); save.tap()
        _ = seedText()
    }

    /// Journal is the Insights tab root, not an Explore sheet.
    private func openJournalTimeline() {
        app.tabBars.buttons["Journal"].tap()
        returnToJournalRoot()
    }

    /// Opens the seed entry's detail and PROVES the open detail is the seed
    /// entry (exact text) before anything else happens. Fail-closed: a
    /// mismatch aborts the test, so no delete can ever run unverified.
    private func openVerifiedSeedDetail(_ file: StaticString = #filePath, line: UInt = #line) {
        seedText(file, line: line).tap()
        let detail = any("journal.detail.text")
        wait(detail, 10, file: file, line: line)
        let shown = (detail.value as? String) ?? detail.label
        XCTAssertTrue(shown.contains(seed),
                      "refusing to act: open detail is not the seed entry (identity unverified)",
                      file: file, line: line)
    }

    /// Deletes the currently open, identity-verified seed entry via its own
    /// detail menu. Callers must have passed openVerifiedSeedDetail first.
    private func deleteVerifiedSeedFromOpenDetail() {
        let more = app.buttons["journal.detail.menu"].firstMatch
        wait(more); more.tap()
        let del = app.buttons["Delete"].firstMatch
        wait(del, 5); del.tap()
        let confirm = app.buttons["Delete"].firstMatch
        wait(confirm, 5); confirm.tap()
        wait(app.navigationBars["Journal"], 10)
        gone(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", seed)).firstMatch, 5)
    }

    func testJournalDetailMoreMenuOpens() {
        seedEntryViaInsights()
        returnToJournalRoot()
        openJournalTimeline()
        openVerifiedSeedDetail()
        let more = app.buttons["journal.detail.menu"].firstMatch
        wait(more); more.tap()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "detail More menu must offer Edit")
        XCTAssertTrue(app.buttons["Delete"].exists, "detail More menu must offer Delete")
        shot("journal-detail-menu-open")
        // Dismiss without choosing and prove the menu is gone before re-opening it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        gone(edit, 5)
        deleteVerifiedSeedFromOpenDetail()
    }

    func testInsightsEntryContextMenuOpens() {
        seedEntryViaInsights()
        seedText().press(forDuration: 1.2)
        let del = app.buttons["Delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5), "entry context menu must offer Delete")
        shot("insights-entry-context-menu")
        // Dismiss WITHOUT deleting and prove the menu is gone before navigating.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        gone(del, 5)
        returnToJournalRoot()
        openJournalTimeline()
        openVerifiedSeedDetail()
        deleteVerifiedSeedFromOpenDetail()
    }
}
