import XCTest

/// #245 phase 3: a journal that did not open cleanly must be presented honestly.
/// These launch the real app with a QA-forced open state (`-qaJournalOpenState`,
/// JournalStore.qaForcedOpenState) and verify the banner through the running app's
/// realized accessibility tree, over the actual route a user takes:
/// Library tab -> browse menu -> Journal sheet.
///
/// Why UI tests and not hosted rendering: a UIHostingController hosted in a unit
/// test never realizes SwiftUI's accessibility tree (no accessibility server queries
/// it), so a hierarchy walk returns an empty collection while the pixels render
/// correctly - dogfood run 41272234984 proved exactly that (banner visible in the
/// rendered snapshot, walk empty, "no banner" assertions passing vacuously).
/// Presentation assertions belong in the real app.
///
/// Screenshots of every state are attached to the result and exported into the log
/// (SNAPSHOT-CHUNK base64) so review sees exactly what shipped, not just assertions.
final class JournalOpenStateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"] + extra
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

    private func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
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

    /// The existing route to the journal timeline: Library tab -> browse menu -> Journal.
    /// Menu items surface as labelled buttons on this runtime (identifiers are not exposed
    /// inside the open menu; see CoverageUITests), so the item is matched by label.
    private func openJournal() {
        wait(app.tabBars.firstMatch, 15)
        app.tabBars.buttons["Library"].tap()
        wait(app.buttons["libraryBrowseMenu"], 10)
        app.buttons["libraryBrowseMenu"].tap()
        let menu = app.collectionViews.containing(NSPredicate(format: "label == %@", "Collections")).firstMatch
        let item = menu.descendants(matching: .button).matching(NSPredicate(format: "label == %@", "Journal")).firstMatch
        wait(item, 10)
        item.tap()
        wait(app.navigationBars["Journal"], 10)
    }

    private func banner(_ timeout: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let b = any("journal.openStateBanner")
        XCTAssertTrue(b.waitForExistence(timeout: timeout),
                      "the open-state banner must be exposed", file: file, line: line)
        return b
    }

    func testRecoveredOpenShowsBannerWithBackupName() {
        launch(extra: ["-qaJournalOpenState", "recovered"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal recovered"),
                      "the user must hear the journal was recovered, not see a silent fresh one")
        XCTAssertTrue(b.label.contains("ate-20250101-120000.store"),
                      "the kept backup is named so it can be found in Backups")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "a recovered-empty journal must not be presented as real history")
        shot("jos-01-recovered")
    }

    func testInMemoryFallbackOpenShowsTemporaryWarning() {
        launch(extra: ["-qaJournalOpenState", "fallback"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal is temporary right now"),
                      "the user must hear the journal is temporary")
        XCTAssertTrue(b.label.contains("will disappear when you close Ate"),
                      "the user must hear their saves will not last")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "a temporary journal must not be presented as real history")
        shot("jos-02-fallback")
    }

    func testUnavailableOpenShowsHonestFailure() {
        launch(extra: ["-qaJournalOpenState", "unavailable"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal unavailable"),
                      "the user must hear the journal could not be opened")
        XCTAssertFalse(any("journal.entry").exists,
                       "an unavailable journal must not show entries as if all is well")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "an unavailable journal must not be presented as an empty healthy one")
        // The screen stays navigable: the user is never trapped on a broken journal.
        wait(app.buttons["library.explore.dismiss"], 10)
        shot("jos-03-unavailable")
    }

    func testHealthyOpenShowsNoBanner() {
        launch()
        openJournal()
        XCTAssertFalse(any("journal.openStateBanner").waitForExistence(timeout: 3),
                       "a clean open must not show a recovery banner")
        wait(text("No journal entries yet"), 10)
        shot("jos-04-healthy")
    }
    // MARK: Food Journal timeline (#245 step 4). Fixture states are injected by `-qaJournalTimeline`;
    // the real-store and open-state tests use no fixture. The meal-type menu is NOT UI-tested here (unit-tested only).

    /// Timeline rows are single combined accessibility elements, so match them by identifier and label.
    private func row(_ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "journal.timeline.row")
            .matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private func openTimeline() {
        openJournal()
        wait(app.buttons["journal.timelineLink"], 10)
        app.buttons["journal.timelineLink"].tap()
        wait(app.navigationBars["Food Journal"], 10)
    }

    func testTimelineFixtureShowsEveryRecordThenFilterAndSearchNarrow() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(any("journal.timeline.filter"), 10)
        wait(row("Oat porridge"), 10)
        wait(row("Meal details unavailable"), 10)   // orphan meal stays visible
        wait(row("Soup was the best part"), 10)     // legacy reflection stays visible
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "journal.timeline.row").count, 3,
                       "one row per stored entry, nothing dropped")
        XCTAssertFalse(any("journal.timeline.empty").exists)
        XCTAssertFalse(any("journal.timeline.error").exists)
        shot("jt-01-fixture")
        app.buttons["Reflections"].tap()
        wait(row("Soup was the best part"), 10)
        XCTAssertFalse(row("Oat porridge").exists, "the reflections filter hides meals")
        shot("jt-02-reflections-filter")
        app.buttons["All"].tap()
        let search = app.searchFields.firstMatch
        wait(search, 10)
        search.tap()
        search.typeText("zzzz-no-match")
        wait(any("journal.timeline.noMatches"), 10)
        XCTAssertFalse(any("journal.timeline.empty").exists, "no hits is not an empty journal")
        shot("jt-03-no-matches")
    }

    func testTimelineReadFailureIsAnErrorNotAnEmptyJournal() {
        launch(extra: ["-qaJournalTimeline", "failure"])
        openTimeline()
        wait(any("journal.timeline.error"), 10)
        wait(app.buttons["Try again"], 10)
        XCTAssertFalse(any("journal.timeline.empty").exists, "a read failure must not look like no entries")
        XCTAssertFalse(text("No journal entries yet").exists)
        shot("jt-04-read-failure")
    }

    /// No fixture: the real (in-memory under UI tests) store through FoodJournalStore.timelineItems.
    func testTimelineRealStoreEmptySaysSo() {
        launch()
        openTimeline()
        wait(any("journal.timeline.empty"), 10)
        shot("jt-05-real-store-empty")
    }

    func testTimelineRecoveredOpenStateShowsBannerAndNoEmptyClaim() {
        launch(extra: ["-qaJournalOpenState", "recovered"])
        openTimeline()
        _ = banner()
        XCTAssertFalse(any("journal.timeline.empty").exists, "a recovered-empty journal must not read as real history")
        shot("jt-06-recovered-banner")
    }

    /// Fixture at an accessibility text size: the first row is shown and the filter control stays reachable.
    func testTimelineFixtureAtLargestTextSizeKeepsRowAndFilterReachable() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTimeline()
        wait(row("Oat porridge"), 10)
        XCTAssertTrue(any("journal.timeline.filter").waitForExistence(timeout: 10))
        XCTAssertTrue(any("journal.timeline.filter").isHittable, "the filter must stay tappable at the largest text size")
        shot("jt-07-fixture-large-text")
    }
}
