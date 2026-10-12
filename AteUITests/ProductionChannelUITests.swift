import XCTest

final class ProductionChannelUITests: XCTestCase {
    func testBetaChannelShowsBetaDiagnosticsEntry() {
        let app = XCUIApplication()
        // Make the intended channel explicit; this test must not inherit the production-channel setup.
        app.launchArguments = ["-UITesting", "-qaBetaChannel"]
        app.launch()

        let settingsTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Settings", "Settings")
        ).firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab should remain available")
        settingsTab.tap()
        XCTAssertTrue(app.staticTexts["accountSyncTitle"].waitForExistence(timeout: 10))

        // Settings is a scrolling Form; SwiftUI may not materialize this row until
        // its section is brought onscreen. Scroll to the destination before asserting.
        // Match the NavigationLink itself by identifier; a label-only match can tap
        // its child text without activating the row's navigation action.
        let betaEntry = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", "settings.betaTesting")
        ).firstMatch
        var scrolls = 0
        while !(betaEntry.exists && betaEntry.isHittable) && scrolls < 12 {
            app.swipeUp(velocity: .slow)
            scrolls += 1
        }
        XCTAssertTrue(betaEntry.waitForExistence(timeout: 5) && betaEntry.isHittable,
                      "Beta-channel builds should expose a hittable Beta testing entry in Settings after scrolling. Settings hierarchy: \(app.debugDescription)")
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

        XCTAssertTrue(app.staticTexts["accountSyncTitle"].waitForExistence(timeout: 10))
        // Scroll through Settings before checking absence: a lazy Form may not
        // create lower rows until they enter the viewport.
        for _ in 0..<12 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(app.descendants(matching: .any)["settings.betaTesting"].exists,
                       "Production-channel builds must not expose Beta testing in Settings")
        XCTAssertFalse(app.staticTexts["Beta testing"].exists,
                       "Production-channel builds must not expose the Beta testing screen")
    }
}
