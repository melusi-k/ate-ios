import XCTest

final class CookPlanPickerUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaNutritionFixtures", "-qaResetCookingHistory"]
        app.launch()
    }
    override func tearDown() { app.terminate() }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func libraryEntry() {
        let menu = app.buttons["libraryBrowseMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let plan = app.buttons["library.planCook"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5)); plan.tap()
    }
    private func chooseAndSaveWithoutReminder() {
        let row = app.buttons["cookPlan.pick.qa-nutrition-pap"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable)
        shot("plan-recipe-picker")
        row.tap()
        let reminder = app.switches["cookPlan.reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        if reminder.value as? String == "1" {
            reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(reminder.value as? String, "0")
        app.buttons["cookPlan.save"].tap()
        XCTAssertTrue(reminder.waitForNonExistence(timeout: 5))
    }
    func testLibraryPickerCancelThenSaveReopenAndCancelPlan() {
        libraryEntry()
        app.buttons["cookPlan.pickerCancel"].tap()
        XCTAssertFalse(app.buttons["cookPlan.save"].exists, "Cancelling selection must not open/save a plan")
        libraryEntry(); chooseAndSaveWithoutReminder()
        libraryEntry(); app.buttons["cookPlan.pick.qa-nutrition-pap"].tap()
        XCTAssertTrue(app.staticTexts["cookPlan.savedDate"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["cookPlan.reminder"].value as? String, "0")
        shot("plan-from-library-saved-reopened")
        app.buttons["cookPlan.cancelPlan"].tap()
    }
    func testCalendarPickerUsesSamePlanEditor() {
        let hub = app.buttons["library.todayJournalHub"]
        XCTAssertTrue(hub.waitForExistence(timeout: 10)); hub.tap()
        let plan = app.buttons["tracker.planCook"]
        for _ in 0..<8 {
            if plan.exists && plan.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(plan.isHittable); plan.tap()
        chooseAndSaveWithoutReminder()
        XCTAssertTrue(app.buttons["tracker.planCook"].waitForExistence(timeout: 5))
        shot("calendar-plan-picker-return")
        app.buttons["tracker.planCook"].tap()
        app.buttons["cookPlan.pick.qa-nutrition-pap"].tap()
        XCTAssertTrue(app.buttons["cookPlan.cancelPlan"].waitForExistence(timeout: 5))
        app.buttons["cookPlan.cancelPlan"].tap()
    }
}
