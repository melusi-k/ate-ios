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
        // #245 feedback: the Food Journal must be findable without hunting. Its tile
        // leads the default Insights layout, so the link must work in the first viewport.
        XCTAssertTrue(any("insights.openFoodJournal").isHittable,
                      "destination link must be visible in the initial Insights viewport, without scrolling")
        XCTAssertTrue(app.staticTexts["Open Food Journal"].waitForExistence(timeout: 3),
                      "empty state must invite opening the Food Journal")
        // The Insights root keeps its contextual Add accessory.
        XCTAssertTrue(any("accessoryAdd").waitForExistence(timeout: 3),
                      "Insights root must keep its Add accessory")
        shot("jd-empty-02-insights-card")

        any("insights.openFoodJournal").tap()
        wait(app.navigationBars["Food Journal"], 10)
        XCTAssertTrue(app.staticTexts["No journal entries yet"].waitForExistence(timeout: 5),
                      "the healthy empty timeline must say so honestly")
        // The pushed journal destination has no Add action of its own: no accessory
        // control may linger there as a blank placeholder. The standard tab bar stays.
        XCTAssertFalse(any("accessoryAdd").exists, "the journal destination must not show an Add accessory")
        XCTAssertFalse(any("bottomAccessory").exists, "the journal destination must not show the bottom accessory")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "the journal destination keeps the standard tab bar")
        shot("jd-empty-03-journal-destination")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(any("insights.openFoodJournal"), 10)
        // Returning to the root must restore its chrome.
        XCTAssertTrue(any("accessoryAdd").waitForExistence(timeout: 5),
                      "the Add accessory must be restored when back at the Insights root")
        shot("jd-empty-04-back-to-insights")
    }

    /// Root view-state identity across the push/back round trip: the accessory gating
    /// must not rebuild the tab hierarchy and drop in-progress root state. The probe is
    /// the user-visible one - an in-progress journal draft typed on the Insights root
    /// before the push must still be there after returning. The reflection composer only
    /// renders once Health is connected (InsightsModel.context is nil until then), so
    /// this runs with the established mock-Health fixture (CoverageUITests precedent)
    /// and drives the multi-line composer through type-agnostic queries: it is not
    /// exposed as XCUIElementTypeTextField.
    func testJournalDraftSurvivesDestinationRoundTrip() {
        launch(extra: ["-qaMockHealth", "recovery", "-qaHealthRecipes"])
        openInsights()
        let connect = app.buttons["insights.connect"]
        scrollTo(connect)
        XCTAssertTrue(connect.exists, "mock Health must offer the connect action")
        connect.tap()
        let composer = any("insights.journalText")
        scrollTo(composer)
        XCTAssertTrue(composer.waitForExistence(timeout: 5),
                      "the reflection composer must render once Health is connected")
        composer.tap()
        app.typeText("continuity draft")
        shot("jd-continuity-01-draft")

        let link = any("insights.openFoodJournal")
        scrollTo(link)
        // Pixel evidence of the exact state at tap time (keyboard, link position).
        shot("jd-continuity-02-pre-tap")
        link.tap()
        // With the composer focused, the first tap can be consumed resigning the
        // keyboard instead of activating the link (CI run 41283944646: tap
        // synthesized, no navigation). Re-tap only if no navigation happened AND
        // the link is still on screen - after a successful push the link leaves
        // the accessibility tree, so the second tap never fires spuriously.
        if !app.navigationBars["Food Journal"].waitForExistence(timeout: 3), link.waitForExistence(timeout: 2) {
            link.tap()
        }
        wait(app.navigationBars["Food Journal"], 10)
        XCTAssertFalse(any("accessoryAdd").exists, "the journal destination must not show an Add accessory")
        XCTAssertFalse(any("bottomAccessory").exists, "the journal destination must not show the bottom accessory")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "the journal destination keeps the standard tab bar")
        shot("jd-continuity-03-destination")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(any("insights.openFoodJournal"), 10)
        XCTAssertTrue(any("accessoryAdd").waitForExistence(timeout: 5),
                      "the Add accessory must be restored when back at the Insights root")
        let composerAfter = any("insights.journalText")
        scrollTo(composerAfter)
        let draftValue = composerAfter.value as? String ?? ""
        XCTAssertTrue(draftValue.contains("continuity draft"),
                      "root state must survive push/back; journalText now holds: \(draftValue)")
        shot("jd-continuity-04-back-draft-survives")
    }

    func testFoodJournalDiscoveryWithEntries() {
        launch(extra: ["-qaJournalMomentEntry"])
        assertNoJournalTabAdded()

        openInsights()
        XCTAssertTrue(any("insights.openFoodJournal").isHittable,
                      "destination link must be visible in the initial Insights viewport, without scrolling")
        XCTAssertTrue(app.staticTexts["View entry"].waitForExistence(timeout: 3),
                      "a single entry must read 'View entry', never 'See all 1 entries'")
        shot("jd-entries-01-insights-card")

        any("insights.openFoodJournal").tap()
        wait(app.navigationBars["Food Journal"], 10)
        XCTAssertTrue(app.staticTexts["Seeded from a Journal moment"].waitForExistence(timeout: 5),
                      "the destination must show the actual entries")
        XCTAssertFalse(any("accessoryAdd").exists, "the journal destination must not show an Add accessory")
        shot("jd-entries-02-journal-destination")

        // The entry itself opens its own detail and comes back.
        any("journal.entry").tap()
        wait(app.navigationBars["Journal entry"], 10)
        XCTAssertTrue(any("journal.detail.text").waitForExistence(timeout: 5),
                      "the entry detail must show the full entry text")
        XCTAssertFalse(any("accessoryAdd").exists, "the entry detail must not show an Add accessory")
        shot("jd-entries-03-entry-detail")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Food Journal"], 10)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(any("insights.openFoodJournal"), 10)
        XCTAssertTrue(any("accessoryAdd").waitForExistence(timeout: 5),
                      "the Add accessory must be restored when back at the Insights root")
        shot("jd-entries-04-back-to-insights")
    }
}
