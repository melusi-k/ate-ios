import XCTest

/// Uses existing isolated UI-test startup, MockAuth and MockSync through real
/// Settings sign-in. These are UI/status captures, not server/two-device proof.
final class ShoppingSyncCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetShopping", "-qaResetServer"]
        app.launch()
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func shopping() {
        let tab = app.tabBars.buttons["Shopping"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.navigationBars["Shopping list"].waitForExistence(timeout: 10))
    }
    private func signIn() {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let signIn = app.buttons["openSignIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        let email = app.textFields["authEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 10)); email.tap(); email.typeText("qa@example.com")
        let password = app.secureTextFields["authPassword"]
        XCTAssertTrue(password.exists); password.tap(); password.typeText("password123")
        app.buttons["authSubmit"].tap()
        XCTAssertTrue(app.staticTexts["accountEmail"].waitForExistence(timeout: 8))
    }
    private func localCapture(landscape: Bool) {
        shopping()
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        let local = app.staticTexts["shopping.localOnly"]
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        XCTAssertEqual(local.label, "Saved on this iPhone. Sign in from Settings to sync your shopping list.")
        XCTAssertTrue(local.isHittable)
        XCTAssertFalse(app.buttons["shopping.syncNow"].exists)
        XCTAssertFalse(app.staticTexts["shopping.syncStatus"].exists)
        XCTAssertTrue(app.textFields["shoppingAddField"].isHittable)
        shot("shopping-local-only-" + (landscape ? "landscape" : "portrait"))
    }
    private func signedInCapture(landscape: Bool) {
        signIn(); shopping()
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        let status = app.staticTexts["shopping.syncStatus"]
        let refresh = app.buttons["shopping.syncNow"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["shopping.localOnly"].exists)
        let ready = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: refresh)], timeout: 10), .completed)
        let synced = NSPredicate(format: "label BEGINSWITH %@", "Synced")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: synced, object: status)], timeout: 10), .completed)
        shot("shopping-signed-in-before-refresh-" + (landscape ? "landscape" : "portrait"))
        refresh.tap()
        // MockSync may complete within one frame; do not require a transient
        // spinner. Require the actual button to be available and success shown.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: refresh)], timeout: 10), .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: synced, object: status)], timeout: 10), .completed)
        XCTAssertTrue(status.isHittable)
        shot("shopping-signed-in-after-manual-refresh-" + (landscape ? "landscape" : "portrait"))
    }
    func testSignedOutShoppingPortraitLocalStatus() { localCapture(landscape: false) }
    func testSignedOutShoppingLandscapeLocalStatus() { localCapture(landscape: true) }
    func testSignedInShoppingPortraitStatusAndManualRefresh() { signedInCapture(landscape: false) }
    func testSignedInShoppingLandscapeStatusAndManualRefresh() { signedInCapture(landscape: true) }
}
