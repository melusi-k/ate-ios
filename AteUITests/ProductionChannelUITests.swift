import XCTest

final class ProductionChannelUITests: XCTestCase {
    func testBetaChannelShowsBetaDiagnosticsEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()

        let settingsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Settings", "Settings")
        ).firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab should remain available")
        settingsTab.tap()
        XCTAssertTrue(app.staticTexts["Account & sync"].waitForExistence(timeout: 10))

        let betaEntry = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "settings.betaTesting", "Beta testing")
        ).firstMatch
        XCTAssertTrue(betaEntry.waitForExistence(timeout: 5) && betaEntry.isHittable,
                      "Beta-channel builds should expose Beta testing in Settings")
        betaEntry.tap()
        XCTAssertTrue(app.staticTexts["betaBuildLabel"].waitForExistence(timeout: 10),
                      "The Settings entry should open the Beta testing dashboard")
    }

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
