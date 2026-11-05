import XCTest

/// Cook completion journeys that do not depend on the reflection offer. The offer is dormant in the app until the
/// Journal integration binds `onReflect`, so no offer journey exists here and none is claimed.
final class CookReflectionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        if app != nil {
            if app.buttons["Keep for later"].exists { app.buttons["Keep for later"].tap() }
            if app.buttons["cookReflection.notNow"].exists { app.buttons["cookReflection.notNow"].tap() }
            if app.buttons["cookJournal.qa.cleanup"].waitForExistence(timeout: 2) { app.buttons["cookJournal.qa.cleanup"].tap() }
        }
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @discardableResult
    func launch(extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory"] + extra
        app.launch()
        return app
    }

    func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func addPromptRecipe() {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        wait(text("Review your card"), 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
    }

    /// Opens Cook Mode, walks to the last step and taps Finish.
    func cookAndFinish() {
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of 4"))
        let finish = app.buttons["cookFinish"]
        var steps = 0
        while !finish.exists && steps < 6 {
            let next = app.buttons["Next step"]
            wait(next, 5)
            next.tap()
            steps += 1
        }
        wait(finish, 5)
        finish.tap()
    }

    /// Finish with no offer host (the production default until the Journal binds onReflect) ends on the recipe and does not leave a resumable
    /// session behind.
    func testFinishDoesNotRecreateTheResumeSession() {
        launch()
        addPromptRecipe()
        cookAndFinish()
        wait(app.buttons["Cook mode"], 10)
        XCTAssertTrue(app.buttons["cookSessionMiniPlayer"].waitForNonExistence(timeout: 5),
                      "a finished cook must not be offered for resume")
        XCTAssertFalse(app.buttons["cookReflection.write"].exists, "no offer without a bound host")
    }
    func launchHost(extra: [String] = []) {
        launch(extra: ["-qaCookJournalHost"] + extra)
        wait(app.buttons["cookFinish"], 15)
    }

    func finishAndChooseNote() {
        app.buttons["cookFinish"].tap()
        wait(app.buttons["cookReflection.write"], 10)
        shot("cook-journal-offer")
        app.buttons["cookReflection.write"].tap()
        wait(app.textViews["cookJournal.note"], 10)
        XCTAssertFalse(app.buttons["cookFinish"].exists, "Cook Mode must be dismissed before the composer")
    }

    func testOptionalCookReflectionSavesThroughActualModalHost() {
        launchHost()
        finishAndChooseNote()
        let note = app.textViews["cookJournal.note"]
        XCTAssertTrue((note.value as? String)?.contains("Original pap") == true)
        note.tap(); note.typeText("It worked well.")
        shot("cook-journal-modal-draft")
        app.buttons["cookJournal.save"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["cookSessionMiniPlayer"].exists)
        shot("cook-journal-modal-saved")
        app.buttons["cookJournal.qa.inspect"].tap()
        let detail = app.staticTexts["cookJournal.qa.detail"]
        wait(detail)
        XCTAssertTrue(detail.label.contains("rows=1;pending=0"))
        XCTAssertTrue(detail.label.contains("It worked well."))
        XCTAssertTrue(detail.label.contains("Original pap"))
        XCTAssertTrue(detail.label.contains("qa-cook-journal"))
        XCTAssertTrue(detail.label.contains("kind=reflection;health-empty=yes"))
        shot("cook-journal-bound-saved-record-detail")
    }

    func testKeepLaterReopensSameDraftAcrossRotation() {
        launchHost()
        finishAndChooseNote()
        let note = app.textViews["cookJournal.note"]
        note.tap(); note.typeText("Keep this note.")
        let retained = note.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(note)
        XCTAssertEqual(note.value as? String, retained)
        shot("cook-journal-landscape-draft")
        app.buttons["Keep for later"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        wait(app.tabBars.buttons["Insights"])
        app.tabBars.buttons["Insights"].tap()
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cookJournal.pending.")).firstMatch
        wait(pending)
        pending.tap()
        wait(note)
        XCTAssertEqual(note.value as? String, retained)
        shot("cook-journal-retained-reopened")
    }

    func testOptionalCookReflectionUsesNavigationHostAfterFinish() {
        launchHost(extra: ["-qaCookJournalNavigation"])
        finishAndChooseNote()
        shot("cook-journal-navigation-composer")
        app.buttons["cookJournal.save"].tap()
        XCTAssertTrue(app.textViews["cookJournal.note"].waitForNonExistence(timeout: 10))
    }

    func testPendingCookComposerWaitsForManualComposerThenAppears() {
        launch(extra: ["-qaCookJournalHost", "-qaCookJournalManualBlocker"])
        wait(app.textViews["journal.compose.text"], 15)
        XCTAssertFalse(app.textViews["cookJournal.note"].exists)
        shot("cook-journal-blocked-by-manual")
        app.buttons["journal.compose.cancel"].tap()
        wait(app.textViews["cookJournal.note"], 10)
        XCTAssertFalse(app.textViews["journal.compose.text"].exists)
        shot("cook-journal-after-manual-dismissal")
    }

    func testMaximumAccessibilityOfferAndComposerActionsRemainReachable() {
        launchHost(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["cookFinish"].tap()
        let write = app.buttons["cookReflection.write"]
        wait(write, 10)
        var swipes = 0
        while !write.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(write.isHittable)
        shot("cook-journal-maxax-offer")
        write.tap()
        wait(app.textViews["cookJournal.note"], 10)
        XCTAssertTrue(app.buttons["cookJournal.save"].isHittable)
        XCTAssertTrue(app.buttons["Keep for later"].isHittable)
        shot("cook-journal-maxax-composer")
    }

}
