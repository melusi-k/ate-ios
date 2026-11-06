import XCTest

/// A single fail-closed readiness probe before regression acceptance invocations.
/// This is runner/app launch evidence, not Insights or Settings acceptance.
final class UIRunnerReadinessUITests: XCTestCase {
    func testRunnerCanQueryLaunchedApp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15),
                      "The same UI runner must query the real app before acceptance starts")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ui-runner-readiness"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
