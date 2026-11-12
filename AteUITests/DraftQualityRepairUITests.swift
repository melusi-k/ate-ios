import XCTest

/// Synthetic UI wiring, NOT real model/ingredient-quantity acceptance.
final class DraftQualityRepairUITests: XCTestCase {
    func testExplicitRepairKeepsTheDraftAndResolvesTheMissingBreadGap() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaDraftQualityRepair", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let addButton = app.buttons["Add recipe"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()
        app.buttons["Prompt"].firstMatch.tap()
        let field = app.textViews["promptEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Tomato bread salad")
        app.buttons["generateButton"].tap()
        let repair = app.buttons["repairDraftQuality"]
        XCTAssertTrue(repair.waitForExistence(timeout: 15))
        for _ in 0..<6 where !repair.isHittable { app.swipeUp() }
        XCTAssertTrue(repair.isHittable)
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "draft-quality-missing-bread-before"
        before.lifetime = .keepAlways
        add(before)
        repair.tap()
        let gapPanel = app.buttons["repairDraftQuality"]
        let cleared = NSPredicate(format: "exists == false")
        expectation(for: cleared, evaluatedWith: gapPanel)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.staticTexts["repairDraftError"].exists)
        XCTAssertTrue(app.staticTexts["Tomato bread salad"].firstMatch.exists)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "draft-quality-repaired-after"
        after.lifetime = .keepAlways
        add(after)
    }
}
