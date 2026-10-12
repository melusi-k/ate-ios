import XCTest

final class CookingTrackerEntryUITests: XCTestCase {
    func testTrackerHasDedicatedTabEntryPoint() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let trackerTab = app.tabBars.buttons["Tracker"]
        XCTAssertTrue(trackerTab.waitForExistence(timeout: 10), "Cooking Tracker should be a first-class tab")
        trackerTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cookingTracker.screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cooking Tracker"].firstMatch.exists)
    }
}
