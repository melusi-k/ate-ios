import XCTest

final class SettingsClarificationUITests: XCTestCase {
    func testPrivateModeExplanationTracksToggleAndRetainsScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { app.buttons["Settings"].firstMatch.tap() }
        let toggle = app.switches["toggle.Private mode"].firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable, "The actual Private mode switch must be reachable")
        let original = toggle.value as? String
        XCTAssertTrue(original == "0" || original == "1", "Private mode must expose an unambiguous switch value")
        if original == "0" { toggle.tap() }
        let on = NSPredicate(format: "value == %@", "1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: toggle)], timeout: 5), .completed,
                       "A direct switch interaction must establish Private mode ON before testing copy")
        defer { if original == "0", toggle.exists && toggle.isHittable, toggle.value as? String == "1" { toggle.tap() } }
        let status = app.descendants(matching: .any)["settings.aiAvailability"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let updated = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                  "Private mode is blocking new AI recipes", "including demo recipes")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: status)], timeout: 5), .completed,
                       "Private mode ON must update the availability explanation")
        XCTAssertTrue(status.label.contains("Private mode is blocking new AI recipes"), status.label)
        XCTAssertTrue(status.label.contains("including demo recipes"), status.label)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "settings-private-mode-guidance"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
