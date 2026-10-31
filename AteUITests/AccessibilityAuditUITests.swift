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
        for tab in ["Shopping", "More", "Settings"] {
            app.tabBars.buttons[tab].tap(); sleep(1)
            try audit(tab.lowercased())
        }
    }

    func testAuditOnboarding() throws {
        launch(["-showOnboarding"])
        let dots = app.descendants(matching: .any)["onboardingDots"]
        if dots.waitForExistence(timeout: 5) {
            XCTAssertTrue((dots.value as? String)?.contains("of") == true, "page dots announce 'x of y'")
            try audit("onboarding")
        }
    }

    /// #179: the nutrition diary and goals screens must actually be reached and audited -
    /// absent navigation fails the test instead of silently skipping the audit.
    func testAuditNutritionScreens() throws {
        launch(["-resetNutritionDiary", "-resetNutritionGoals"])
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()

        let diaryEntry = app.buttons["settings.nutritionDiary"]
        var diaryScrolls = 0
        while !(diaryEntry.exists && diaryEntry.isHittable) && diaryScrolls < 8 {
            app.swipeUp(velocity: .slow)
            diaryScrolls += 1
        }
        XCTAssertTrue(diaryEntry.waitForExistence(timeout: 10), "Settings must expose the Food diary entry")
        diaryEntry.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10), "Food diary screen must open before auditing")
        try audit("nutrition-diary")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let goalsEntry = app.buttons["settings.nutritionGoals"]
        var goalsScrolls = 0
        while !(goalsEntry.exists && goalsEntry.isHittable) && goalsScrolls < 8 {
            app.swipeUp(velocity: .slow)
            goalsScrolls += 1
        }
        XCTAssertTrue(goalsEntry.waitForExistence(timeout: 10), "Settings must expose the Nutrition goals entry")
        goalsEntry.tap()
        XCTAssertTrue(app.navigationBars["Nutrition goals"].waitForExistence(timeout: 10), "Nutrition goals screen must open before auditing")
        try audit("nutrition-goals")
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
