import XCTest

final class ProductionChannelUITests: XCTestCase {
    func testProductionChannelHidesBetaDiagnostics() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaProductionChannel"]
        app.launch()

        let settingsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Settings", "Settings")
        ).firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab should remain available")
        settingsTab.tap()

        XCTAssertTrue(app.staticTexts["Account & sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.betaTesting"].exists,
                       "Production-channel builds must not expose Beta testing in Settings")
        XCTAssertFalse(app.staticTexts["Beta testing"].exists,
                       "Production-channel builds must not expose the Beta testing screen")
    }
}
