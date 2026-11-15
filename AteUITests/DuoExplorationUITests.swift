import XCTest

/// Manual Duo exploration only. Skipped outside its dedicated xctestrun opt-in;
/// screenshots are observations, not fold-continuity, widget or release acceptance.
final class DuoExplorationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["ATE_DUO_EXPLORATION"] == "1" else {
            throw XCTSkip("Opt-in Duo exploration only; not a qualification pass")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        if ProcessInfo.processInfo.environment["ATE_DUO_EXPLORATION"] == "1", (testRun?.failureCount ?? 0) > 0 {
            shot("duo-failure-state")
        }
        XCUIDevice.shared.orientation = .portrait
        XCUIApplication().terminate()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRootPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"]
        app.launch()
        let add = app.buttons["Add recipe"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "Library root must load before capture")
        shot("duo-root-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Root remains available after rotation")
        shot("duo-root-landscape")
    }

    func testModalCookPortraitAndLandscape() { captureCook(navigation: false) }
    func testPushedCookPortraitAndLandscape() { captureCook(navigation: true) }

    private func captureCook(navigation: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-qaCookJournalHost"]
        if navigation { app.launchArguments.append("-qaCookJournalNavigation") }
        app.launch()
        let finish = app.buttons["cookFinish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20), "Cook Mode fixture must load before capture")
        assertFinishClear(finish, app: app, pushed: navigation)
        shot(navigation ? "duo-cook-pushed-portrait" : "duo-cook-modal-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Cook Mode remains available after rotation")
        assertFinishClear(finish, app: app, pushed: navigation)
        shot(navigation ? "duo-cook-pushed-landscape" : "duo-cook-modal-landscape")
    }
    private func assertFinishClear(_ finish: XCUIElement, app: XCUIApplication, pushed: Bool) {
        let mini = app.buttons["cookSessionMiniPlayer"]
        let clear = NSPredicate { _, _ in
            finish.isHittable && (!pushed || (mini.exists && finish.frame.maxY <= mini.frame.minY))
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: clear, object: finish)], timeout: 10), .completed,
                       "Finish must be hittable and wholly above the retained resume accessory")
    }

}
