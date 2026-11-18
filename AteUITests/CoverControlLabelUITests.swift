import XCTest

/// Adds normal-size evidence without changing the existing photo/OCR QA flow.
extension CoverageUITests {
    func testCoverControlsHaveUnbrokenLabelsAndSeparateTargetsAtNormalSize() {
        launch(["-qaNoPlayground"])
        startPrompt("Chakalaka")
        wait(text("Review your card"), 15)
        let sample = app.buttons["sampleCover"]
        scrollTo(sample); wait(sample, 5); sample.tap()
        let remove = app.buttons["removeCover"]
        wait(remove, 5)
        let controls = [("changeCover", "Change photo"), ("sampleCover", "Sample cover"), ("removeCover", "Remove")]
        var frames: [CGRect] = []
        for (id, label) in controls {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists && button.isHittable, "Missing visible action \(label)")
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(app.frame.contains(button.frame), "Action must stay inside the viewport")
            for earlier in frames { XCTAssertFalse(earlier.intersects(button.frame), "Cover actions must not overlap") }
            frames.append(button.frame)
        }
        shot("cover-controls-normal-text-photo-unbroken-labels")
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sample.isHittable)
        XCTAssertTrue(app.buttons["changeCover"].isHittable)
        shot("cover-controls-normal-text-after-remove")
    }
}
