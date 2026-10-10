import XCTest

final class AteUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"] + extra
        app.launch()
        return app
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }

    func tapSwitch(_ id: String) {
        let s = app.switches[id].firstMatch
        wait(s)
        var tries = 0
        while !s.isHittable && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
        s.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// Opens Add sheet, picks a tab, generates via mock and saves; ends on Recipe detail.
    func addRecipe(tab: String, input: ((XCUIApplication) -> Void)?, shotPrefix: String) {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons[tab].tap()
        input?(app)
        shot("\(shotPrefix)-1-input")
        app.buttons["generateButton"].tap()
        wait(text("Review your card"), 15)
        shot("\(shotPrefix)-2-review")
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
    }

    func addPromptRecipe() {
        addRecipe(tab: "Prompt", input: { app in
            let e = app.textViews["promptEditor"]; e.tap(); e.typeText("Miso salmon for two")
        }, shotPrefix: "add-prompt")
    }

    // MARK: tests

    func test01_EmptyLibrary() {
        launch()
        wait(text("Your kitchen library"))
        XCTAssertTrue(text("Nothing saved yet").exists)
        XCTAssertTrue(text("0 recipes saved on this device.").exists)
        shot("library-empty")
        app.buttons["Add recipe"].tap()
        app.buttons["generateButton"].tap()
        wait(text("Paste a recipe link first."), 5)
        shot("add-validation-toast")
    }

    func test02_AddViaLink() {
        launch()
        addRecipe(tab: "Link", input: { app in
            let f = app.textFields["linkField"]; f.tap(); f.typeText("https://example.com/miso")
        }, shotPrefix: "add-link")
        wait(text("Recipe from example.com"))
        shot("detail-after-link")
    }

    func test03_AddViaImage() {
        launch()
        addRecipe(tab: "Image", input: { app in
            app.buttons["sampleImage"].tap()
        }, shotPrefix: "add-image")
        wait(text("Screenshot recipe"))
    }

    func test04_AddViaPromptAndLibraryRow() {
        launch()
        addPromptRecipe()
        app.buttons["Library"].tap()
        wait(text("1 recipe saved on this device."))
        shot("library-one-recipe")
        let search = app.textFields["Search chicken, pasta, vegan…"]
        search.tap(); search.typeText("zzz")
        wait(text("No matches"))
        shot("library-no-matches")
    }

    func test05_DetailScaleEditShopDelete() {
        launch()
        addPromptRecipe()
        shot("detail-x1")
        app.buttons["x2 servings"].tap()
        wait(text("4 servings"))
        shot("detail-x2")

        app.buttons["editButton"].tap()
        let title = app.textFields["editorTitle"]
        wait(title)
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60) + "Edited salmon")
        shot("detail-editing")
        app.buttons["Done"].tap()
        wait(text("Edited salmon"))
        shot("detail-edited")

        app.buttons["Add to shopping list"].tap()
        wait(text("Added to your shopping list"), 5)
        shot("detail-added-to-list")

        app.buttons["deleteButton"].tap()
        let confirm = app.buttons["Delete recipe"]
        wait(confirm)
        shot("detail-delete-confirm")
        confirm.tap()
        wait(text("Nothing saved yet"))
        shot("library-after-delete")
    }

    func test06_CookMode() {
        launch()
        addPromptRecipe()
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        XCTAssertFalse(app.buttons["Back"].isEnabled)
        shot("cook-step1")
        app.buttons["Next step"].tap()
        wait(text("Step 2 of 4"))
        app.buttons["Back"].tap()
        wait(text("Step 1 of 4"))
        app.buttons["Next step"].tap(); app.buttons["Next step"].tap()
        wait(text("Step 3 of 4"))
        wait(text("10:00"))
        app.buttons["Start timer"].tap()
        wait(app.buttons["Pause timer"], 5)
        sleep(2)
        XCTAssertFalse(text("10:00").exists, "timer should count down")
        shot("cook-timer-running")
        app.buttons["Pause timer"].tap()
        app.buttons["Reset timer"].tap()
        wait(text("10:00"))
        app.buttons["Next step"].tap()
        wait(text("Step 4 of 4"))
        XCTAssertFalse(app.buttons["Next step"].isEnabled)
        shot("cook-last-step")
        app.buttons["Exit"].tap()
        wait(app.buttons["Cook mode"])
    }

    func test07_ShoppingList() {
        launch()
        wait(text("Your kitchen library"))
        app.buttons["Shopping list"].tap()
        wait(text("Nothing on the list"))
        shot("shopping-empty")
        app.buttons["Library"].tap()
        addPromptRecipe()
        app.buttons["Add to shopping list"].tap()
        app.buttons["Library"].tap()
        app.buttons["Shopping list"].tap()
        wait(text("5 to buy"))
        let field = app.textFields["shoppingAddField"]
        field.tap(); field.typeText("Lemons")
        app.buttons["Add item"].tap()
        wait(text("6 to buy"))
        app.buttons["Mark honey as bought"].tap()
        wait(text("1 in the basket"))
        shot("shopping-ticked")
        app.buttons["Copy text"].tap()
        wait(text("Copied as text"), 5)
        app.swipeUp()
        shot("shopping-export")
        app.buttons["Share / copy"].tap()
        sleep(2)
        shot("shopping-share-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        sleep(1)
        app.buttons["Clear ticked"].firstMatch.tap()
        wait(text("5 to buy"))
        app.buttons["Clear all"].tap()
        wait(text("Nothing on the list"))
    }

    func test08_Settings() {
        launch()
        app.buttons["Settings"].tap()
        wait(text("Timer notifications"))
        shot("settings-default")
        tapSwitch("toggle.Quiet hours")
        wait(text("From"))
        wait(text("Until"))
        tapSwitch("toggle.Sound")
        XCTAssertEqual(app.switches["toggle.Sound"].value as? String, "0")
        tapSwitch("toggle.Private mode")
        XCTAssertEqual(app.switches["toggle.Private mode"].value as? String, "1")
        shot("settings-changed")
        app.buttons["Library"].tap()
        app.buttons["Add recipe"].tap()
        app.buttons["Prompt"].tap()
        app.buttons["generateButton"].tap()
        wait(text("Private mode is on"), 5)
        shot("add-private-mode-blocked")
    }

    func test09_SharedRecipeDeepLink() {
        launch(["-ateOpenURL", "ate://r/demo"])
        wait(app.buttons["Save to my library"], 15)
        shot("shared-recipe")
        app.buttons["Save to my library"].tap()
        wait(app.buttons["Cook mode"])
        shot("shared-saved-detail")
        app.buttons["Library"].tap()
        wait(text("1 recipe saved on this device."))
    }

    func test11_TimerBar() {
        launch()
        addPromptRecipe()
        app.buttons["Cook mode"].tap()
        app.buttons["Next step"].tap(); app.buttons["Next step"].tap()
        wait(text("Step 3 of 4"))
        app.buttons["Start timer"].tap()
        wait(app.buttons["Pause timer"], 5)
        app.buttons["Exit"].tap()
        let open = app.buttons["timerBarOpen"]
        wait(open, 5)
        shot("timerbar-detail")
        app.buttons["Library"].tap()
        wait(text("Your kitchen library"))
        XCTAssertTrue(open.exists, "timer bar should persist on Library")
        shot("timerbar-library")
        app.buttons["Pause bar timer"].tap()
        wait(app.buttons["Resume bar timer"], 3)
        wait(text("paused"))
        shot("timerbar-paused")
        app.buttons["Resume bar timer"].tap()
        open.tap()
        wait(text("Step 3 of 4"), 5)
        wait(app.buttons["Pause timer"], 3)
        shot("timerbar-returned-to-cook")
        app.buttons["Exit"].tap()
        wait(open, 5)
        app.buttons["Stop bar timer"].tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 3))
        shot("timerbar-stopped")
    }

    func test12_Account() {
        launch()
        app.buttons["Settings"].tap()
        wait(text("Account & sync"))
        shot("account-signed-out")
        let email = app.textFields["accountEmailField"]
        email.tap(); email.typeText("cook@example.com")
        let pw = app.secureTextFields["accountPasswordField"]
        pw.tap(); pw.typeText("wrongpass")
        app.buttons["Sign in"].tap()
        wait(text("Invalid login credentials"), 5)
        shot("account-sign-in-error")
        pw.tap(); pw.typeText("password123")
        app.buttons["Create account"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Synced"), 8)
        shot("account-signed-in")
        app.buttons["Sync now"].tap()
        wait(text("Synced"), 8)
        app.buttons["Sign out"].tap()
        wait(text("Signed out"), 5)
        wait(app.textFields["accountEmailField"], 5)
        shot("account-signed-out-again")
    }

    func test13_ShareOptions() {
        launch()
        addPromptRecipe()
        app.buttons["Share recipe"].tap()
        wait(app.buttons["Share link"], 5)
        XCTAssertTrue(app.buttons["Share as text"].exists)
        shot("share-options")
        app.buttons["Share link"].tap()
        sleep(3)
        shot("share-link-sheet")
    }

    func test14_CustomSchemeRecipeLink() {
        launch(["-ateOpenURL", "ate://recipe/demo"])
        wait(app.buttons["Save to my library"], 15)
        shot("deeplink-ate-recipe-scheme")
    }

    func test10_SharedExpiredAndNotFound() {
        launch(["-ateOpenURL", "ate://r/nope1234"])
        wait(text("This recipe link has expired"), 15)
        shot("shared-expired")
        app.buttons["Open ate"].tap()
        wait(text("Your kitchen library"))

        launch(["-ateOpenURL", "ate://somewhere/else"])
        wait(text("Page not found"), 10)
        shot("not-found-404")
        app.buttons["Go home"].tap()
        wait(text("Your kitchen library"))
    }
}
