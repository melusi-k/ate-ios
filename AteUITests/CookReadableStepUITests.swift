import XCTest

/// Run at the standard iPhone 18 Pro normal text size; retained pixels are the
/// readability evidence. AX existence alone is not a font-size measurement.
final class CookReadableStepUITests: XCTestCase {
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLongInstructionScrollsWithoutMovingStepControls() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaCookReadableStep"]
        app.launch()
        let scroll = app.scrollViews["cookStepScroll"]
        let instruction = app.staticTexts["cookStepText"]
        let next = app.buttons["cookNextStep"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertTrue(instruction.exists)
        XCTAssertTrue(instruction.label.contains("Before heating the pan"))
        XCTAssertTrue(instruction.label.contains("Final check: serve the stew while warm."),
            "The complete instruction must be retained, not clipped to a shorter string")
        XCTAssertTrue(next.isHittable)
        let controlFrame = next.frame
        shot("cook-long-step-top-normal-text")
        for _ in 0..<4 { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(next.isHittable)
        XCTAssertEqual(next.frame, controlFrame, "Instruction scrolling must not move the step controls")
        shot("cook-long-step-end-normal-text")
        next.tap()
        XCTAssertTrue(app.buttons["cookFinish"].waitForExistence(timeout: 5))
        XCTAssertTrue(instruction.label.contains("Put the remaining stew"))
        shot("cook-short-next-step-normal-text")
        app.buttons["Back"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(instruction.label.contains("Before heating the pan"))
        shot("cook-return-to-long-step-start-normal-text")
    }
}
