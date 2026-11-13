import XCTest

final class CookSharedStepUITests: XCTestCase {
    func testExternalSharedStepChangeWhileCookIsOpenUpdatesCurrentStep() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaExternalCookStep"]
        app.launch()
        app.buttons["Add recipe"].tap()
        app.buttons["Prompt"].firstMatch.tap()
        let editor = app.textViews["promptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("miso salmon")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap()
        let cook = app.buttons["Cook mode"]
        XCTAssertTrue(cook.waitForExistence(timeout: 10)); cook.tap()
        let external = app.buttons["qaExternalCookStep"]
        XCTAssertTrue(external.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next step"].exists)
        external.tap() // Writes AppStore.cookSession directly, not a CookMode index.
        let finish = app.buttons["cookFinish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "The open view must observe the new final step")
        XCTAssertFalse(app.buttons["Next step"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "cook-open-external-shared-step"; shot.lifetime = .keepAlways; add(shot)
        // Local Back writes the same owner, then external change is visible again.
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Next step"].waitForExistence(timeout: 5))
        external.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        app.buttons["Exit"].tap()
        XCTAssertTrue(cook.waitForExistence(timeout: 5)); cook.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "Reopen must keep shared step, not the old timer/private index")
    }
}
