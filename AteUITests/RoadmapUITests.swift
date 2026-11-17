import XCTest

/// Real Settings route and real UserDefaults persistence. No injected catalog or vote results.
final class RoadmapUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }

    private func openRoadmap() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let row = app.buttons["settings.roadmap"]
        // Ordinary scroll-to-row setup for the lazy Settings Form, never a failed-action retry.
        for _ in 0..<16 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.exists); XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.navigationBars["Roadmap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["roadmap.localOnly"].exists)
    }
    private func shot(_ name: String) {
        let value = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        value.name = name; value.lifetime = .keepAlways; add(value)
    }
    private func openFirstIdea() -> XCUIElement {
        let row = app.buttons["roadmap.card.meal-planning"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("Choose recipes while planning"))
        row.tap()
        XCTAssertTrue(app.staticTexts["roadmap.detail.title"].waitForExistence(timeout: 5))
        return app.buttons["roadmap.vote.meal-planning"]
    }
    func testSettingsListDetailVoteUnvoteAndRealRelaunchPersistence() {
        openRoadmap(); shot("roadmap-list")
        var vote = openFirstIdea()
        XCTAssertTrue(vote.exists); XCTAssertTrue(vote.isHittable)
        XCTAssertGreaterThanOrEqual(vote.frame.height, 44)
        // Start from either legitimate persisted state. Toggle once, then require the inverse state.
        let initiallySaved = (vote.value as? String) == "Local vote saved"
        vote.tap()
        XCTAssertEqual(vote.value as? String, initiallySaved ? "No local vote" : "Local vote saved")
        shot("roadmap-detail-after-toggle")
        app.terminate()
        openRoadmap()
        vote = openFirstIdea()
        XCTAssertEqual(vote.value as? String, initiallySaved ? "No local vote" : "Local vote saved")
        vote.tap()
        XCTAssertEqual(vote.value as? String, initiallySaved ? "Local vote saved" : "No local vote")
        app.terminate()
        openRoadmap()
        vote = openFirstIdea()
        XCTAssertEqual(vote.value as? String, initiallySaved ? "Local vote saved" : "No local vote")
        shot("roadmap-detail-restored-original-local-preference")
    }
}
