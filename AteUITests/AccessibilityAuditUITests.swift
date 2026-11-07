import XCTest

/// HIG accessibility pass: XCUITest performAccessibilityAudit() on the main screens.
/// Hard-fails on missing labels, small hit regions, traits, Dynamic Type and clipped text at the default size;
/// contrast issues (pixel-sampled, noisy over photos/gradients) and the AX5 sweep are attached for review.
final class AccessibilityAuditUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() { continueAfterFailure = true; XCUIDevice.shared.orientation = .portrait }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch()
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }

    func audit(_ screen: String, strict: Bool = true) throws {
        var log: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let who = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' [\($0.identifier)]" } ?? "system element"
            log.append("\(issue.auditType.rawValue) · \(issue.compactDescription) · \(who)")
            if issue.element == nil { return true }                   // system chrome (status bar, keyboard) is not ours
            if issue.auditType == .contrast { return true }           // recorded below; brand pairs are unit-tested (AccessibilityTests)
            if issue.element?.identifier == "qa.probe" { return true } // invisible test probe
            return !strict
        }
        let a = XCTAttachment(string: log.isEmpty ? "no issues" : log.joined(separator: "\n"))
        a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways; add(a)
    }

    func addRecipe() {
        app.buttons["Add recipe"].tap()
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText("miso salmon")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap()
        XCTAssertTrue(app.buttons["Cook mode"].waitForExistence(timeout: 10))
    }

    func testAuditMainScreens() throws {
        launch()
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        try audit("library-empty")
        addRecipe()
        try audit("recipe-detail")
        app.buttons["Cook mode"].tap()
        XCTAssertTrue(text("Step 1 of").waitForExistence(timeout: 5))
        try audit("cook-mode")
        app.buttons["Exit"].tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try audit("library")
        // Portrait no longer has a More tab; beta pages are reached through Settings.
        // Each destination is identified before it is audited. A missing tab or screen throws and ends the test,
        // so the audit never re-audits whatever screen happens to be showing.
        try openTab("Shopping", expecting: app.navigationBars["Shopping list"])
        try audit("shopping")
        try openTab("Settings", expecting: app.navigationBars["Settings"])
        try audit("settings")
        // Beta pages formerly linked from More (beta channel is the UI-testing default).
        try open(app.buttons["settings.betaTesting"], expecting: app.staticTexts["betaProgress"], named: "Beta testing")
        try audit("beta-testing")
        try open(app.buttons["betaExpectationsLink"], expecting: app.navigationBars["What to expect in this beta"], named: "Beta expectations")
        try audit("beta-expectations")
    }

    struct NavigationFailure: Error, CustomStringConvertible { let description: String }

    /// Selects a tab-bar tab and requires its destination to be on screen; throws instead of falling through.
    private func openTab(_ name: String, expecting destination: XCUIElement) throws {
        let button = app.tabBars.buttons[name]
        guard button.waitForExistence(timeout: 5) else { throw fail("Tab bar has no '\(name)' tab") }
        button.tap()
        guard destination.waitForExistence(timeout: 5) else { throw fail("'\(name)' tab did not show its destination") }
    }

    /// Scrolls the control into view, taps it, and requires the destination to appear.
    private func open(_ control: XCUIElement, expecting destination: XCUIElement, named name: String) throws {
        var swipes = 0
        while !(control.exists && control.isHittable) && swipes < 6 { app.swipeUp(); swipes += 1 }
        guard control.exists, control.isHittable else { throw fail("\(name): entry point is missing or not hittable") }
        control.tap()
        guard destination.waitForExistence(timeout: 10) else { throw fail("\(name) screen did not open") }
    }

    private func fail(_ message: String) -> NavigationFailure {
        XCTFail(message)
        return NavigationFailure(description: message)
    }

    func testAuditOnboarding() throws {
        launch(["-showOnboarding"])
        let dots = app.descendants(matching: .any)["onboardingDots"]
        if dots.waitForExistence(timeout: 5) {
            XCTAssertTrue((dots.value as? String)?.contains("of") == true, "page dots announce 'x of y'")
            try audit("onboarding")
        }
    }

    /// AX5 sweep: largest accessibility text size. Recorded (not gating yet) so clipping can be tracked per build.
    func testAuditLargestDynamicType() throws {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        try audit("ax5-library", strict: false)
        addRecipe()
        try audit("ax5-recipe-detail", strict: false)
        let s = XCTAttachment(screenshot: app.screenshot()); s.name = "ax5-recipe-detail"; s.lifetime = .keepAlways; add(s)
        app.buttons["Cook mode"].tap()
        try audit("ax5-cook-mode", strict: false)
        let c = XCTAttachment(screenshot: app.screenshot()); c.name = "ax5-cook"; c.lifetime = .keepAlways; add(c)
    }
}
