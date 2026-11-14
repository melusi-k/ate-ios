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
    /// Preserve pixels before any AX query that could itself stall. Step markers
    /// show which property/hierarchy request failed to return in a budget kill.
    private func refreshDiagnostics(_ phase: String, refresh: XCUIElement, status: XCUIElement) {
        let prefix = "SHOPPING-REFRESH-DIAGNOSTIC \(phase)"
        print("\(prefix) screenshot begin \(Date().timeIntervalSince1970)")
        let screenshot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(screenshot: screenshot)
        image.name = "shopping-refresh-\(phase)"; image.lifetime = .keepAlways; add(image)
        // Keep the image recoverable from the individual log as well as xcresult.
        let encoded = screenshot.pngRepresentation.base64EncodedString()
        print("SNAPSHOT-BEGIN shopping-refresh-\(phase) \(encoded.count)")
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 4000, limitedBy: encoded.endIndex)
                ?? encoded.endIndex
            print("SNAPSHOT-CHUNK shopping-refresh-\(phase) \(encoded[index..<end])")
            index = end
        }
        print("SNAPSHOT-END shopping-refresh-\(phase)")
        var lines = ["phase=\(phase)", "deviceOrientation=\(XCUIDevice.shared.orientation.rawValue)"]
        func record(_ name: String, _ read: () -> String) {
            print("\(prefix) \(name) begin \(Date().timeIntervalSince1970)")
            let value = read()
            lines.append("\(name)=\(value)")
            print("\(prefix) \(name)=\(value) \(Date().timeIntervalSince1970)")
        }
        record("app.state") { String(describing: app.state) }
        record("app.frame") { String(describing: app.frame) }
        record("refresh.exists") { String(refresh.exists) }
        if refresh.exists {
            record("refresh.isEnabled") { String(refresh.isEnabled) }
            record("refresh.isHittable") { String(refresh.isHittable) }
            record("refresh.frame") { String(describing: refresh.frame) }
        }
        record("status.exists") { String(status.exists) }
        if status.exists {
            record("status.label") { status.label }
            record("status.frame") { String(describing: status.frame) }
        }
        let sidebar = app.descendants(matching: .any)["sidebar"].firstMatch
        record("sidebar.exists") { String(sidebar.exists) }
        if sidebar.exists {
            record("sidebar.frame") { String(describing: sidebar.frame) }
            record("sidebar.isHittable") { String(sidebar.isHittable) }
        }
        let toggle = app.buttons["sidebarToggle"]
        record("sidebarToggle.exists") { String(toggle.exists) }
        if toggle.exists {
            record("sidebarToggle.label") { toggle.label }
            record("sidebarToggle.frame") { String(describing: toggle.frame) }
        }
        let values = XCTAttachment(string: lines.joined(separator: "\n"))
        values.name = "shopping-refresh-\(phase)-state"; values.lifetime = .keepAlways; add(values)
        print("\(prefix) hierarchy begin \(Date().timeIntervalSince1970)")
        let hierarchy = app.debugDescription
        let tree = XCTAttachment(string: hierarchy)
        tree.name = "shopping-refresh-\(phase)-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        print("\(prefix) hierarchy\n\(hierarchy)\n\(prefix) hierarchy end")
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
        print("SHOPPING-REFRESH tap begin \(Date().timeIntervalSince1970)")
        refresh.tap()
        print("SHOPPING-REFRESH tap returned \(Date().timeIntervalSince1970)")
        // Screenshot only before the waiter: diagnostic AX reads must not consume
        // its unchanged10s completion window or make a failing state recover first.
        shot("shopping-immediately-post-refresh-tap-" + (landscape ? "landscape" : "portrait"))
        // MockSync may complete within one frame; do not require a transient
        // spinner. Require the actual button to be available and success shown.
        let readyResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: refresh)], timeout: 10)
        if readyResult != .completed {
            refreshDiagnostics("post-ready-failure", refresh: refresh, status: status)
        }
        XCTAssertEqual(readyResult, .completed)
        let syncedResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: synced, object: status)], timeout: 10)
        if syncedResult != .completed {
            refreshDiagnostics("post-sync-failure", refresh: refresh, status: status)
        }
        XCTAssertEqual(syncedResult, .completed)
        XCTAssertTrue(status.isHittable)
        shot("shopping-signed-in-after-manual-refresh-" + (landscape ? "landscape" : "portrait"))
    }
    func testSignedOutShoppingPortraitLocalStatus() { localCapture(landscape: false) }
    func testSignedOutShoppingLandscapeLocalStatus() { localCapture(landscape: true) }
    func testSignedInShoppingPortraitStatusAndManualRefresh() { signedInCapture(landscape: false) }
    func testSignedInShoppingLandscapeStatusAndManualRefresh() { signedInCapture(landscape: true) }
}
