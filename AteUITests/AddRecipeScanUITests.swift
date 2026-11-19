import XCTest

/// Synthetic backend/UI wiring. Not extraction accuracy or real-model acceptance.
final class AddRecipeScanUITests: XCTestCase {
    private func launch(off: Bool = false, landscape: Bool = false, retry: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if off { app.launchArguments += ["-qaStitchAddRecipeScanOff"] }
        if retry { app.launchArguments += ["-qaBackendFailOnce"] }
        app.launch()
        let add = app.buttons["Add recipe"]
        XCTAssertTrue(add.waitForExistence(timeout: 20)); add.tap()
        XCTAssertTrue(app.navigationBars["Add recipe"].waitForExistence(timeout: 5))
        return app
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, earlier: Bool = false) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if earlier { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func shot(_ name: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    private func prompt(_ app: XCUIApplication) {
        app.buttons["Prompt"].firstMatch.tap()
        let field = app.textViews["promptEditor"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Miso salmon for two")
        let generate = app.buttons["generateButton"]
        reveal(generate, in: app); generate.tap()
    }
    func testOnReviewUsesActualDraftCountsAndOriginalEditSave() {
        let app = launch(); prompt(app)
        let title = app.staticTexts["add.scan.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Miso salmon for two")
        XCTAssertEqual(app.staticTexts["add.scan.counts"].label, "5 ingredient entries · 4 cooking steps")
        XCTAssertFalse(app.descendants(matching: .any)["aiConfidence"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["sourceBadge"].firstMatch.label.contains("Demo"))
        shot("add-scan-on-real-draft-summary")
        let edit = app.buttons["Edit"].firstMatch
        reveal(edit, in: app); edit.tap()
        let editor = app.textFields["editorTitle"]
        reveal(editor, in: app, earlier: true)
        XCTAssertEqual(editor.value as? String, "Miso salmon for two")
        shot("add-scan-on-original-editor")
        let preview = app.buttons["Preview"].firstMatch
        reveal(preview, in: app); preview.tap()
        let save = app.buttons["saveRecipe"]
        XCTAssertTrue(save.isEnabled); reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons["Cook mode"].waitForExistence(timeout: 10))
    }
    func testOffRetainsOriginalReviewWithoutNewSummary() {
        let app = launch(off: true); prompt(app)
        XCTAssertTrue(app.navigationBars["Review your card"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["add.scan.title"].exists)
        XCTAssertFalse(app.staticTexts["add.scan.counts"].exists)
        let save = app.buttons["saveRecipe"]
        XCTAssertTrue(save.isEnabled)
        shot("add-scan-off-original-review")
    }
    func testSourceLinkReviewKeepsImportedIdentityAndNoMockAccuracy() {
        let app = launch()
        let field = app.textFields["linkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        field.typeText("https://fixtures.ate.test/jsonld-shakshuka")
        let generate = app.buttons["generateButton"]
        reveal(generate, in: app); generate.tap()
        XCTAssertTrue(app.staticTexts["add.scan.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["add.scan.title"].label, "Weekend shakshuka")
        XCTAssertTrue(app.descendants(matching: .any)["sourceBadge"].firstMatch.label.contains("Imported from page data"))
        XCTAssertFalse(app.descendants(matching: .any)["aiConfidence"].exists)
        XCTAssertFalse(app.buttons["Scan Another Page"].exists)
        shot("add-scan-source-identity-preserved")
    }
    func testLandscapeRetryRetainsInputAndCancelKeepsDraftUntilDiscard() {
        let app = launch(landscape: true, retry: true); prompt(app)
        let retry = app.buttons["generateRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertEqual(app.textViews["promptEditor"].value as? String, "Miso salmon for two")
        shot("add-scan-landscape-error-retains-input")
        reveal(retry, in: app); retry.tap()
        XCTAssertTrue(app.staticTexts["add.scan.counts"].waitForExistence(timeout: 15))
        shot("add-scan-landscape-review-after-explicit-retry")
        app.buttons["addCancel"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].exists)
        app.buttons["addCancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertFalse(app.buttons["saveRecipe"].exists)
    }
    func testSingleImageReplacementAndReadKeepExistingFlow() {
        let app = launch()
        app.buttons["Image"].firstMatch.tap()
        let sample = app.buttons["sampleImage"]
        reveal(sample, in: app); sample.tap()
        XCTAssertTrue(app.staticTexts["add.scan.imageReady"].exists)
        // Selecting the same input again is replacement, never a second page.
        sample.tap()
        let read = app.buttons["generateButton"]
        reveal(read, in: app); read.tap()
        XCTAssertTrue(app.staticTexts["add.scan.counts"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Scan Another Page"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["aiConfidence"].exists)
        shot("add-scan-single-image-review-no-accuracy-badge")
    }
}
