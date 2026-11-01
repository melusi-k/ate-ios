import XCTest

/// #245: the Food Journal must be findable in the app's existing navigation.
/// These launch the real app and walk the actual route a user takes:
/// Insights tab -> Food Journal card -> destination link -> Journal timeline,
/// then back. They also guard the constraint from feedback: discovery must NOT
/// add a tab. Screenshots of every step are attached to the result and
/// exported into the log (SNAPSHOT-CHUNK base64) so review sees exactly what
/// shipped, not just assertions.
///
/// Scope note: this covers the access route and naming of the existing journal
/// timeline. The unified Food Journal timeline (combined meals + reflections)
/// is a later phase of #245 and is deliberately not asserted here.
final class JournalDiscoveryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-qaResetInsightLifecycle"] + extra
        app.launch()
        return app
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)",
                      file: file, line: line)
    }

    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func scrollTo(_ element: XCUIElement, max swipes: Int = 25) {
        _ = element.waitForExistence(timeout: 2)
        var n = 0
        while !(element.exists && element.isHittable) && n < swipes { app.swipeUp(); n += 1 }
        n = 0
        while !(element.exists && element.isHittable) && n < swipes * 2 { app.swipeDown(); n += 1 }
    }

    /// Attaches a named screenshot and mirrors it into the log as chunked base64
    /// so the exact rendered pixels can be recovered from CI logs alone.
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let b64 = screenshot.pngRepresentation.base64EncodedString()
        print("SNAPSHOT-BEGIN \(name) \(b64.count)")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SNAPSHOT-CHUNK \(name) \(b64[i..<j])")
            i = j
        }
        print("SNAPSHOT-END \(name)")
    }

    /// The existing tab set. Feedback was explicit that discovery must not
    /// clutter the tab bar, so any new Journal/Food Journal tab fails here.
    private func assertNoJournalTabAdded(file: StaticString = #filePath, line: UInt = #line) {
        wait(app.tabBars.firstMatch, 15)
        for name in ["Library", "Shopping", "Insights", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[name].waitForExistence(timeout: 5),
                          "existing tab missing: \(name)", file: file, line: line)
        }
        XCTAssertFalse(app.tabBars.buttons["Journal"].exists, "a Journal tab must not be added", file: file, line: line)
        XCTAssertFalse(app.tabBars.buttons["Food Journal"].exists, "a Food Journal tab must not be added", file: file, line: line)
    }

    private func openInsights() {
        app.tabBars.buttons["Insights"].tap()
        wait(any("insights.openFoodJournal"), 20)
    }

    func testFoodJournalDiscoveryEmptyState() {
        launch()
        assertNoJournalTabAdded()
        shot("jd-empty-01-tabs")

        openInsights()
        scrollTo(any("insights.openFoodJournal"))
        XCTAssertTrue(any("insights.openFoodJournal").isHittable, "destination link must be visible on Insights")
        XCTAssertTrue(app.staticTexts["Open Food Journal"].waitForExistence(timeout: 3),
                      "empty state must invite opening the Food Journal")
        shot("jd-empty-02-insights-card")

        any("insights.openFoodJournal").tap()
        wait(app.navigationBars["Food Journal"], 10)
        XCTAssertTrue(app.staticTexts["No journal entries yet"].waitForExistence(timeout: 5),
                      "the healthy empty timeline must say so honestly")
        shot("jd-empty-03-journal-destination")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(any("insights.openFoodJournal"), 10)
        shot("jd-empty-04-back-to-insights")
    }

    func testFoodJournalDiscoveryWithEntries() {
        launch(extra: ["-qaJournalMomentEntry"])
        assertNoJournalTabAdded()

        openInsights()
        scrollTo(any("insights.openFoodJournal"))
        XCTAssertTrue(app.staticTexts["See all 1 entries"].waitForExistence(timeout: 3),
                      "populated state must show the entry count")
        shot("jd-entries-01-insights-card")

        any("insights.openFoodJournal").tap()
        wait(app.navigationBars["Food Journal"], 10)
        XCTAssertTrue(app.staticTexts["Seeded from a Journal moment"].waitForExistence(timeout: 5),
                      "the destination must show the actual entries")
        shot("jd-entries-02-journal-destination")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(any("insights.openFoodJournal"), 10)
        shot("jd-entries-03-back-to-insights")
    }
}
