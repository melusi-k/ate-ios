import XCTest

/// Actual completion sheets and event-linked optional Journal notes, including repeated cooks on one day.
final class CookReflectionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        if app != nil {
            if app.buttons["Later"].exists { app.buttons["Later"].tap() }
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
        let b64 = XCUIScreen.main.screenshot().pngRepresentation.base64EncodedString()
        print("SNAPSHOT-BEGIN \(name) \(b64.count)")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SNAPSHOT-CHUNK \(name) \(b64[i..<j])")
            i = j
        }
        print("SNAPSHOT-END \(name)")
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

    /// Normal-size portrait acceptance: both action buttons precede centered content.
    private func assertCompletionActionsAreAtTop(file: StaticString = #filePath, line: UInt = #line) {
        let add = app.buttons["cookReflection.write"]
        let done = app.buttons["cookReflection.notNow"]
        let title = app.staticTexts["cookReflection.title"]
        wait(add); wait(done); wait(title)
        XCTAssertTrue(add.isHittable && done.isHittable, file: file, line: line)
        XCTAssertLessThanOrEqual(max(add.frame.maxY, done.frame.maxY), title.frame.minY,
                                 "Both completion actions belong above the content", file: file, line: line)
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 6,
                       "Completion title is centered", file: file, line: line)
        let recipe = app.staticTexts["cookCompletion.recipe"]
        XCTAssertEqual(recipe.frame.midX, app.frame.midX, accuracy: 6,
                       "Recipe is centered", file: file, line: line)
    }

    /// Production route: history is confirmed before Done, which leaves no resumable session.
    func testFinishDoesNotRecreateTheResumeSession() {
        launch()
        addPromptRecipe()
        cookAndFinish()
        wait(app.staticTexts["cookCompletion.recorded"])
        wait(app.buttons["cookReflection.write"])
        assertCompletionActionsAreAtTop()
        shot("completion-01-first-cook-confirmation-portrait")
        app.buttons["cookReflection.notNow"].tap()
        wait(app.buttons["Cook mode"], 10)
        XCTAssertTrue(app.buttons["cookSessionMiniPlayer"].waitForNonExistence(timeout: 5),
                      "a finished cook must not be offered for resume")
        XCTAssertFalse(app.buttons["cookReflection.write"].exists, "Done closes the completion sheet")
    }
    func testEveryFinishShowsCompletionButDailyNudgeAppearsOnlyOnce() {
        launch()
        addPromptRecipe()
        cookAndFinish()
        wait(app.staticTexts["cookCompletion.recorded"])
        wait(app.staticTexts["cookCompletion.dailyNudge"])
        app.buttons["cookReflection.notNow"].tap()
        wait(app.buttons["Cook mode"])
        cookAndFinish()
        wait(app.staticTexts["cookCompletion.recorded"])
        XCTAssertFalse(app.staticTexts["cookCompletion.dailyNudge"].exists)
        wait(app.buttons["cookReflection.write"])
        assertCompletionActionsAreAtTop()
        shot("completion-03-repeat-cook-note-still-available-portrait")
        app.buttons["cookReflection.write"].tap()
        wait(app.textViews["cookJournal.note"])
        shot("completion-04-production-event-linked-note-portrait")
    }

    func launchHost(extra: [String] = []) {
        launch(extra: ["-qaCookJournalHost"] + extra)
        wait(app.buttons["cookFinish"], 15)
    }

    func finishAndChooseNote() {
        let finish = app.buttons["cookFinish"]
        wait(finish)
        let trace = XCTAttachment(string: "Finish frame=\(finish.frame); matches=\(app.buttons.matching(identifier: "cookFinish").count); tabBarVisible=\(app.tabBars.firstMatch.isHittable)")
        trace.name = "cook-finish-before-tap"
        trace.lifetime = .keepAlways
        add(trace)
        XCTAssertTrue(finish.isHittable, "Finish must be a tappable control in its host safe area")
        finish.tap()
        wait(app.buttons["cookReflection.write"], 10)
        wait(app.staticTexts["cookCompletion.recorded"])
        shot("completion-02-add-note-first-cook-portrait")
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
        app.buttons["Later"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        wait(app.tabBars.buttons["Journal"])
        app.tabBars.buttons["Journal"].tap()
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cookJournal.pending.")).firstMatch
        wait(pending)
        // These are actual List cell bounds, not label-to-label distances: header
        // padding and an accidental empty section must count as visible whitespace.
        let notesCell = app.cells.containing(.any, identifier: "journal.cookingNotesCard").firstMatch
        let insightsCell = app.cells.containing(.any, identifier: "journal.insightsHistory").firstMatch
        let mealsCell = app.cells.containing(.any, identifier: "journal.meals").firstMatch
        let reflectionCell = app.cells.containing(.any, identifier: "journal.reflection").firstMatch
        for cell in [notesCell, insightsCell, mealsCell, reflectionCell] { wait(cell) }
        let gaps = [insightsCell.frame.minY - notesCell.frame.maxY,
                    mealsCell.frame.minY - insightsCell.frame.maxY,
                    reflectionCell.frame.minY - mealsCell.frame.maxY]
        let geometry = XCTAttachment(string: "Journal home cell gaps: \(gaps); notes=\(notesCell.frame); insights=\(insightsCell.frame); meals=\(mealsCell.frame); reflection=\(reflectionCell.frame)")
        geometry.name = "journal-home-section-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        shot("journal-normal-home-equal-section-gaps")
        for gap in gaps { XCTAssertEqual(gap, 12, accuracy: 2, "All home cards share the explicit 12pt gap") }
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



}
