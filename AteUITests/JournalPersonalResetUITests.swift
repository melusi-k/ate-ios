import XCTest

/// User-facing routes against the app's real Journal storage, not a timeline override.
/// Unit tests cover direct A-to-B sign-in, meals, partial failure and writer refusal.
final class JournalPersonalResetUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaJournalMomentEntry", "-qaJournalResetMemoryCredentials"] + extra
        app.launch()
    }
    private func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
    }
    private func tab(_ title: String) {
        let button = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        // Scrolling Settings minimises the native tab bar to its selected tab.
        // Reveal the real tab through content scrolling before its one tap.
        for _ in 0..<6 where !button.exists { app.swipeDown() }
        wait(button); XCTAssertTrue(button.isHittable); button.tap()
    }
    private func signIn() {
        tab("Settings")
        let open = app.buttons["openSignIn"]; wait(open); open.tap()
        let email = app.textFields["authEmail"]; wait(email); email.tap(); email.typeText("qa@example.com")
        let password = app.secureTextFields["authPassword"]; password.tap(); password.typeText("password123")
        app.buttons["authSubmit"].tap()
    }
    private func seededJournal() {
        tab("Journal")
        wait(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Seeded from a Journal moment")).firstMatch)
    }
    private func emptyJournal(_ name: String) {
        tab("Journal")
        wait(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No journal entries yet")).firstMatch)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Seeded from a Journal moment")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSettingsClearAllRemovesVisibleJournal() {
        launch(); seededJournal(); tab("Settings")
        let clear = app.buttons["Clear all"]
        for _ in 0..<6 { if clear.exists && clear.isHittable { break }; app.swipeUp() }
        wait(clear); clear.tap()
        let confirm = app.buttons["Clear all"].firstMatch
        wait(confirm); confirm.tap()
        emptyJournal("journal-after-settings-clear-all")
    }
    func testExplicitSignOutKeepRecipesRemovesVisibleJournal() {
        launch(); signIn(); wait(app.staticTexts["accountEmail"]); seededJournal(); tab("Settings")
        let signOut = app.buttons["signOutButton"]; wait(signOut); signOut.tap()
        let keep = app.buttons["Sign out, keep recipes on this iPhone"]; wait(keep); keep.tap()
        wait(app.buttons["openSignIn"])
        emptyJournal("journal-after-explicit-sign-out-keep-recipes")
    }
    func testExpiredTokenPreservesVisibleJournal() {
        launch(["-qaExpireSession"]); seededJournal(); signIn()
        wait(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Your session expired")).firstMatch)
        seededJournal()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "journal-retained-after-expiry"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
