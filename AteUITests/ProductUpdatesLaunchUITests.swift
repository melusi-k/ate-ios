import XCTest

final class ProductUpdatesLaunchUITests: XCTestCase {
    func testUnseenLaunchSwipeDismissRelaunchAndOfflineLocalHistoryAtNormalText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaReleaseNotesLaunch", "-qaReleaseNotesDefaults", "release-tour-ui-" + UUID().uuidString,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let page = app.staticTexts["whatsNew.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        XCTAssertEqual(page.label, "1 of 2")
        capture(app, "release-launch-first-page-normal")
        app.swipeLeft()
        let secondPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 of 2"), object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [secondPage], timeout: 5), .completed)
        capture(app, "release-launch-swiped-last-page-normal")
        app.buttons["whatsNew.close"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        XCTAssertFalse(page.exists, "Dismissed version must not auto-show after relaunch")
        app.tabBars.buttons["Settings"].tap()
        let notes = app.buttons["settings.releaseNotes"]
        for _ in 0..<8 where !notes.isHittable { app.swipeUp() }
        XCTAssertTrue(notes.isHittable)
        notes.tap()
        let release = app.buttons["release.product-updates-introduction"]
        XCTAssertTrue(release.waitForExistence(timeout: 5))
        release.tap()
        XCTAssertTrue(app.buttons["release.whatsNew"].waitForExistence(timeout: 5))
        capture(app, "release-history-after-relaunch-normal")
        app.buttons["release.whatsNew"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.label, "1 of 2", "Seen release remains replayable")
        app.buttons["whatsNew.next"].tap()
        app.buttons["whatsNew.next"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 5))
        app.terminate()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}

extension ProductUpdatesLaunchUITests {
    private func launchApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaReleaseNotesLaunch", "-qaReleaseNotesDefaults", "release-link-ui-" + UUID().uuidString,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        return app
    }
    func testRealColdIncomingLinkOwnsLaunchInsteadOfTour() {
        continueAfterFailure = false
        let app = launchApp()
        app.open(URL(string: "ate://shopping")!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.navigationBars["Shopping list"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["whatsNew.page"].exists)
        capture(app, "release-cold-link-shopping-normal")
        app.terminate()
    }
    func testRealWarmIncomingLinkDismissesTourWithoutConsumingUnseenVersion() {
        continueAfterFailure = false
        let app = launchApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["whatsNew.page"].waitForExistence(timeout: 15))
        app.open(URL(string: "ate://shopping")!)
        XCTAssertTrue(app.navigationBars["Shopping list"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["whatsNew.page"].exists)
        capture(app, "release-warm-link-shopping-normal")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["whatsNew.page"].waitForExistence(timeout: 15), "Incoming interruption must not mark this version seen")
        app.buttons["whatsNew.close"].tap()
        app.terminate()
    }
    func testOnboardingHandoffPresentsUnseenTourOnlyAfterContinue() {
        continueAfterFailure = false
        let app = launchApp(["-showOnboarding"])
        app.launch()
        XCTAssertTrue(app.buttons["onboardingSkip"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["whatsNew.page"].exists)
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.staticTexts["whatsNew.page"].waitForExistence(timeout: 10))
        capture(app, "release-after-onboarding-normal")
        app.buttons["whatsNew.close"].tap()
        app.terminate()
    }
}
