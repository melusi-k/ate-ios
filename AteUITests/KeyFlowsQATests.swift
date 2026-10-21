import XCTest

/// Mandatory QA gate: the 8 key flows. CI runs this suite on its own and only publishes a release if it passes.
/// Test names are parsed into the QA summary table (testQA<N>_<Flow>).
final class KeyFlowsQATests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: helpers

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"] + extra
        app.launch()
        return app
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "qa-" + name; a.lifetime = .keepAlways; add(a)
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }
    func scrollTo(_ e: XCUIElement, max: Int = 6) {
        var n = 0
        while !(e.exists && e.isHittable) && n < max { app.swipeUp(velocity: .slow); n += 1 }
    }
    /// Recipe detail hides the tab bar (b36), so pop back until it shows, then tap the tab.
    /// SwiftUI's iOS 26 tab API doesn't always expose a tab title as its accessibility identifier;
    /// match the visible label as well, rather than relying on XCUIElement subscript identifier lookup.
    func tab(_ name: String) {
        var n = 0
        while !app.tabBars.firstMatch.exists && n < 4 {
            let bar = app.buttons["backBar"].firstMatch
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if bar.exists { bar.tap() } else if back.exists { back.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))) }
            sleep(1); n += 1
        }
        let tabBar = app.tabBars.firstMatch
        let byLabel = tabBar.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR identifier == %@ OR identifier BEGINSWITH %@", name, name, name, name)).firstMatch
        if byLabel.waitForExistence(timeout: 5) && byLabel.isHittable {
            byLabel.tap()
            return
        }

        let visibleButton = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name)).firstMatch
        XCTAssertTrue(visibleButton.waitForExistence(timeout: 5) && visibleButton.isHittable,
                      "Couldn't find a visible \(name) tab/button. Tab bar: \(tabBar.debugDescription)")
        visibleButton.tap()
    }
    func waitHittable(_ e: XCUIElement, _ t: TimeInterval = 8) {
        let end = Date().addingTimeInterval(t)
        while Date() < end && !(e.exists && e.isHittable) { usleep(250_000) }
    }
    func openAdd(_ tab: String) {
        let add = app.buttons["Add recipe"]
        if !add.waitForExistence(timeout: 4) { self.tab("Library"); _ = add.waitForExistence(timeout: 10) }
        waitHittable(add)
        add.tap()
        wait(text("Add a recipe"))
        app.buttons[tab].firstMatch.tap()
    }
    func generate() {
        let g = app.buttons["generateButton"]; scrollTo(g); g.tap()
    }
    func review(_ timeout: TimeInterval = 15) { wait(text("Review your card"), timeout) }
    func save() { app.buttons["saveRecipe"].tap(); wait(app.buttons["Cook mode"], 10) }
    func replace(_ e: XCUIElement, _ v: String) {
        wait(e); e.tap()
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let cur = e.value as? String, !cur.isEmpty { e.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: cur.count + 2)) }
        e.typeText(v)
    }
    func addPrompt(_ s: String) {
        openAdd("Prompt")
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText(s)
        generate(); review(); save()
    }
    func signIn() {
        tab("Settings")
        wait(app.staticTexts["accountSyncTitle"])
        // Beta-channel visibility has its own focused test. Keep the sync key flow
        // independent of the diagnostics dashboard's long checklist rendering.
        app.buttons["openSignIn"].tap()
        replace(app.textFields["authEmail"], "qa@example.com")
        let p = app.secureTextFields["authPassword"]; p.tap(); p.typeText("password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
    }

    // MARK: 1 — add from URL (JSON-LD page + social caption)

    func testQA1_AddFromURL() {
        launch()
        openAdd("Link")
        let f = app.textFields["linkField"]; f.tap(); f.typeText("https://fixtures.ate.test/jsonld-shakshuka")
        generate(); review()
        wait(text("Weekend shakshuka"))
        XCTAssertTrue(app.descendants(matching: .any)["sourceBadge"].firstMatch.label.contains("Imported from page data"))
        shot("1-url-jsonld-review")
        save()
        openAdd("Link")
        let f2 = app.textFields["linkField"]; f2.tap(); f2.typeText("https://www.instagram.com/reel/qafixture/?igsh=TRACK")
        generate(); review()
        wait(text("Creamy chakalaka pasta"))
        shot("1-url-instagram-caption-review")
        save()
        // friendly fallback when the caption is hidden
        openAdd("Link")
        let f3 = app.textFields["linkField"]; f3.tap(); f3.typeText("https://www.instagram.com/reel/nocaption/")
        generate()
        wait(text("Instagram didn't share the caption"), 10)
        wait(app.buttons["switchToPrompt"])
        shot("1-url-instagram-fallback")
    }

    // MARK: 2 — add from photo (text screenshot + food photo fallback)

    func testQA2_AddFromPhoto() {
        launch()
        openAdd("Image")
        app.buttons["sampleImage"].tap()
        generate(); review()
        shot("2-photo-screenshot-review")
        save()
        openAdd("Image")
        let food = app.buttons["sampleFoodPhoto"]; scrollTo(food); food.tap()
        generate()
        // Either a guessed recipe (badged) or the friendly "couldn't recognise a dish" message — never the old OCR error.
        let guessed = text("Review your card"), friendly = text("Couldn't recognise a dish")
        let deadline = Date().addingTimeInterval(20)
        while !guessed.exists && !friendly.exists && Date() < deadline { usleep(300_000) }
        XCTAssertTrue(guessed.exists || friendly.exists, "food photo produced neither a guess nor the friendly message")
        XCTAssertFalse(text("Couldn't read any text").exists)
        if guessed.exists { XCTAssertTrue(app.descendants(matching: .any)["sourceBadge"].firstMatch.label.contains("Guessed from photo")) }
        shot("2-photo-food-fallback")
    }

    // MARK: 3 + 4 — generate & edit, then save

    func testQA3_GenerateAndEdit() {
        launch()
        openAdd("Prompt")
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText("Lemon chicken traybake")
        generate(); review()
        app.buttons["Edit"].firstMatch.tap()
        replace(app.textFields["editorTitle"], "QA edited traybake")
        let cuisine = app.textFields["editorCuisine"]; scrollTo(cuisine)
        cuisine.tap(); cuisine.typeText("Greek")
        shot("3-edit-before-save")
        app.buttons["Preview"].firstMatch.tap()
        wait(text("QA edited traybake"))
    }

    func testQA4_Save() {
        launch()
        addPrompt("Pea risotto")
        tab("Library")
        wait(text("Pea risotto"), 5)
        XCTAssertFalse(text("Nothing saved yet").exists)
        shot("4-saved-in-library")
    }

    // MARK: 5 — share (link + text)

    func testQA5_Share() {
        launch()
        addPrompt("Shareable soup")
        sleep(3) // let the "Saved to your library" toast clear
        waitHittable(app.buttons["Share recipe"])
        app.buttons["Share recipe"].tap()
        wait(app.buttons["Share link"], 5)
        XCTAssertTrue(app.buttons["Share as text"].waitForExistence(timeout: 3), "Missing \"Share as text\" Button")
        shot("5-share-options")
        app.buttons["Share link"].tap()
        let sheet = app.otherElements["ActivityListView"].firstMatch
        let ok = sheet.waitForExistence(timeout: 8) || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2)
        XCTAssertTrue(ok, "share sheet for the link")
        shot("5-share-link-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        sleep(1)
        waitHittable(app.buttons["Share recipe"])
        app.buttons["Share recipe"].tap()
        wait(app.buttons["Share as text"], 5)
        app.buttons["Share as text"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForExistence(timeout: 8)
                      || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2), "share sheet for text")
        shot("5-share-text-sheet")
    }

    // MARK: 6 — open shared recipe (+ not found / expired)

    func testQA6_OpenShared() {
        launch(["-ateOpenURL", "ate://recipe/demo"])
        wait(app.buttons["Save to my library"], 15)
        shot("6-shared-open")
        app.buttons["Save to my library"].tap()
        wait(app.buttons["Cook mode"], 8)
        launch(["-ateOpenURL", "ate://recipe/nope1234"])
        wait(text("This recipe link has expired"), 15)
        shot("6-shared-expired")
        launch(["-ateOpenURL", "ate://somewhere/else"])
        wait(text("Page not found"), 10)
        shot("6-not-found")
    }

    // MARK: 7 — sync (sign in, edit, sync, second launch pulls)

    func testQA7_SyncAccount() {
        launch(["-qaPersistServer", "-qaResetServer"])
        addPrompt("Synced stew")
        app.buttons["recipeMenu"].tap(); app.buttons["editButton"].tap()
        replace(app.textFields["editorTitle"], "Synced stew v2")
        let editorDone = app.buttons["recipeEditor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: 5), "Recipe editor Done action should exist")
        // Replacing the title leaves the software keyboard open; the editor's
        // bottom action can remain underneath it. Scroll the actual target into
        // view before deciding the control is genuinely not hittable.
        scrollTo(editorDone)
        waitHittable(editorDone, 5)
        if !editorDone.isHittable {
            shot("7-editor-done-not-hittable")
            XCTFail("Recipe editor Done action remained non-hittable after scrolling. UI hierarchy: \(app.debugDescription)")
        }
        editorDone.tap()
        signIn()
        wait(text("Synced"), 10)
        shot("7-sync-device-a")
        app.terminate()
        // second launch: fresh local store, same server
        launch(["-qaPersistServer"])
        tab("Library")
        wait(text("Nothing saved yet"), 5)
        signIn()
        wait(text("Synced"), 10)
        tab("Library")
        wait(text("Synced stew v2"), 10)
        shot("7-sync-device-b-pulled")
    }

    // MARK: 8 — timers (start, pause, resume, timer bar, finish → chime/haptic, Live Activity request)

    func testQA8_Timers() {
        launch(["-qaFastTimers"])
        addPrompt("Timer test salmon")
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        app.buttons["Next step"].tap(); app.buttons["Next step"].tap()
        wait(text("Step 3 of 4"))
        app.buttons["Start timer"].tap()
        wait(app.buttons["Pause timer"], 5)
        let probe = app.staticTexts["qa.probe"]
        XCTAssertTrue(probe.label.contains("la=") && !probe.label.contains("la=0"), "Live Activity requested: \(probe.label)")
        app.buttons["Pause timer"].tap()
        let paused = app.staticTexts["cookTimerValue"].label
        sleep(2)
        XCTAssertEqual(app.staticTexts["cookTimerValue"].label, paused, "paused timer doesn't move")
        app.buttons["Start timer"].tap()   // resume
        wait(app.buttons["Pause timer"], 5)
        shot("8-timer-running")
        app.buttons["Exit"].tap()
        wait(app.buttons["timerBarOpen"].firstMatch, 5)
        shot("8-timer-bar")
        XCTAssertTrue(app.buttons["timerBarOpen"].firstMatch.waitForNonExistence(timeout: 40), "timer finished")
        XCTAssertTrue(probe.label.contains("chime=1"), probe.label)
        XCTAssertTrue(probe.label.contains("haptic=1"), probe.label)
        shot("8-timer-finished")

        // Early exit preserves the untimed cooking session after its timer has completed.
        let miniPlayer = app.buttons["cookSessionMiniPlayer"]
        wait(miniPlayer, 5)
        XCTAssertTrue(miniPlayer.label.contains("Timer test salmon"), miniPlayer.label)
        miniPlayer.tap()
        wait(text("Step 3 of 4"), 5)
        app.buttons["Next step"].tap()
        wait(text("Step 4 of 4"), 5)
        app.buttons["Exit"].tap() // no timer on this step: progress must still survive
        wait(miniPlayer, 5)
        XCTAssertTrue((miniPlayer.value as? String ?? "").contains("Step 4 of 4"), miniPlayer.value as? String ?? "")
        miniPlayer.tap()
        wait(text("Step 4 of 4"), 5)
        app.buttons["Finish cooking"].tap()
        XCTAssertTrue(miniPlayer.waitForNonExistence(timeout: 5), "explicit completion clears the cooking session")
    }

    // MARK: Legal documents

    func testLegalDocumentsOpenInNativeSheets() {
        launch()
        tab("Settings")
        wait(app.buttons["openSignIn"], 10)
        app.buttons["openSignIn"].tap()

        let privacy = app.buttons["privacyLink"]
        wait(privacy, 10)
        privacy.tap()
        wait(app.navigationBars["Privacy Policy"], 10)
        wait(app.webViews.firstMatch, 10)
        app.buttons["legalDocumentClose"].tap()

        let terms = app.buttons["termsLink"]
        wait(terms, 10)
        terms.tap()
        wait(app.navigationBars["Terms of Use"], 10)
        wait(app.otherElements["legalDocumentWebView"], 10)
        app.buttons["legalDocumentClose"].tap()
    }
}
