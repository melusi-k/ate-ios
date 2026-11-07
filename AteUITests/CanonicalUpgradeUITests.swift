import XCTest

/// Real canonical views, typed diary route and disk-backed synthetic legacy upgrade.
/// This does not activate production composition or prove archive/reset/process-kill safety.
final class CanonicalUpgradeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testLegacyMealAndReflectionAppearAndSurviveAppRelaunchInTypedDiary() {
        let app = XCUIApplication()
        let identity = UUID().uuidString
        app.launchArguments = ["-UITesting", "-qaCanonicalUpgrade", identity]
        app.launch()
        XCTAssertTrue(app.navigationBars["Food Journal"].waitForExistence(timeout: 20))
        let rows = app.descendants(matching: .any).matching(identifier: "journal.timeline.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        // A row identifier may occur on both the row and its accessibility container. Use
        // the visible labels instead of claiming count from an unverified element type.
        let mealRow = rows.matching(NSPredicate(format: "label CONTAINS %@", "Sample upgrade lunch")).firstMatch
        let reflectionRow = rows.matching(NSPredicate(format: "label CONTAINS %@", "Sample reflection before upgrade")).firstMatch
        XCTAssertTrue(mealRow.exists)
        XCTAssertTrue(reflectionRow.exists)
        shot("upgrade-01-real-timeline-meal-and-reflection")
        app.buttons["upgradeQA.diary"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
        let meal = app.buttons["nutritionDiary.entry.24500000-0000-4000-8000-000000000002"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        XCTAssertTrue(meal.label.contains("Sample upgrade lunch"))
        shot("upgrade-02-typed-diary-same-migrated-meal")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Food Journal"].waitForExistence(timeout: 20))
        XCTAssertTrue(mealRow.waitForExistence(timeout: 10))
        XCTAssertTrue(reflectionRow.exists)
        shot("upgrade-03-relaunch-disk-timeline")
        app.buttons["upgradeQA.diary"].tap()
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        meal.tap()
        let food = app.textFields["nutritionDiary.foodName"]
        XCTAssertTrue(food.waitForExistence(timeout: 10))
        XCTAssertEqual(food.value as? String, "Sample upgrade lunch")
        shot("upgrade-04-relaunch-preserved-entry-editor")
        // No production files are deleted. The unique synthetic namespace intentionally
        // remains for diagnostics after a failure and is never reused by another test.
    }
}
