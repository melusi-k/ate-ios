import XCTest

/// Features without UI coverage until build 49, plus simulator-side Tier A automation
/// (A-SHARE-05 backend down, A-CREATE-05 killed mid-generation, A-AUTH-06 expired-session refresh).
/// Runs as its own ui-suite shard so the whole suite fits the job timeout.
final class CoverageUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch(); return app
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }
    /// Lists load rows lazily, so the target may be above or below: search down, then back up.
    func scrollTo(_ e: XCUIElement, max: Int = 25) {
        _ = e.waitForExistence(timeout: 2)
        var n = 0
        while !(e.exists && e.isHittable) && n < max { app.swipeUp(); n += 1 }
        n = 0
        while !(e.exists && e.isHittable) && n < max * 2 { app.swipeDown(); n += 1 }
    }
    func tab(_ name: String) {
        var n = 0
        while !app.tabBars.firstMatch.exists && n < 4 {
            let bar = app.buttons["backBar"].firstMatch, back = app.navigationBars.buttons.element(boundBy: 0)
            if bar.exists { bar.tap() } else if back.exists { back.tap() }
            sleep(1); n += 1
        }
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap() } else { app.buttons[name].firstMatch.tap() }
    }
    func startPrompt(_ s: String) {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText(s)
        app.buttons["generateButton"].tap()
    }
    func addPrompt(_ s: String) {
        startPrompt(s)
        wait(text("Review your card"), 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
    }
    func replaceText(_ e: XCUIElement, _ newText: String) {
        wait(e); e.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if let v = e.value as? String, !v.isEmpty, v != e.placeholderValue {
            e.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        e.typeText(newText)
    }

    // MARK: covers

    func test31_CoverControlsHeroAndTile() {
        launch(["-qaNoPlayground"])
        startPrompt("Chakalaka")
        wait(text("Review your card"), 15)
        let hero = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(hero, 5)
        XCTAssertFalse(app.buttons["generateCover"].exists, "Generate must be hidden when Image Playground is unavailable")
        sleep(2) // initial cover resolution is async
        if app.buttons["removeCover"].exists { app.buttons["removeCover"].tap(); sleep(1) }
        wait(app.buttons["changeCover"], 3)
        shot("cover-review-tile")
        app.buttons["sampleCover"].tap()
        wait(app.buttons["removeCover"], 5)
        XCTAssertEqual(hero.value as? String, "photo")
        shot("cover-review-photo")
        app.buttons["removeCover"].tap()
        XCTAssertTrue(app.buttons["removeCover"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(hero.value as? String, "tile")
        shot("cover-review-removed")
        app.buttons["sampleCover"].tap()
        wait(app.buttons["removeCover"], 5)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        let detailHero = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(detailHero, 5)
        XCTAssertEqual(detailHero.value as? String, "photo")
        shot("cover-detail-hero")
        // A second recipe without a cover gets the branded tile.
        tab("Library")
        addPrompt("Plain rice")
        let tile = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(tile, 5)
        XCTAssertEqual(tile.value as? String, "tile")
        shot("cover-detail-branded-tile")
    }

    // MARK: Library discovery + Settings tools/About

    func test32_MoreCollectionsToolsAbout() {
        launch()
        addPrompt("Miso salmon for two")
        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        wait(app.buttons["library.collection.Recently added"])
        XCTAssertTrue(app.buttons["library.collection.Favourites"].exists || app.buttons["library.collection.Favorites"].exists)
        shot("library-collections")
        app.buttons["library.collection.Recently added"].tap()
        wait(app.tabBars.buttons["Library"], 5)
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected, "collection should open the Library tab")
        wait(text("Miso salmon"), 5)
        shot("collection-filtered-library")
        tab("Settings")
        let export = app.buttons["settings.export"]; scrollTo(export); wait(export, 3)
        XCTAssertTrue(app.buttons["settings.import"].exists)
        XCTAssertTrue(app.buttons["settings.replayOnboarding"].exists)
        shot("settings-tools")
        export.tap(); sleep(2); shot("more-export-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        let about = app.staticTexts["aboutVersion"]; scrollTo(about); wait(about, 3)
        XCTAssertTrue(about.label.contains("(build "))
        XCTAssertTrue(app.staticTexts["aiTransparency"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["aiDiagnostics"].firstMatch.exists)
        shot("settings-about")
    }

    // MARK: photo dish step

    func test33_WhatDishIsThisSpread() {
        launch(["-qaSpreadPhoto"])
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Image"].tap()
        app.buttons["sampleFoodPhoto"].tap()
        app.buttons["generateButton"].tap()
        wait(app.descendants(matching: .any)["photoDishQuestion"].firstMatch, 10)
        wait(text("What dish is this?"), 3)
        XCTAssertTrue(text("spread of several dishes").exists)
        shot("photo-what-dish-spread")
        app.buttons["mogodu"].tap()
        app.buttons["ujeqe"].tap()
        shot("photo-spread-picked")
        app.buttons["generateButton"].tap()
        wait(text("Review your card"), 15)
        wait(text("Mogodu"), 5)
        shot("photo-spread-review-first")
        // The "Saved 1 more card" toast is transient (2.6 s); the library check below is the real assertion.
        _ = text("Saved 1 more card").waitForExistence(timeout: 4)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        tab("Library")
        wait(text("Ujeqe"), 5)
        wait(text("Mogodu"), 5)
        shot("photo-spread-library")
    }

    // MARK: sign-up

    func openSignUp() {
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        app.segmentedControls["authModePicker"].buttons["Create account"].tap()
    }

    func test34_SignUpStrengthMeterAndExistingEmail() {
        launch()
        openSignUp()
        replaceText(app.textFields["authEmail"], "new@example.com")
        let p = app.secureTextFields["authPassword"]
        replaceText(p, "abc")
        let meter = app.descendants(matching: .any)["passwordStrength"].firstMatch
        wait(meter, 5)
        let reason = app.staticTexts["authSubmitReason"]
        wait(reason, 5)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled, "weak password must disable Create account")
        XCTAssertFalse(reason.label.isEmpty)
        shot("signup-weak-password")
        replaceText(p, "Cooking2026")
        XCTAssertTrue(reason.waitForNonExistence(timeout: 5), "reason should clear for a valid password")
        XCTAssertTrue(app.buttons["authSubmit"].isEnabled)
        shot("signup-strong-password")
        replaceText(app.textFields["authEmail"], "exists@example.com")
        app.buttons["authSubmit"].tap()
        wait(app.buttons["existsSignIn"], 8)
        XCTAssertTrue(app.buttons["existsReset"].exists)
        wait(text("may already exist"), 3)
        shot("signup-existing-email")
        app.buttons["existsSignIn"].tap()
        XCTAssertTrue(app.segmentedControls["authModePicker"].buttons["Sign in"].isSelected)
    }

    func test34b_SignUpRateLimitedShowsMessage() {
        launch()
        openSignUp()
        replaceText(app.textFields["authEmail"], "ratelimit@example.com")
        replaceText(app.secureTextFields["authPassword"], "Cooking2026")
        app.buttons["authSubmit"].tap()
        let err = app.descendants(matching: .any)["authError"].firstMatch
        wait(err, 8)
        XCTAssertTrue(err.label.contains("Email limit"), "rate-limited sign-up must show a visible message, got: \(err.label)")
        shot("signup-rate-limited")
    }

    // MARK: Beta testing screen

    func test35_BetaScreenManualExportReset() {
        launch(["-qaCIResults"])
        tab("Settings")
        app.buttons["settings.betaTesting"].tap()
        wait(app.staticTexts["betaProgress"])
        wait(app.staticTexts["betaCISummary"], 3)
        XCTAssertTrue(app.staticTexts["betaCISummary"].label.contains("1/2"))
        shot("beta-screen")
        let before = passed()
        let row = app.descendants(matching: .any)["beta.A-SYNC-02"].firstMatch
        scrollTo(row); wait(row, 5)
        XCTAssertTrue(row.label.contains("CI"), row.label)
        let manual = app.descendants(matching: .any)["beta.A-AUTH-03"].firstMatch
        scrollTo(manual); manual.tap()
        wait(app.buttons["Pass"], 5)
        app.buttons["Pass"].tap()
        wait(text("pass"), 5)
        shot("beta-item-pass")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<6 { app.swipeDown() }
        wait(text("Tier A: \(before + 1)/"), 5)
        let item2 = app.descendants(matching: .any)["beta.A-AUTH-04"].firstMatch
        scrollTo(item2); item2.tap()
        wait(app.buttons["Fail"], 5); app.buttons["Fail"].tap()
        wait(text("fail"), 5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let export = app.buttons["Export results (JSON + Markdown)"]
        scrollTo(export); export.tap(); sleep(2)
        shot("beta-export-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        let reset = app.buttons["Reset all results"]
        scrollTo(reset); reset.tap()
        let confirm = app.buttons["Reset"].firstMatch
        wait(confirm, 5); confirm.tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        wait(text("Tier A: 0/"), 5)
        shot("beta-reset")
    }

    /// Regression for the reported crash: destructive data clearing must not leave navigation
    /// state that crashes when Settings › Beta testing is opened afterward.
    func test35b_BetaOpensAfterLibraryClear() {
        launch()
        tab("Settings")
        let clear = app.buttons["Clear all"].firstMatch
        scrollTo(clear); wait(clear, 5); clear.tap()
        let confirm = app.buttons["Clear all"].firstMatch
        wait(confirm, 3); confirm.tap()
        wait(text("Library cleared"), 5)
        tab("Settings")
        let beta = app.buttons["settings.betaTesting"]
        wait(beta, 5); beta.tap()
        wait(app.staticTexts["betaProgress"], 8)
        XCTAssertTrue(app.navigationBars.staticTexts["Beta testing"].exists)
    }

    func passed() -> Int {
        let l = app.staticTexts["betaProgress"].label   // "Tier A: 3/44 passed"
        return Int(l.components(separatedBy: ": ").last?.components(separatedBy: "/").first ?? "") ?? -1
    }

    // MARK: Tier A simulator automation

    /// A-SHARE-05: backend errors show the ErrorRetryCard and leave the local library intact.
    func test36_BackendDownRetryCardLibraryIntact() {
        launch(["-qaBackendDown"])
        addPrompt("Keep this stew")        // first generation succeeds, every later one fails
        tab("Library")
        startPrompt("Second dish")
        wait(app.buttons["generateRetry"], 10)
        wait(text("isn't responding"), 3)
        shot("backend-down-retry-card")
        app.buttons["generateRetry"].tap()
        wait(app.buttons["generateRetry"], 10)
        app.swipeDown(velocity: .fast)  // close the sheet
        sleep(1)
        tab("Library")
        wait(text("Keep this stew"), 5)
        // Signed-in sync against a failing server keeps the library too.
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap(); wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "cook@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        sleep(2)
        shot("backend-down-sync")
        tab("Library")
        wait(text("Keep this stew"), 5)
        shot("backend-down-library-intact")
    }

    /// A-CREATE-05: kill the app mid-generation, relaunch → clear "interrupted, retry"; and an unsaved card is restored.
    func test37_KilledMidGenerationRecovers() {
        launch(["-qaPersistDraft", "-qaResetDraft", "-qaSlowGenerate"])
        startPrompt("Umngqusho")
        wait(text("Cooking up your card"), 5)
        sleep(2)
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("interrupted"), 8)
        wait(app.buttons["generateRetry"], 3)
        shot("generation-interrupted-retry")
        app.terminate()
        // Unsaved review card survives a kill.
        launch(["-qaPersistDraft", "-qaResetDraft"])
        startPrompt("Chotlo")
        wait(text("Review your card"), 15)
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("Review your card"), 8)
        wait(text("Restored your unsaved card"), 5)
        shot("generation-draft-restored")
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        XCTAssertFalse(text("Restored your unsaved card").exists, "saved draft must not come back")
    }

    /// A-AUTH-06: an expired access token is refreshed silently and sync still succeeds.
    func test38_ExpiredSessionRefreshes() {
        launch(["-qaExpireOnce"])
        addPrompt("Refresh me")
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap(); wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "cook@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Synced"), 10)
        XCTAssertFalse(text("Your session expired").exists)
        shot("auth-expired-session-refreshed")
    }
}

/// Health insights MVP with mock Health data (`-qaMockHealth`). Extension so it runs in the CoverageUITests shard.
extension CoverageUITests {
    func openInsights(_ scenario: String) {
        launch(["-qaMockHealth", scenario, "-qaHealthRecipes"])
        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        let row = app.buttons["library.insights"]
        wait(row); row.tap()
    }
    func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    /// Connects, checks title + prompts, returns suggestion titles, saves a journal entry.
    @discardableResult
    func runHealthScenario(_ scenario: String, title: String, save: Bool = false) -> [String] {
        openInsights(scenario)
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(text(title))
        let prompt = app.buttons["insights.prompt"].firstMatch; scrollTo(prompt)
        XCTAssertTrue(prompt.exists, "\(scenario): no journal prompt")
        let names = app.buttons.matching(identifier: "insights.suggestion").allElementsBoundByIndex.map(\.label)
        shot("insights-" + scenario)
        if save {
            let field = any("insights.journalText"); scrollTo(field); field.tap(); field.typeText("Note for \(scenario)")
            let b = app.buttons["insights.save"]; scrollTo(b); b.tap()
            wait(any("insights.entry"))
            XCTAssertFalse(any("insights.journalingPicker").exists, "Picker must be hidden without the paid entitlement")
        }
        app.terminate()
        return names
    }
    func testHealthScenarioRecovery() { runHealthScenario("recovery", title: "Recovery day", save: true) }
    func testHealthScenarioLowEnergy() { runHealthScenario("lowEnergy", title: "Low-energy day", save: true) }
    func testHealthScenarioPerformance() { runHealthScenario("performance", title: "Good-energy day", save: true) }
    func testHealthScenarioUnderactive() { runHealthScenario("underactive", title: "Quiet week") }
    func testHealthSuggestionsDifferByState() {
        let a = runHealthScenario("recovery", title: "Recovery day")
        let b = runHealthScenario("underactive", title: "Quiet week")
        XCTAssertFalse(a.isEmpty, "Recovery should suggest meals"); XCTAssertFalse(b.isEmpty, "Underactive should suggest meals")
        XCTAssertNotEqual(a, b, "Recovery and underactive should rank meals differently")
    }
    func testHealthScenarioEmpty() {
        openInsights("empty")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.noData"))
    }
    func testHealthInsightsDeniedAndUnavailable() {
        openInsights("denied")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.denied"))
        app.terminate()
        openInsights("unavailable")
        wait(any("insights.unavailable"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
        app.terminate()
        openInsights("noEntitlement")
        wait(any("insights.entitlementMissing"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
    }
    func testHealthOpenRecipeSheetAndClose() {
        openInsights("recovery")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(text("Recovery day"))
        let sug = app.buttons["insights.suggestion"].firstMatch; scrollTo(sug); sug.tap()
        let done = app.buttons["recipeSheet.done"]; wait(done)
        shot("insights-recipe-sheet")
        // (1) A sheet has only Done: no custom or system "Recipes" back.
        XCTAssertFalse(app.buttons["backBar"].exists, "custom back bar inside the sheet")
        XCTAssertFalse(app.navigationBars.buttons["Recipes"].exists, "back to Recipes inside the sheet")
        XCTAssertFalse(app.buttons["Recipes"].exists, "back to Recipes inside the sheet")
        // (2) Content scrolls clear of Cook mode: the last card ends above the button.
        let cook = app.buttons["Cook mode"]; wait(cook)
        let ask = app.textFields["askField"]
        for _ in 0..<8 where !(ask.exists && ask.isHittable) { app.swipeUp() }
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(ask.isHittable, "last card reachable")
        XCTAssertLessThanOrEqual(ask.frame.maxY, cook.frame.minY + 1, "Cook mode covers the bottom of the content")
        done.tap()
        wait(text("Recovery day"))
        scrollTo(sug); sug.tap(); wait(done)
        app.navigationBars.firstMatch.swipeDown(velocity: .fast)   // swipe-to-dismiss also returns to Insights
        wait(text("Recovery day"))
        XCTAssertFalse(done.exists)
    }

    /// Bottom area is one system: Cook mode sits above the (single) timer bar, the Ask Ate field scrolls clear of both,
    /// and the offline banner lives at the top.
    func testBottomBarsDoNotOverlapRecipeDetail() {
        launch(["-simulateOffline"])
        addPrompt("miso salmon")
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of"))
        app.buttons["Next step"].tap(); app.buttons["Next step"].tap()
        app.buttons["Start timer"].tap()
        wait(app.buttons["Pause timer"], 5)
        app.buttons["Exit"].tap()
        let cook = app.buttons["Cook mode"]; wait(cook)
        let bar = app.buttons["timerBarOpen"].firstMatch
        let banner = app.descendants(matching: .any)["offlineBanner"].firstMatch
        wait(bar, 5); wait(banner, 5)
        shot("detail-bottom-bars")
        XCTAssertLessThan(banner.frame.midY, app.frame.midY, "offline banner belongs at the top")
        // C-FIX-03: the strip sits below the nav bar, never on top of it or the title.
        let nav = app.navigationBars.firstMatch
        if nav.exists { XCTAssertGreaterThanOrEqual(banner.frame.minY + 1, nav.frame.maxY, "offline banner overlaps the nav bar") }
        XCTAssertLessThanOrEqual(cook.frame.maxY, bar.frame.minY + 1, "Cook mode overlaps the timer bar")
        XCTAssertEqual(app.buttons.matching(identifier: "timerBarOpen").count, 1, "timer bar shown once")
        let ask = app.textFields["askField"]
        scrollTo(ask)
        XCTAssertTrue(ask.isHittable)
        XCTAssertFalse(ask.frame.intersects(cook.frame), "Ask Ate field under Cook mode")
        XCTAssertFalse(ask.frame.intersects(bar.frame), "Ask Ate field under the timer bar")
    }

    /// Gap 1: system Back from a recipe and the Beta screen never strands navigation.
    func testSystemBackFromRecipeNeverDead() {
        launch()
        addPrompt("miso salmon")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        wait(back); back.tap()
        wait(app.buttons["Add recipe"])
        XCTAssertFalse(app.buttons["Cook mode"].exists)
        tab("Settings")
        wait(app.buttons["settings.betaTesting"])
        app.buttons["settings.betaTesting"].tap()
        let back2 = app.navigationBars.buttons.element(boundBy: 0)
        wait(back2); back2.tap()
        wait(app.buttons["settings.betaTesting"])
    }
    /// Regression guard (StepTrackerTCA lesson): Connect must still ask for Health when access is undecided.
    func testHealthPermissionPromptAppearsWhenUndecided() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes", "-qaHealthPrompt"])
        tab("Library"); app.buttons["libraryBrowseMenu"].tap(); let row = app.buttons["library.insights"]; wait(row); row.tap()
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        let alert = app.alerts.firstMatch; wait(alert, 5)
        XCTAssertTrue(alert.label.contains("Health"), alert.label)
        alert.buttons["Allow"].tap()
        wait(text("Recovery day"))
    }
    func testHealthEmptyStateSampleDataAction() {
        openInsights("empty")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.noData"))
        let sample = app.buttons["insights.sampleData"]; wait(sample, 5); sample.tap()
        wait(text("Recovery day"))
    }
    /// Journaling Suggestions picker is never presented under UI tests; check the context row instead.
    func testJournalMomentContextRow() {
        launch(["-qaMockHealth", "recovery", "-qaJournalMomentEntry"])
        tab("Library"); app.buttons["libraryBrowseMenu"].tap(); let row = app.buttons["library.insights"]; wait(row); row.tap()
        let ctx = any("insights.entryMomentContext"); scrollTo(ctx); wait(ctx)
        XCTAssertTrue(ctx.label.contains("Dinner at Mama"), ctx.label)
        XCTAssertFalse(any("insights.journalingPicker").exists)
    }
}


extension CoverageUITests {
    func testCookingTrackerMonthNavigationAndSelectedDay() {
        launch(["-qaMockHealth", "empty", "-qaHealthRecipes"])
        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        let insights = app.buttons["library.insights"]
        wait(insights); insights.tap()

        let insightsTitle = app.navigationBars["Today & Journal"]
        wait(insightsTitle)
        wait(app.images["insights.logo"])
        let month = any("tracker.displayedMonth")
        scrollTo(month)
        wait(month)
        let currentMonth = month.label
        XCTAssertGreaterThanOrEqual(month.frame.minY, insightsTitle.frame.minY,
                                    "Tracker content must begin below the shared navigation header")
        app.swipeUp()
        XCTAssertTrue(insightsTitle.exists, "Tracker navigation header must remain present while scrolling")
        let previous = any("tracker.previousMonth")
        scrollTo(previous)
        wait(previous); previous.tap()
        XCTAssertNotEqual(month.label, currentMonth, "Previous month should update the calendar title")

        let next = any("tracker.nextMonth")
        wait(next); next.tap()
        XCTAssertEqual(month.label, currentMonth, "Next month should return to the current month")
        XCTAssertFalse(next.isEnabled, "Future months must not be selectable")

        let day = any("tracker.day.1")
        scrollTo(day); wait(day); day.tap()
        wait(app.navigationBars["Cooked that day"])
        XCTAssertTrue(text("Nothing recorded for this day.").exists,
                      "An unrecorded day should show the explicit empty state")
    }
}

extension CoverageUITests {
    /// Issue #68: root navigation chrome remains visible and large titles do not cover first content.
    func testNavigationHeadersRemainStableOnShoppingAndSettings() {
        launch()
        tab("Shopping")
        let shoppingTitle = app.navigationBars["Shopping list"]
        wait(shoppingTitle)
        wait(app.images["shopping.logo"])
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to buy")).firstMatch
        wait(count)
        XCTAssertGreaterThanOrEqual(count.frame.minY, shoppingTitle.frame.minY,
                                    "Shopping content must begin below the navigation title")
        app.swipeUp()
        XCTAssertTrue(shoppingTitle.exists, "The navigation bar must remain present while Shopping scrolls")

        tab("Settings")
        let settingsTitle = app.navigationBars["Settings"]
        wait(settingsTitle)
        wait(app.images["settings.logo"])
        app.swipeUp()
        XCTAssertTrue(settingsTitle.exists, "The navigation bar must remain present while Settings scrolls")
    }
}
