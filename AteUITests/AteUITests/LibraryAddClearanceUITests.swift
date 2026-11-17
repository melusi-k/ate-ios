import XCTest

/// Select explicitly on normal-text iPhone 18 Pro and Duo. Real root chrome, no layout overrides.
final class LibraryAddClearanceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        XCUIApplication().terminate()
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testLastEmptyLibraryActionClearsActualAddAndOpensPromptPortrait() { check(.portrait, name: "portrait") }
    func testLastEmptyLibraryActionClearsActualAddAndOpensPromptLandscapeRequest() { check(.landscapeLeft, name: "landscape-request") }
    private func check(_ orientation: UIDeviceOrientation, name: String) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let last = app.buttons["library.firstRecipe.prompt"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        let add = app.buttons["accessoryAdd"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Actual root Add must remain present")
        // Ordinary scroll-to-end setup, not a failed tap retry.
        for _ in 0..<8 {
            if last.isHittable && last.frame.maxY <= add.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, add.frame.minY, "Last action must be entirely above actual floating Add")
        let window = app.windows.firstMatch.frame
        capture("library-add-clear-\(name)-actual-\(Int(window.width))x\(Int(window.height))")
        last.tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["promptEditor"].waitForExistence(timeout: 5), "Last action must open the existing Prompt flow")
        capture("library-last-action-opened-\(name)")
    }
}
