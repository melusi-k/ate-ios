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

    // MARK: More

    func test32_MoreCollectionsToolsAbout() {
        launch()
        addPrompt("Miso salmon for two")
        tab("More")
        wait(app.buttons["more.Recently added"])
        XCTAssertTrue(app.buttons["more.Favourites"].exists || app.buttons["more.Favorites"].exists)
        shot("more-collections")
        app.buttons["more.Recently added"].tap()
        wait(app.tabBars.buttons["Library"], 5)
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected, "collection should open the Library tab")
        wait(text("Miso salmon"), 5)
        shot("more-collection-filtered-library")
        tab("More")
        let export = app.buttons["more.export"]; scrollTo(export); wait(export, 3)
        XCTAssertTrue(app.buttons["more.import"].exists)
        XCTAssertTrue(app.buttons["replayOnboarding"].exists)
        shot("more-tools")
        export.tap(); sleep(2); shot("more-export-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        let about = app.staticTexts["aboutVersion"]; scrollTo(about); wait(about, 3)
        XCTAssertTrue(about.label.contains("(build "))
        XCTAssertTrue(app.staticTexts["aiTransparency"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["aiDiagnostics"].firstMatch.exists)
        shot("more-about")
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

    // MARK: Beta testing screen

    func test35_BetaScreenManualExportReset() {
        launch(["-qaCIResults"])
        tab("More")
        app.buttons["more.betaTesting"].tap()
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
        tab("More")
        let row = app.buttons["more.insights"]
        scrollTo(row); row.tap()
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
}
