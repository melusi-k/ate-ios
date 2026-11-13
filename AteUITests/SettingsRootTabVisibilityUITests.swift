import XCTest

final class SettingsRootTabVisibilityUITests: XCTestCase {
    func testSettingsScrollKeepsJournalTabVisibleWithoutRevealGesture() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertTrue(settings.isSelected)
        // Intentionally no reverse gesture, back button, retry or alternate query.
        let journal = app.tabBars.buttons.matching(identifier: "Journal")
        XCTAssertEqual(journal.count, 1)
        XCTAssertTrue(journal.element.isHittable)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "settings-scrolled-all-root-tabs-visible"
        evidence.lifetime = .keepAlways
        add(evidence)
        journal.element.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Journal"].isSelected)
    }
}
