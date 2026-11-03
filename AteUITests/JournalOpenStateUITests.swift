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

    /// Failure evidence for the browse-menu route: a screenshot (existing attachment + SNAPSHOT-CHUNK log
    /// mechanism) and a scoped log line with what is actually realized, not the whole app hierarchy.
    private func menuEvidence(_ name: String, item: XCUIElement) {
        shot(name)
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map { "\($0.label)@\($0.frame)" }
        print("MENU-EVIDENCE \(name) collectionViews=\(app.collectionViews.count) collectionsLabel=\(app.staticTexts["Collections"].exists) itemExists=\(item.exists) itemHittable=\(item.exists ? item.isHittable : false) itemFrame=\(item.exists ? "\(item.frame)" : "-") buttons=\(buttons)")
    }

    /// The existing route to the journal timeline: Library tab -> browse menu -> Journal.
    /// Menu items surface as labelled buttons on this runtime (identifiers are not exposed
    /// inside the open menu; see CoverageUITests), so the item is matched by label.
    private func openJournal() {
        wait(app.tabBars.firstMatch, 15)
        app.tabBars.buttons["Library"].tap()
        wait(app.buttons["libraryBrowseMenu"], 10)
        app.buttons["libraryBrowseMenu"].tap()
        // The "Collections" header scrolls out of the realized range after the first swipe (CI run 41631190141,
        // MENU-EVIDENCE: collectionsLabel=false, Journal button realized at y=766 but outside the visible popover).
        // So no label is a stable anchor through scrolling. Find the open menu ONCE, while its "Collections" header
        // (LibraryView Section("Collections"), present only in this menu) is realized, then keep addressing that same
        // container by its position among app.collectionViews instead of re-matching by label after each swipe.
        let header = NSPredicate(format: "label == %@", "Collections")
        let located = app.collectionViews.containing(header).firstMatch
        let menuAppeared = located.waitForExistence(timeout: 10)
        var menuIndex = -1
        if menuAppeared {
            for (i, cv) in app.collectionViews.allElementsBoundByIndex.enumerated()
            where cv.descendants(matching: .any).matching(header).firstMatch.exists { menuIndex = i; break }
        }
        // ASSUMPTION (unproven): the popover's collection view keeps this index while it is open. If the popover is
        // dismissed and the index now resolves to another collection view (e.g. the Library list), menu.exists stays
        // true and does not prove the popover is open. This is not a proof of no false pass. The test relies on the
        // bounded loop, MENU-EVIDENCE and the unchanged assertions (Journal button exists and is hittable, the Journal
        // navigation bar appears after the tap) to fail honestly when the container is not the popover.
        let menu = app.collectionViews.element(boundBy: max(menuIndex, 0))
        let item = menu.descendants(matching: .button).matching(NSPredicate(format: "label == %@", "Journal")).firstMatch
        if !menuAppeared || menuIndex < 0 { menuEvidence("jos-menu-not-realized", item: item) }
        XCTAssertTrue(menuAppeared && menuIndex >= 0, "Missing \(located)")
        // At accessibility text sizes the menu rows grow and "Journal" sits below the fold, where the lazy list
        // has not realized it (run 41617917747 XXXL hierarchy: no Journal button). Scroll the realized menu
        // until the item exists and is hittable. Bounded (8); the assertion below is unchanged.
        _ = item.waitForExistence(timeout: 3)
        var swipes = 0
        while !(item.exists && item.isHittable) && swipes < 8 {
            if !menu.exists { break }   // menu vanished: stop and record evidence below instead of failing blind inside swipeUp
            menu.swipeUp()
            swipes += 1
        }
        if !(item.exists && item.isHittable) {
            menuEvidence("jos-menu-journal-\(item.exists ? "not-hittable" : "not-realized")-after-\(swipes)-swipes", item: item)
        }
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

    func testTimelineFixtureShowsEveryRecordAcrossDays() {
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
    }

    func testTimelineFixtureReflectionsFilterHidesMeals() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(any("journal.timeline.filter"), 10)
        wait(row("Oat porridge"), 10)
        app.buttons["Reflections"].tap()
        wait(row("Soup was the best part"), 10)
        XCTAssertFalse(row("Oat porridge").exists, "the reflections filter hides meals")
        shot("jt-02-reflections-filter")
    }

    func testTimelineFixtureSearchWithNoHitsIsNotAnEmptyJournal() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(row("Oat porridge"), 10)
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

    /// The last fixture entry must scroll fully clear of the floating search bar at the largest text size.
    /// Geometry cannot prove readable text under a translucent bar, so jt-08 is captured BEFORE any assertion for
    /// visual inspection. A missing row, a missing search bar, no clearance after the bounded scroll, or a timeout is
    /// reported as what it is; none of them is assumed to be an app defect.
    func testTimelineFixtureAtLargestTextSizeLastRowClearsSearchBar() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTimeline()
        let nav = app.navigationBars["Food Journal"]   // the same bar openTimeline() waits for
        let searchBar = app.searchFields.firstMatch    // the same query the existing search test uses
        let last = row("Soup was the best part")
        _ = searchBar.waitForExistence(timeout: 10)    // non-asserting; existence is asserted after the screenshot
        // The last row is lazily realized, so it is not waited for before scrolling: the bounded loop brings it in.
        func clear() -> Bool {
            last.exists && last.isHittable && nav.exists && searchBar.exists
                && last.frame.minY >= nav.frame.maxY && last.frame.maxY <= searchBar.frame.minY
        }
        var swipes = 0
        while !clear() && swipes < 6 { app.swipeUp(); swipes += 1 }
        shot("jt-08-fixture-large-text-last-row")
        XCTAssertTrue(nav.exists, "the Food Journal navigation bar must exist (swipes: \(swipes))")
        XCTAssertTrue(searchBar.exists, "the search field must exist (swipes: \(swipes))")
        XCTAssertTrue(last.exists, "the last row was never realized after \(swipes) swipes")
        XCTAssertTrue(clear(),
                      "the last row must lie between the navigation bar and the search bar (swipes: \(swipes), row: \(last.frame), nav: \(nav.frame), bar: \(searchBar.frame), hittable: \(last.isHittable))")
    }
}
