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
        while !s.isHittable && tries < 8 {
            if s.frame.minY < app.frame.midY { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            tries += 1
        }
        let before = s.value as? String
        for _ in 0..<3 {
            sleep(1) // let scroll momentum settle
            s.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            sleep(1)
            if (s.value as? String) != before { return }
        }
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
        wait(app.staticTexts["aisle.Produce"], 3)
        XCTAssertTrue(app.staticTexts["aisle.Pantry"].exists)
        XCTAssertTrue(app.staticTexts["aisle.Meat & Fish"].exists)
        shot("shopping-by-aisle")
        let honey = app.buttons["Mark honey as bought"]
        var n = 0
        while !honey.isHittable && n < 4 { app.swipeUp(velocity: .slow); n += 1 }
        honey.tap()
        wait(text("1 in the basket"))
        shot("shopping-ticked")
        tapSwitch("toggle.Group by aisle")
        XCTAssertTrue(app.staticTexts["aisle.Produce"].waitForNonExistence(timeout: 3))
        tapSwitch("toggle.Group by aisle")
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

    func openSettingsAccount() {
        app.buttons["Settings"].tap()
        wait(text("Account & sync"))
    }

    func replaceText(_ e: XCUIElement, _ newText: String, placeholder: String) {
        wait(e)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if let v = e.value as? String, !v.isEmpty, v != placeholder {
            e.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        e.typeText(newText)
    }

    func fillAuth(_ email: String, _ password: String?) {
        replaceText(app.textFields["authEmail"], email, placeholder: "Email")
        if let password {
            let p = app.secureTextFields["authPassword"]
            replaceText(p, password, placeholder: (p.placeholderValue ?? ""))
        }
    }

    func signInViaSettings() {
        openSettingsAccount()
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        fillAuth("cook@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Synced"), 8)
    }

    func test12_SignInErrors() {
        launch()
        openSettingsAccount()
        shot("account-signed-out")
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        shot("auth-sign-in")
        // wrong password
        fillAuth("cook@example.com", "wrongpass")
        app.buttons["authSubmit"].tap()
        wait(text("Wrong email or password"), 5)
        shot("auth-error-credentials")
        // show/hide password
        app.buttons["Show password"].tap()
        wait(app.textFields["authPasswordVisible"], 3)
        app.buttons["Hide password"].tap()
        // offline
        fillAuth("offline@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(text("You're offline"), 5)
        shot("auth-error-offline")
        // not confirmed -> pending state with resend
        fillAuth("unconfirmed@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["confirmPending"], 5)
        app.buttons["resendConfirmation"].tap()
        wait(text("Sent again"), 5)
        shot("auth-confirm-pending")
        app.buttons["I've confirmed, sign in"].tap()
        // forgot password
        wait(app.buttons["forgotPassword"], 5)
        app.buttons["forgotPassword"].tap()
        wait(text("Reset your password"))
        app.buttons["sendReset"].tap()
        wait(text("Check your inbox"), 5)
        shot("auth-forgot")
        app.buttons["authClose"].tap()
        wait(app.buttons["openSignIn"], 5)
    }

    func test15_SignUpPendingAndSignInOut() {
        launch()
        openSettingsAccount()
        app.buttons["openSignUp"].tap()
        wait(text("Create your account"))
        fillAuth("pending@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["confirmPending"], 5)
        shot("auth-signup-pending")
        app.buttons["authClose"].tap()
        wait(text("Waiting for you to confirm"), 5)
        // sign in, then sign out keeping data
        app.buttons["openSignIn"].tap()
        fillAuth("cook@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Synced"), 8)
        shot("account-signed-in")
        app.buttons["signOutButton"].tap()
        let keep = app.buttons["Sign out, keep recipes on this iPhone"]
        wait(keep, 5)
        shot("account-sign-out-confirm")
        keep.tap()
        wait(app.buttons["openSignIn"], 5)
        shot("account-signed-out-again")
    }

    func test16_DeleteAccount() {
        launch()
        addPromptRecipe()
        app.buttons["Library"].firstMatch.tap()
        signInViaSettings()
        let del = app.buttons["deleteAccountButton"]
        var n = 0
        while !del.isHittable && n < 6 { app.swipeUp(velocity: .slow); n += 1 }
        del.tap()
        wait(app.alerts.buttons["Continue"], 5)
        app.alerts.buttons["Continue"].tap()
        let field = app.alerts.textFields.firstMatch
        wait(field, 5)
        // wrong word first: nothing is deleted
        field.typeText("delete")
        app.alerts.buttons["Delete account"].tap()
        wait(text("you didn't type DELETE"), 5)
        wait(app.staticTexts["accountEmail"], 3)
        del.tap()
        app.alerts.buttons["Continue"].tap()
        wait(app.alerts.textFields.firstMatch, 5)
        app.alerts.textFields.firstMatch.typeText("DELETE")
        shot("account-delete-confirm")
        app.alerts.buttons["Delete account"].tap()
        wait(app.buttons["onboardingNext"], 8)
        shot("account-deleted-onboarding")
        app.buttons["onboardingSkip"].tap()
        app.buttons["onboardingContinue"].tap()
        wait(text("Nothing saved yet"), 5)
    }

    func test17_Onboarding() {
        launch(["-showOnboarding"])
        wait(text("Any recipe, one clean card"))
        shot("onboarding-1")
        app.buttons["onboardingNext"].tap()
        wait(text("Cook mode with timers"))
        shot("onboarding-2")
        app.buttons["onboardingNext"].tap()
        wait(text("Sync and share"))
        shot("onboarding-3")
        app.buttons["onboardingNext"].tap()
        wait(app.staticTexts["onboardingChoice"])
        XCTAssertTrue(app.buttons["privacyLink"].exists)
        XCTAssertTrue(app.staticTexts["onboardingVersion"].label.contains("(build "))
        shot("onboarding-choice")
        app.buttons["onboardingSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        fillAuth("cook@example.com", "password123")
        app.buttons["authSubmit"].tap()
        wait(text("Your kitchen library"), 8)
        XCTAssertFalse(app.staticTexts["onboardingChoice"].exists)
        // replay from Settings, then continue without account
        openSettingsAccount()
        let replay = app.buttons["replayOnboarding"]
        var n = 0
        while !replay.isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        XCTAssertTrue(app.staticTexts["aboutVersion"].label.contains("(build "))
        let footer = app.buttons["versionFooter"]
        n = 0
        while !footer.isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        XCTAssertTrue(footer.label.contains("backend ploncuhexmwydjxljuhe"), footer.label)
        XCTAssertTrue(footer.label.contains("(build "), footer.label)
        footer.tap()
        wait(text("Version info copied"), 5)
        shot("settings-version-footer")
        n = 0
        while !replay.isHittable && n < 8 { app.swipeDown(velocity: .slow); n += 1 }
        replay.tap()
        wait(text("Any recipe, one clean card"))
        app.buttons["onboardingSkip"].tap()
        app.buttons["onboardingContinue"].tap()
        wait(text("Account & sync"), 5)
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

    // MARK: batch v1.3

    func test18_SwipeContextMenuPullToRefresh() {
        launch()
        addPromptRecipe()
        app.buttons["Library"].firstMatch.tap()
        let row = text("Miso salmon for two")
        wait(row)
        // pull to refresh (signed out → hint)
        app.swipeDown(velocity: .slow)
        wait(text("Sign in from Settings to sync"), 5)
        // context menu
        row.press(forDuration: 1.2)
        wait(app.buttons["Add to shopping list"], 5)
        shot("library-context-menu")
        app.buttons["Add to shopping list"].tap()
        wait(text("Added to your shopping list"), 5)
        // swipe to delete
        row.swipeLeft()
        let del = app.buttons["Delete"].firstMatch
        wait(del, 5)
        shot("library-swipe-delete")
        del.tap()
        wait(app.buttons["Delete recipe"], 5)
        app.buttons["Delete recipe"].tap()
        wait(text("Nothing saved yet"), 5)
    }

    func test19_OfflineAndRetry() {
        launch(["-simulateOffline", "-ateOpenURL", "ate://recipe/offline"])
        wait(app.descendants(matching: .any)["offlineBanner"].firstMatch, 8)
        wait(text("Couldn't load this recipe"), 8)
        wait(text("You're offline"), 3)
        shot("shared-offline-retry")
        app.buttons["sharedRetry"].tap()
        wait(text("Back online soup"), 8)
        shot("shared-after-retry")
    }

    func test20_CameraOptionAndLargeText() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        wait(text("Your kitchen library"))
        shot("a11y-large-text-library")
        app.buttons["Add recipe"].tap()
        app.buttons["Image"].tap()
        wait(app.buttons["takePhoto"])
        shot("add-image-camera-option")
        app.buttons["takePhoto"].tap()
        wait(text("used a sample photo"), 5)
        let gen = app.buttons["generateButton"]
        var n = 0
        while !gen.isHittable && n < 5 { app.swipeUp(velocity: .slow); n += 1 }
        gen.tap()
        wait(text("Review your card"), 15)
        shot("a11y-large-text-review")
    }

    func test21_VoiceCookMode() {
        launch()
        addPromptRecipe()
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        app.buttons["voiceToggle"].tap()
        wait(app.descendants(matching: .any)["voicePanel"].firstMatch, 5)
        let say = app.textFields["voiceTestInput"]
        func speak(_ t: String) { say.tap(); replaceText(say, t, placeholder: "say…"); say.typeText("\n") }
        speak("next")
        wait(text("Step 2 of 4"))
        speak("next please next")
        wait(text("Step 3 of 4"))
        speak("start the timer")
        wait(app.buttons["Pause timer"], 5)
        shot("cook-voice-timer")
        speak("pause timer")
        wait(app.buttons["Start timer"], 5)
        speak("go back")
        wait(text("Step 2 of 4"))
        speak("repeat")
        wait(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'speaking: Step 2'")).firstMatch, 5)
        shot("cook-voice-listening")
        app.buttons["voiceToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["voicePanel"].firstMatch.waitForNonExistence(timeout: 3))
    }
}
