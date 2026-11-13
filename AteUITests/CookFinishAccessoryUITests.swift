import XCTest

/// Same pushed one-step host that exposed the overlap on Duo. Also selected by
/// the ordinary account-cooking worker; not hidden behind the Duo opt-in skip.
final class CookFinishAccessoryUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-qaCookJournalHost", "-qaCookJournalNavigation"]
        app.launch()
    }
    override func tearDown() {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "cook-finish-accessory-final-state"; attachment.lifetime = .keepAlways; add(attachment)
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }
    private func assertAndFinish(landscape: Bool) {
        let finish = app.buttons["cookFinish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20))
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        let mini = app.buttons["cookSessionMiniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10), "Retain the actual accessory state that caused the bug")
        let clear = NSPredicate { _, _ in
            finish.exists && finish.isHittable && finish.frame.height > 0 && finish.frame.maxY <= mini.frame.minY
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: clear, object: finish)], timeout: 10), .completed)
        XCTAssertEqual(app.buttons.matching(identifier: "cookFinish").count, 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = landscape ? "cook-finish-clear-of-resume-landscape" : "cook-finish-clear-of-resume-portrait"
        attachment.lifetime = .keepAlways; add(attachment)
        finish.tap()
        XCTAssertTrue(app.staticTexts["cookCompletion.recorded"].waitForExistence(timeout: 10), "The actual Finish tap must record completion, not open Resume")
    }
    func testPushedFinishAboveResumeAccessoryPortrait() { assertAndFinish(landscape: false) }
    func testPushedFinishAboveResumeAccessoryLandscape() { assertAndFinish(landscape: true) }
}
