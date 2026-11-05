import XCTest

final class SettingsClarificationUITests: XCTestCase {
    func testPrivateModeExplanationTracksToggleAndRetainsScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { app.buttons["Settings"].firstMatch.tap() }
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Private mode")).firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        if original != "1" { toggle.tap() }
        defer { if original != "1", toggle.exists && toggle.isHittable { toggle.tap() } }
        let status = app.descendants(matching: .any)["settings.aiAvailability"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Private mode is blocking new AI recipes"), status.label)
        XCTAssertTrue(status.label.contains("including demo recipes"), status.label)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "settings-private-mode-guidance"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
