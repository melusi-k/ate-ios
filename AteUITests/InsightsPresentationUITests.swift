import XCTest

/// Acceptance for the Insights presentation work (audit quick wins): quiet optional Health,
/// unmistakable sample data on every Health-derived surface, a clear next action per insight,
/// cooking-history insights that link back to their recipes, and the unified Food Journal tile.
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

    private func tab(_ name: String) {
        wait(app.tabBars.firstMatch, 15)
        let button = app.tabBars.buttons[name]
        wait(button, 8)
        button.tap()
    }

    /// The Insights tab root is the Journal; Insights & Cooking History is its one named route.
    private func openInsightsHub() {
        tab("Insights")
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
        openInsightsHub()
        connectHealth()
        wait(text("Recovery day"))
        wait(any("insights.sampleBadge"))
        wait(text("Not your personal Health data."))
        // Library first: scrolling the hub minimizes the iOS 26+ tab bar (.onScrollDown), and a
        // minimized bar exposes no sibling tab buttons. Check the Library route before any hub
        // scroll. First Library visit of this launch opens at the top, where the Today card
        // lives; a miss fails here explicitly instead of scrolling blind in one direction.
        tab("Library")
        let card = any("library.todayCard")
        wait(card)
        XCTAssertTrue(card.isHittable, "the Library Today card must be present once Health is connected")
        wait(any("library.todayCard.sampleBadge"))
        shot("ipp-01-sample-marks-library-today")
        // The Insights stack keeps the pushed hub at its top position; the two remaining badge
        // checks scroll in the known-downward direction from there.
        tab("Insights")
        wait(app.navigationBars["Insights & Cooking History"])
        XCTAssertTrue(scrollTo(any("insights.sampleBadge.suggestedMeals")),
                      "the Suggested meals tile must carry the sample marker")
        XCTAssertTrue(scrollTo(any("insights.sampleBadge.dailyReflection")),
                      "the Reflect on your day tile must carry the sample marker")
        shot("ipp-01-sample-marks-insights")
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

    // MARK: Unified Food Journal tile

    func testFoodJournalTileRoutesToUnifiedTimeline() {
        launch(["-qaMockHealth", "empty"])
        openInsightsHub()
        let link = any("insights.journalTimeline")
        XCTAssertTrue(scrollTo(link), "the Food Journal tile must route to the unified timeline")
        shot("ipp-08-food-journal-tile")
        link.tap()
        wait(app.navigationBars["Food Journal"], 10)
        wait(any("journal.timeline.filter"), 10)
        shot("ipp-08-unified-timeline")
        app.navigationBars["Food Journal"].buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Insights & Cooking History"])
    }

    /// Fixture-level honesty: -qaJournalOpenState forces the presented state, it is not a
    /// runtime-injected store failure. Bound-runtime acceptance (tile + reader + banner over the
    /// same actual journal) belongs to central's composition qualification, not this test.
    func testJournalTileNeverPresentsForcedBadOpenAsHealthyEmpty() {
        launch(["-qaJournalOpenState", "unavailable"])
        openInsightsHub()
        let banner = any("journal.openStateBanner")
        XCTAssertTrue(scrollTo(banner), "the tile must carry the honest open-state banner")
        XCTAssertTrue(banner.label.contains("Journal unavailable"), banner.label)
        XCTAssertFalse(text("No reflections yet").exists,
                       "an unavailable journal must not be presented as an empty healthy one")
        shot("ipp-09-forced-unavailable-tile")
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
        resetHubScrollPosition()
        _ = scrollTo(connect, 4)
        shot("ipp-10-landscape-quiet-connect")
        XCTAssertTrue(connect.exists && connect.isHittable,
                      "the quiet Connect action must survive compact landscape")
        XCUIDevice.shared.orientation = .portrait
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
        resetHubScrollPosition()
        _ = scrollTo(badge)
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
        tab("Insights")
        let hub = any("journal.insightsHistory")
        wait(hub)
        hub.tap()
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
        tab("Library")
    }

    /// Switching tabs preserves the pushed hub. Return to Journal explicitly instead of
    /// assuming a second tab selection pops a stack that was not currently selected.
    private func reopenInsightsFromJournal() {
        tab("Insights")
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
}
