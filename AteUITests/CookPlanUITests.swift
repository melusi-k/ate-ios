import XCTest

final class CookPlanUITests: XCTestCase {
    func testSavedRecipePlanWithoutReminderCanBeReopenedAndCancelled() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaNutritionFixtures"]
        app.launchArguments += ["-qaCookPlanCancelDiagnostic"]
        app.launch()
        let recipe = app.staticTexts["QA pap and rice"].firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        // Library opens a compact quick-look. Follow its explicit route to real detail
        // before searching for the planning action, which is not mounted in the preview.
        let expand = app.buttons["expandRecipeDetails"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let servings = app.segmentedControls["servingsPicker"]
        XCTAssertTrue(servings.waitForExistence(timeout: 10), "Expansion must mount recipe detail before planning")
        let plan = app.buttons["recipe.plan"]
        for _ in 0..<5 where !plan.isHittable { app.swipeUp() }
        XCTAssertTrue(plan.isHittable)
        plan.tap()
        let reminder = app.switches["cookPlan.reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 10))
        if reminder.value as? String == "1" {
            // SwiftUI exposes the whole Form row as Switch. Its center is blank;
            // touch the actual trailing switch pill, not the row's midpoint.
            reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(reminder.value as? String, "0", "Turn the reminder off before saving the no-reminder plan")
        app.buttons["cookPlan.save"].tap()
        XCTAssertTrue(reminder.waitForNonExistence(timeout: 10), "Save must dismiss the cooking plan sheet before reopening")
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        plan.tap()
        XCTAssertTrue(app.staticTexts["cookPlan.savedDate"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["cookPlan.reminder"].value as? String, "0")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "cook-plan-saved-without-reminder"; shot.lifetime = .keepAlways
        add(shot)
        app.buttons["cookPlan.cancelPlan"].tap()
        captureCancelReceipt(app, "after-original-cancel-tap")
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        plan.tap()
        captureCancelReceipt(app, "before-original-final-assertion")
        XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)
    }
}

extension CookPlanUITests {
    private func captureCancelReceipt(_ app: XCUIApplication, _ phase: String) {
        let editor = app.buttons["cookPlan.save"]
        let detail = app.buttons["recipe.plan"]
        let value: String?
        if editor.exists { value = editor.value as? String }
        else if detail.exists { value = detail.value as? String }
        else { value = nil }
        let body = "COOK-PLAN-CANCEL-RECEIPT phase=\(phase) " + (value ?? "receipt-unavailable")
        print(body)
        let attachment = XCTAttachment(string: body)
        attachment.name = "cook-plan-cancel-receipt-" + phase
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
