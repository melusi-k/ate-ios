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
        let generated = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        generated.name = "draft-quality-before-identity-query"
        generated.lifetime = .keepAlways
        add(generated)
        let repair = app.buttons["repairDraftQuality"]
        XCTAssertTrue(repair.waitForExistence(timeout: 15))
        for _ in 0..<6 where !repair.isHittable { app.swipeUp() }
        XCTAssertTrue(repair.isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "repairDraftQuality").count, 1,
                       "Repair must retain one distinct accessibility identity")
        XCTAssertEqual(app.buttons.matching(identifier: "confirmDraft").count, 1,
                       "Confirm and repair are different actions, not a shared panel identifier")
        XCTAssertFalse(app.buttons["saveRecipe"].isEnabled,
                       "Missing bread must still block saving before repair")
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
        XCTAssertFalse(app.buttons["confirmDraft"].exists,
                       "Repair must resolve the quality gap, not merely remove its own button")
        XCTAssertTrue(app.buttons["saveRecipe"].isEnabled,
                      "Only the repaired draft may become saveable without manual confirmation")
        XCTAssertTrue(app.staticTexts["Tomato bread salad"].firstMatch.exists)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "draft-quality-repaired-after"
        after.lifetime = .keepAlways
        add(after)
    }
}
