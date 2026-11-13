import XCTest

/// Acceptance for the Insights presentation work (audit quick wins): quiet optional Health,
/// unmistakable sample data on every Health-derived surface, a clear next action per insight,
/// cooking-history insights that link back to their recipes, and the Journal-root route to the unified Food Journal.
///
/// Screenshots of the new surfaces are attached and mirrored into the log (SNAPSHOT-CHUNK base64)
/// so review sees exactly what shipped. Visual-inspection shots are captured BEFORE assertions,
/// matching the jt-08 convention.
final class InsightsPresentationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(_ extra: [String] = []) -> XCUIApplication {
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

    private func tab(_ name: String, from: XCUIElement, arrival: XCUIElement) {
        wait(app.tabBars.firstMatch, 15)
        let button = app.tabBars.buttons[name]
        wait(button, 8)
        // Confirm arrival by destination content, not the button's selected state: on this
        // iOS 26 tab bar a tap can be swallowed while the bar is minimized or mid-transition
        // (run-431 evidence: the tap synthesized cleanly and isSelected even read true while
        // the previous tab stayed on screen). A re-tap happens only while the ORIGIN content
        // is still present: a vanished origin means the previous tap did switch and the
        // destination is still rendering, so another tap would hit the now-current tab and
        // pop its stack. Already on the destination means no tap at all. Worst case per
        // call: 3 attempts x (3s arrival wait + 1s settle) + 10s final wait, bounded.
        var attempts = 0
        while !(arrival.exists && arrival.isHittable) && attempts < 3 {
            if attempts > 0 && !from.exists { break }
            button.tap()
            attempts += 1
            _ = arrival.waitForExistence(timeout: 3)
            sleep(1)
        }
        _ = arrival.waitForExistence(timeout: 10)
        XCTAssertTrue(arrival.exists && arrival.isHittable,
                      "the \(name) tab must show its content after tapping it")
    }

    /// The Journal tab root owns reflection; Insights & Cooking History is its one named route.
    private func openInsightsHub() {
        // Destination is the tab ROOT (the Journal tile): a redundant re-tap on the already
        // current tab only pops to that root, so the always-present tab bar is the origin
        // marker and up to 3 taps are safe here.
        tab("Journal", from: app.tabBars.firstMatch, arrival: any("journal.insightsHistory"))
        let hub = any("journal.insightsHistory")
        wait(hub)
        hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
    }

    /// Bounded scroll in one known direction; returns exists && isHittable. Callers assert on the
    /// result, so a miss fails once, explicitly - no retry loops. Pair with resetHubScrollPosition()
    /// whenever an earlier check may have left the hub deep-scrolled; pull-to-refresh rules out
    /// swipe-down resets on this screen.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, _ maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Scrolling inside the landscape split (LandscapeSplitView): app-level swipeUp lands in
    /// the sidebar List and scrolls it while the hub stays put (run-431 evidence: after 8
    /// swipes the sidebar sat at its bottom and the hub had not moved). Drag FIXED coordinates
    /// inside the hub (right) pane instead - app-normalized (0.75, 0.7) -> (0.75, 0.25), a
    /// ~45% screen-height drag per step - so no content anchor has to stay on screen between
    /// iterations. The sidebar occupies the left ~240pt (x < 0.28 normalized), so x = 0.75
    /// sits safely inside the detail pane in either landscape orientation. Bounded, stops as
    /// soon as the target is hittable.
    @discardableResult
    private func scrollHubDownInLandscape(_ element: XCUIElement, _ maxDrags: Int = 12) -> Bool {
        var drags = 0
        while !(element.exists && element.isHittable) && drags < maxDrags {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25))
            start.press(forDuration: 0.01, thenDragTo: end)
            drags += 1
        }
        return element.exists && element.isHittable
    }

    /// Deterministic position reset: pop the hub and push it again so a prior deep scroll can
    /// never hide a target near the top. Model state lives in the shared InsightsModel, so the
    /// repushed screen shows the same content.
    private func resetHubScrollPosition() {
        let title = app.navigationBars["Insights & Cooking History"]
        wait(title)
        let back = title.buttons["Journal"]
        wait(back)
        back.tap()
        wait(app.navigationBars["Journal"])
        let hub = any("journal.insightsHistory")
        wait(hub)
        hub.tap()
        wait(title)
    }

    private func connectHealth() {
        let connect = app.buttons["insights.connect"]
        wait(connect)
        connect.tap()
    }

    // MARK: Sample data is unmistakable on every Health-derived surface

    func testSampleScenarioMarksEveryHealthDerivedSurface() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes"])
        defer { XCUIDevice.shared.orientation = .portrait }
        openInsightsHub()
        connectHealth()
        wait(text("Recovery day"))
        wait(any("insights.sampleBadge"))
        wait(text("Not your personal Health data."))
        // Portrait Library uses list(_:), which has only the navigation Insights tile.
        // Check the portrait Health-derived Recovery day state and its sample marker here.
        let recoveryState = any("insights.state")
        wait(recoveryState)
        XCTAssertTrue(recoveryState.isHittable, "the Recovery day Health state must be reachable once Health is connected")
        wait(any("insights.sampleBadge"))
        shot("ipp-01-sample-marks-body-today")
        // Connecting can scroll the hub down. Reset before the remaining known-downward
        // badge checks so the Suggested meals tile cannot be above the scroll origin.
        resetHubScrollPosition()
        wait(app.navigationBars["Insights & Cooking History"])
        XCTAssertTrue(scrollTo(any("insights.sampleBadge.suggestedMeals")),
                      "the Suggested meals tile must carry the sample marker")
        shot("ipp-01-sample-marks-insights")
        // Reflection moved to the Journal root in #407. Keep the same provenance assertion
        // at its actual destination rather than reviving a duplicate Insights composer.
        let back = app.navigationBars["Insights & Cooking History"].buttons["Journal"]
        wait(back)
        back.tap()
        wait(app.navigationBars["Journal"])
        XCTAssertTrue(scrollTo(any("journal.reflection.sampleBadge")),
                      "the root Reflect on your day composer must carry the sample marker")
        wait(text("These prompts use sample Health data, not your Health readings."))
        shot("ipp-01-sample-marks-journal-root")
        // Compact-height Library uses grid(_:), which still renders TodayHealthCard.
        // Deliberately cover that real surface instead of dropping its provenance checks.
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(any("sidebar"))
        let library = app.buttons["sidebar.Library"]
        wait(library)
        XCTAssertTrue(library.isHittable, "the landscape Library route must be reachable")
        library.tap()
        wait(any("libraryGrid"))
        let card = any("library.todayCard")
        wait(card)
        XCTAssertTrue(card.isHittable, "the Library grid Today card must be present once Health is connected")
        wait(any("library.todayCard.sampleBadge"))
        shot("ipp-01-sample-marks-library-grid-today")
    }

    // MARK: Quiet optional Health

    func testUndecidedHealthIsCompactOptionalSetupAndStillConnects() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes"])
        openInsightsHub()
        wait(text("Apple Health (optional)"))
        let connect = app.buttons["insights.connect"]
        // At normal text the quiet Connect row sits below the tall tracker and progress tiles;
        // tap() auto-scrolls ("Scroll element to visible") but a bare isHittable read does not,
        // so reach the row the way a user would first. scrollTo swipes up (max 8) until the row
        // exists && isHittable and returns exactly that predicate, so this is the old isHittable
        // assertion after a bounded, known-direction scroll rather than a weaker check.
        XCTAssertTrue(scrollTo(connect), "the quiet Connect action must stay tappable")
        shot("ipp-02-quiet-connect-row")
        connect.tap()
        wait(text("Recovery day"))
    }

    func testDeniedHealthIsQuietNoticeWithoutConnect() {
        launch(["-qaMockHealth", "denied", "-qaHealthRecipes"])
        openInsightsHub()
        connectHealth()
        let denied = any("insights.denied")
        wait(denied)
        XCTAssertFalse(app.buttons["insights.connect"].exists,
                       "a denied state routes to Settings; it must not keep offering Connect")
        wait(app.buttons["insights.retry"])
        wait(app.buttons["insights.openSettings"])
        shot("ipp-03-quiet-denied")
    }

    func testUnavailableAndMissingEntitlementAreQuietNoticesWithoutConnect() {
        launch(["-qaMockHealth", "unavailable"])
        openInsightsHub()
        wait(any("insights.unavailable"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
        shot("ipp-04-quiet-unavailable")
        app.terminate()
        launch(["-qaMockHealth", "noEntitlement"])
        openInsightsHub()
        wait(any("insights.entitlementMissing"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
        shot("ipp-04-quiet-entitlement")
    }

    func testConnectedButEmptyHealthKeepsQuietNoDataNotice() {
        launch(["-qaMockHealth", "empty", "-qaHealthRecipes"])
        openInsightsHub()
        connectHealth()
        wait(any("insights.noData"))
        let sample = app.buttons["insights.sampleData"]
        wait(sample, 5)
        sample.tap()
        wait(text("Recovery day"))
        shot("ipp-05-empty-then-sample")
    }

    // MARK: A clear next action per insight

    func testConnectedHealthStateOffersNextMealIdeaAction() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes"])
        openInsightsHub()
        connectHealth()
        wait(text("Recovery day"))
        let action = app.buttons["insights.topMealIdea"]
        XCTAssertTrue(scrollTo(action), "the Health state must offer its next meal idea")
        XCTAssertTrue(action.label.hasPrefix("Next meal idea: "), action.label)
        shot("ipp-06-next-meal-idea")
        action.tap()
        let done = app.buttons["recipeSheet.done"]
        wait(done)
        done.tap()
        wait(text("Recovery day"))
    }

    /// A cooking-history insight must link the recipes that generated it, and those links open the
    /// recipe without recording Health-suggestion beta evidence (source-level flag, not UI-assertable).
    func testCookingHistoryInsightLinksGeneratingRecipe() {
        launch(["-qaResetCookingHistory", "-qaResetInsightLifecycle"])
        addAndCompleteRecipe()
        reopenInsightsFromJournal()
        let action = app.buttons["insights.progress.action.weekly-cooking"]
        XCTAssertTrue(scrollTo(action), "the weekly-cooking insight must be reachable")
        wait(text("From your cooking history"))
        let chip = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "insights.progress.recipe.weekly-cooking.")).firstMatch
        wait(chip)
        shot("ipp-07-history-recipe-link")
        chip.tap()
        let done = app.buttons["recipeSheet.done"]
        wait(done)
        done.tap()
        wait(action)
    }

    // MARK: Journal-root timeline and open-state honesty

    func testJournalRootRoutesToUnifiedTimeline() {
        launch(["-qaMockHealth", "empty"])
        tab("Journal", from: app.tabBars.firstMatch, arrival: any("journal.timelineLink"))
        wait(app.navigationBars["Journal"])
        let link = any("journal.timelineLink")
        XCTAssertTrue(link.exists && link.isHittable, "the Journal root must route to the unified timeline")
        shot("ipp-08-journal-root-timeline-route")
        link.tap()
        wait(app.navigationBars["Food Journal"], 10)
        wait(any("journal.timeline.filter"), 10)
        shot("ipp-08-unified-timeline")
        app.navigationBars["Food Journal"].buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Journal"])
        XCTAssertTrue(any("journal.timelineLink").isHittable, "Back must restore the Journal root route")
    }

    /// Fixture-level honesty: this forces the presented state, not a runtime store failure.
    /// The Journal root now owns the banner; Insights no longer has a duplicate Journal card.
    func testJournalRootNeverPresentsForcedBadOpenAsHealthyEmpty() {
        launch(["-qaJournalOpenState", "unavailable"])
        tab("Journal", from: app.tabBars.firstMatch, arrival: any("journal.timelineLink"))
        wait(app.navigationBars["Journal"])
        let banner = any("journal.openStateBanner")
        XCTAssertTrue(scrollTo(banner), "the Journal root must carry the honest open-state banner")
        XCTAssertTrue(banner.label.contains("Journal unavailable"), banner.label)
        XCTAssertFalse(text("No journal entries yet").exists,
                       "an unavailable journal must not be presented as an empty healthy one")
        XCTAssertFalse(text("No reflections yet").exists,
                       "the removed preview must not supply a false healthy-empty claim")
        shot("ipp-09-forced-unavailable-journal-root")
    }

    // MARK: Compact landscape rotation

    /// The quiet Connect row and the sample markers must survive a landscape round trip at the
    /// normal text size. (Maximum-accessibility-size acceptance was removed from scope by the
    /// owner's call on 2026-11-05; normal-text acceptance remains.) Shots before assertions.
    func testQuietConnectAndSampleMarksSurviveLandscapeRotation() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes"])
        defer { XCUIDevice.shared.orientation = .portrait }
        openInsightsHub()
        let connect = app.buttons["insights.connect"]
        _ = scrollTo(connect)
        shot("ipp-10-quiet-connect")
        XCTAssertTrue(connect.exists, "the quiet Connect action must exist at normal text")
        XCTAssertTrue(connect.isHittable, "the quiet Connect action must stay tappable at normal text")

        XCUIDevice.shared.orientation = .landscapeLeft
        // Landscape replaces the TabView with the sidebar split (verticalSizeClass .compact);
        // swipes fired while that rebuild is still animating are eaten by the transition. The
        // sidebar exists only in the settled landscape layout, so gate on it before resetting
        // and scrolling. The short landscape viewport needs the full bounded scroll budget;
        // the loop still stops as soon as the row is hittable.
        wait(any("sidebar"))
        resetHubScrollPosition()
        _ = scrollHubDownInLandscape(connect)
        shot("ipp-10-landscape-quiet-connect")
        XCTAssertTrue(connect.exists && connect.isHittable,
                      "the quiet Connect action must survive compact landscape")
        XCUIDevice.shared.orientation = .portrait
        // Symmetric gate: the tab bar exists only in the settled portrait TabView layout.
        wait(app.tabBars.firstMatch)
        resetHubScrollPosition()
        let connectAfterRotation = app.buttons["insights.connect"]
        // The connect row sits below the tall tracker and progress tiles; after the reset its
        // direction is known, so one bounded scroll brings it on screen.
        _ = scrollTo(connectAfterRotation)
        XCTAssertTrue(connectAfterRotation.exists && connectAfterRotation.isHittable,
                      "the quiet Connect action must survive the rotation cycle")
        connectAfterRotation.tap()
        wait(text("Recovery day"), 15)

        // The badge sits at the top of the body-today tile, below two tall tiles; reset so the
        // rotation checks' deep position can never hide it, then one bounded scroll in the
        // known-downward direction.
        resetHubScrollPosition()
        let badge = any("insights.sampleBadge")
        _ = scrollTo(badge)
        shot("ipp-10-sample-badge")
        XCTAssertTrue(badge.exists && badge.isHittable, "the sample marker must be reachable at normal text")
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(any("sidebar"))
        resetHubScrollPosition()
        _ = scrollHubDownInLandscape(badge)
        shot("ipp-10-landscape-sample-badge")
        XCTAssertTrue(badge.exists && badge.isHittable, "the sample marker must survive compact landscape")
    }

    // MARK: - Cooking flow helpers (mirrors InsightsAcceptanceUITests' proven journey)

    private func addAndCompleteRecipe() {
        app.buttons["Add recipe"].tap()
        wait(app.staticTexts["Add a recipe"])
        app.buttons["Prompt"].tap()
        let prompt = app.textViews["promptEditor"]
        wait(prompt)
        prompt.tap()
        prompt.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        wait(app.staticTexts["Review your card"], 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)

        app.buttons["Cook mode"].tap()
        var steps = 0
        while !app.buttons["cookFinish"].exists && steps < 6 {
            let next = app.buttons["Next step"]
            wait(next, 5)
            next.tap()
            steps += 1
        }
        let finish = app.buttons["cookFinish"]
        wait(finish, 5)
        finish.tap()
        // The cooking-to-Journal lane's optional reflection offer may present here once bound
        // (first offer under its persisted frequency policy). Decline it exactly as a user can -
        // it is never suppressed through a UI-testing flag. Queried by the offer's unique
        // identifier rather than a shared label; nothing matches until that lane renders it.
        let notNow = app.buttons["cookReflection.notNow"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        }
        wait(app.buttons["Cook mode"], 8)

        // RecipeDetailView hides the tab bar (full-height detail with Cook mode pinned at the
        // bottom). Pop back to the Library root before any tab switch, exactly as a user would.
        // The back button carries the previous screen's title, LibraryView's "Your Kitchen"
        // (L10n libraryTitle; en localization confirmed), the same named-back pattern
        // reopenInsightsFromJournal uses with "Journal".
        let detailBack = app.navigationBars.buttons["Your Kitchen"]
        wait(detailBack)
        detailBack.tap()
        wait(app.navigationBars["Your Kitchen"])
        wait(app.tabBars.firstMatch)

        // Verify the cooking event is visible in the tracker before testing its downstream insight.
        // Destination is the tab ROOT (the Journal tile), so the origin marker is the
        // always-present tab bar, as in openInsightsHub: a redundant re-tap only pops to the
        // tab root, which IS the destination. A screen-specific origin marker here would
        // silently disable the retry whenever the cook flow's exit screen changes.
        tab("Journal", from: app.tabBars.firstMatch, arrival: any("journal.insightsHistory"))
        let hub = any("journal.insightsHistory")
        wait(hub)
        hub.tap()
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
        tab("Library", from: app.navigationBars["Insights & Cooking History"],
            arrival: app.navigationBars["Your Kitchen"])
    }

    /// Switching tabs preserves the pushed hub. Return to Journal explicitly instead of
    /// assuming a second tab selection pops a stack that was not currently selected.
    private func reopenInsightsFromJournal() {
        tab("Journal", from: app.navigationBars["Your Kitchen"],
            arrival: app.navigationBars["Insights & Cooking History"])
        let title = app.navigationBars["Insights & Cooking History"]
        wait(title)
        let back = title.buttons["Journal"]
        wait(back)
        back.tap()
        wait(app.navigationBars["Journal"])
        let hub = any("journal.insightsHistory")
        wait(hub)
        hub.tap()
        wait(title)
    }
    func testSettingsReleaseNotesAndReplayableTourAtNormalText() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        wait(app.tabBars.buttons["Settings"], 15)
        app.tabBars.buttons["Settings"].tap()
        wait(app.navigationBars["Settings"])
        let notes = app.buttons["settings.releaseNotes"]
        for _ in 0..<8 {
            if notes.exists && notes.isHittable { break }
            app.swipeUp()
        }
        wait(notes); XCTAssertTrue(notes.isHittable)
        XCTAssertFalse(app.buttons["settings.roadmap"].exists)
        shot("release-notes-01-settings-normal")
        notes.tap()
        let release = app.buttons["release.product-updates-introduction"]
        wait(release); shot("release-notes-02-list")
        release.tap()
        wait(app.buttons["release.whatsNew"])
        shot("release-notes-03-detail")
        app.buttons["release.whatsNew"].tap()
        wait(any("whatsNew.page"))
        XCTAssertEqual(any("whatsNew.page").label, "1 of 2")
        wait(any("whatsNew.placeholder"))
        shot("release-notes-04-first-page")
        app.buttons["whatsNew.next"].tap()
        XCTAssertEqual(any("whatsNew.page").label, "2 of 2")
        shot("release-notes-05-last-page")
        app.buttons["Back"].tap()
        XCTAssertEqual(any("whatsNew.page").label, "1 of 2")
        app.buttons["whatsNew.close"].tap()
        wait(app.buttons["release.whatsNew"])
        app.buttons["release.whatsNew"].tap()
        wait(any("whatsNew.page"))
        XCTAssertEqual(any("whatsNew.page").label, "1 of 2")
        app.buttons["whatsNew.next"].tap()
        app.buttons["whatsNew.next"].tap()
        wait(app.buttons["release.whatsNew"])
        shot("release-notes-06-replayed-done")
    }

}
