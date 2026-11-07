import XCTest

/// Focused strict Settings accessibility audit (#74) — DESIGN CANDIDATE FOR REVIEW, not landed.
/// Supplements, never replaces, the full main-screen audit gate (testAuditMainScreens stays
/// selected in the lane and stays red until it genuinely passes within the retained 240s
/// allowance). Audit logic mirrors AccessibilityAuditUITests.audit(_:strict:) verbatim so the
/// strictness contract is identical: performAccessibilityAudit(.all), ignoring only system
/// chrome, contrast (brand pairs unit-tested in AccessibilityTests), and the qa.probe element.
final class SettingsAuditUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    private func audit(_ screen: String, strict: Bool = true) throws {
        var log: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let who = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' [\($0.identifier)]" } ?? "system element"
            log.append("\(issue.auditType.rawValue) · \(issue.compactDescription) · \(who)")
            if issue.element == nil { return true }                    // system chrome is not ours
            if issue.auditType == .contrast { return true }            // brand pairs unit-tested
            if issue.element?.identifier == "qa.probe" { return true } // invisible test probe
            return !strict
        }
        let a = XCTAttachment(string: log.isEmpty ? "no issues" : log.joined(separator: "\n"))
        a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways; add(a)
    }

    /// Strict audit of the reorganised Settings root: account/sync prominence, sync summary,
    /// AI availability explanation, and the first preference sections as rendered (no scrolling).
    func testAuditSettingsRoot() throws {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.staticTexts["settings.syncSummary"].waitForExistence(timeout: 10))
        try audit("settings")   // attaches a11y-audit-settings; strict: any non-exempt issue fails
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-audit-root"; shot.lifetime = .keepAlways; add(shot)
    }
}
