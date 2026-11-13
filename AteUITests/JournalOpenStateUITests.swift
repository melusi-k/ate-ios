import XCTest

/// #245 phase 3: a journal that did not open cleanly must be presented honestly.
/// These launch the real app with a QA-forced open state (`-qaJournalOpenState`,
/// JournalStore.qaForcedOpenState) and verify the banner through the running app's
/// realized accessibility tree, over the actual route a user takes:
/// Library tab -> browse menu -> Journal sheet.
///
/// Why UI tests and not hosted rendering: a UIHostingController hosted in a unit
/// test never realizes SwiftUI's accessibility tree (no accessibility server queries
/// it), so a hierarchy walk returns an empty collection while the pixels render
/// correctly - dogfood run 41272234984 proved exactly that (banner visible in the
/// rendered snapshot, walk empty, "no banner" assertions passing vacuously).
/// Presentation assertions belong in the real app.
///
/// Screenshots of every state are attached to the result and exported into the log
/// (SNAPSHOT-CHUNK base64) so review sees exactly what shipped, not just assertions.
final class JournalOpenStateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"] + extra
        app.launch()
        return app
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)",
                      file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "Still presented: \(element)", file: file, line: line)
    }

    /// Final #527 AX contains one native action as an equal-frame parent/child
    /// Button chain. Count distinct terminal actions, not framework wrappers.
    /// Two sibling leaves still fail even if their frames happen to overlap.
    private func uniqueDeleteAlertAction(_ alert: XCUIElement, identifier: String, label: String,
                                         file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        XCTAssertEqual(app.alerts.count, 1, "Exactly one visible delete alert is allowed", file: file, line: line)
        let matches = alert.buttons.matching(identifier: identifier)
        XCTAssertGreaterThan(matches.count, 0, "The named action must exist", file: file, line: line)
        XCTAssertEqual(alert.buttons.matching(NSPredicate(format: "label == %@", label)).count, matches.count,
                       "No same-label action may escape the identity check", file: file, line: line)
        var leaves: [XCUIElement] = []
        for index in 0..<matches.count {
            let candidate = matches.element(boundBy: index)
            XCTAssertEqual(candidate.label, label, "Every alias must name the same decision", file: file, line: line)
            let descendants = candidate.descendants(matching: .button)
            let nested = descendants.matching(identifier: identifier)
            XCTAssertEqual(descendants.count, nested.count, "An alias cannot contain a different action", file: file, line: line)
            if nested.count == 0 { leaves.append(candidate) }
        }
        XCTAssertEqual(leaves.count, 1, "Exactly one distinct visible \(label) action is allowed", file: file, line: line)
        guard leaves.count == 1 else {
            throw NSError(domain: "JournalDeleteActionIdentity", code: 1)
        }
        let action = leaves[0]  // proven unique terminal action, never arbitrary firstMatch
        let frame = action.frame
        XCTAssertFalse(frame.isEmpty, "Action must have visible area", file: file, line: line)
        XCTAssertTrue(alert.frame.contains(frame), "Action must be inside the one alert", file: file, line: line)
        for index in 0..<matches.count {
            let alias = matches.element(boundBy: index)
            XCTAssertEqual(alias.frame, frame, "Nested aliases must occupy exactly the same action frame", file: file, line: line)
            XCTAssertTrue(alias.isEnabled, "No disabled duplicate decision may be hidden", file: file, line: line)
        }
        XCTAssertTrue(action.isHittable, "The unique visible action must be tappable", file: file, line: line)
        return action
    }

    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func text(_ s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// Attaches a named screenshot and mirrors it into the log as chunked base64
    /// so the exact rendered pixels can be recovered from CI logs alone.
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let b64 = screenshot.pngRepresentation.base64EncodedString()
        print("SNAPSHOT-BEGIN \(name) \(b64.count)")
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SNAPSHOT-CHUNK \(name) \(b64[i..<j])")
            i = j
        }
        print("SNAPSHOT-END \(name)")
    }

    /// The journal timeline is the Journal tab root: one tab tap, no menu.
    private func openJournal() {
        wait(app.tabBars.firstMatch, 15)
        app.tabBars.buttons["Journal"].tap()
        wait(app.navigationBars["Journal"], 10)
    }

    private func banner(_ timeout: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let b = any("journal.openStateBanner")
        XCTAssertTrue(b.waitForExistence(timeout: timeout),
                      "the open-state banner must be exposed", file: file, line: line)
        return b
    }

    func testRecoveredOpenShowsBannerWithBackupName() {
        launch(extra: ["-qaJournalOpenState", "recovered"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal recovered"),
                      "the user must hear the journal was recovered, not see a silent fresh one")
        XCTAssertTrue(b.label.contains("ate-20250101-120000.store"),
                      "the kept backup is named so it can be found in Backups")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "a recovered-empty journal must not be presented as real history")
        shot("jos-01-recovered")
    }

    func testInMemoryFallbackOpenShowsTemporaryWarning() {
        launch(extra: ["-qaJournalOpenState", "fallback"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal is temporary right now"),
                      "the user must hear the journal is temporary")
        XCTAssertTrue(b.label.contains("will disappear when you close Ate"),
                      "the user must hear their saves will not last")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "a temporary journal must not be presented as real history")
        shot("jos-02-fallback")
    }

    func testUnavailableOpenShowsHonestFailure() {
        launch(extra: ["-qaJournalOpenState", "unavailable"])
        openJournal()
        let b = banner()
        XCTAssertTrue(b.label.contains("Journal unavailable"),
                      "the user must hear the journal could not be opened")
        XCTAssertFalse(any("journal.entry").exists,
                       "an unavailable journal must not show entries as if all is well")
        XCTAssertFalse(text("No journal entries yet").exists,
                       "an unavailable journal must not be presented as an empty healthy one")
        // The screen stays navigable: the user is never trapped on a broken journal.
        shot("jos-03-unavailable")
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10) && libraryTab.isHittable,
                      "the tab bar must remain selectable from a broken journal")
        libraryTab.tap()
        wait(app.buttons["libraryBrowseMenu"], 10)
    }

    func testHealthyOpenShowsNoBanner() {
        launch()
        openJournal()
        XCTAssertFalse(any("journal.openStateBanner").waitForExistence(timeout: 3),
                       "a clean open must not show a recovery banner")
        wait(text("No journal entries yet"), 10)
        shot("jos-04-healthy")
    }
}

// Manual creation regression: the actual history sheet and Insights routes must both expose writing.
// Generic fixtures only. Never copy private journal text into tests or retained screenshots.
extension JournalOpenStateUITests {
    private func composeFromHistory(extra: [String] = []) {
        launch(extra: ["-qaMockHealth", "empty"] + extra)
        openJournal()
        wait(app.buttons["journal.newEntry"])
        shot("manual-01-history-create-action")
        app.buttons["journal.newEntry"].tap()
        wait(app.textViews["journal.compose.text"])
    }

    func testManualCreateWithoutHealthThenReadDetailAndPreserveExistingEditActions() {
        composeFromHistory()
        XCTAssertFalse(app.buttons["journal.compose.save"].isEnabled)
        let editor = app.textViews["journal.compose.text"]
        editor.tap(); editor.typeText("Generic lentil supper reflection")
        app.buttons["journal.compose.save"].tap()
        wait(app.navigationBars["Journal"])
        let row = any("journal.entry")
        wait(row)
        XCTAssertTrue(row.label.contains("Generic lentil supper reflection"))
        XCTAssertFalse(row.label.contains("Balanced day"))
        shot("manual-02-saved-history")
        row.tap()
        wait(any("journal.detail.text"))
        XCTAssertTrue(any("journal.detail.text").label.contains("Generic lentil supper reflection"))
        XCTAssertFalse(app.staticTexts["Balanced day"].exists)
        app.buttons["journal.detail.menu"].tap()
        wait(app.buttons["Edit"])
        XCTAssertTrue(app.buttons["Delete"].exists)
        shot("manual-03-detail-actions")
    }

    func testTimelineOpensSavedReflectionDetailAndRetainsBackRoute() {
        composeFromHistory()
        let editor = app.textViews["journal.compose.text"]
        editor.tap()
        editor.typeText("Timeline reflection navigation proof")
        app.buttons["journal.compose.save"].tap()
        wait(app.navigationBars["Journal"])
        wait(app.buttons["journal.timelineLink"])
        app.buttons["journal.timelineLink"].tap()
        wait(app.navigationBars["Food Journal"])
        let reflection = row("Timeline reflection navigation proof")
        wait(reflection)
        reflection.tap()
        let detail = any("journal.detail.text")
        wait(detail)
        XCTAssertEqual(detail.label, "Timeline reflection navigation proof")
        wait(app.buttons["journal.detail.menu"])
        shot("timeline-saved-reflection-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Food Journal"])
        wait(row("Timeline reflection navigation proof"))
        shot("timeline-saved-reflection-back")
    }

    func testReflectionEditFailureRetainsDraftThenRetryCommitsAndRefreshesHistory() throws {
        composeFromHistory(extra: ["-qaReflectionEditFailureOnce"])
        let original = "Reflection failure " + UUID().uuidString
        let compose = app.textViews["journal.compose.text"]
        compose.tap(); compose.typeText(original)
        app.buttons["journal.compose.save"].tap()
        wait(app.navigationBars["Journal"])
        let saved = app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", original)).firstMatch
        wait(saved); saved.tap()
        let detail = any("journal.detail.text")
        wait(detail); XCTAssertEqual(detail.label, original)
        app.buttons["journal.detail.menu"].tap(); app.buttons["Edit"].tap()
        let editor = app.textViews["journal.edit.text"]
        wait(editor); editor.tap(); editor.typeText(" retained draft")
        let retainedDraft = try XCTUnwrap(editor.value as? String)
        // The editor retains exact user input after failure. A successful update
        // follows JournalStore's existing whitespace/newline normalization.
        let committedText = retainedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(committedText.isEmpty)
        XCTAssertNotEqual(committedText, original, "Retry must commit an actual edit")
        app.navigationBars["Edit entry"].buttons["journal.edit.save"].tap()
        wait(any("journal.edit.error"))
        XCTAssertTrue(editor.exists, "Failed commit must not dismiss editor")
        XCTAssertEqual(editor.value as? String, retainedDraft, "Failed commit must keep exact draft")
        shot("reflection-edit-failure-retained-draft")
        app.navigationBars["Edit entry"].buttons["journal.edit.save"].tap()
        waitUntilGone(editor)
        wait(detail); XCTAssertEqual(detail.label, committedText)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Journal"])
        let edited = app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", committedText)).firstMatch
        wait(edited)
        shot("reflection-edit-retry-refreshed-history")
    }

    /// Keep actual alert evidence before a strict uniqueness failure stops the method.
    /// Diagnostic only: does not choose/hide a match or change any assertion.
    private func retainDeleteAlertEvidence(_ alert: XCUIElement, phase: String) {
        shot("delete-alert-" + phase)
        let hierarchy = XCTAttachment(string: alert.debugDescription + "\nAPP\n" + app.debugDescription)
        hierarchy.name = "delete-alert-" + phase + "-AX"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testManualReflectionEditSaveCancelAndConfirmedDelete() throws {
        composeFromHistory()
        let original = "Manual CRUD " + UUID().uuidString
        let changed = original + " edited"
        let compose = app.textViews["journal.compose.text"]
        compose.tap(); compose.typeText(original)
        app.buttons["journal.compose.save"].tap()
        wait(app.navigationBars["Journal"])
        let saved = app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", original)).firstMatch
        wait(saved); saved.tap()
        let detail = any("journal.detail.text")
        wait(detail)
        XCTAssertEqual(detail.label, original, "Only the newly created reflection may be edited or deleted")
        let originalDate = any("journal.detail.date").label

        app.buttons["journal.detail.menu"].tap(); app.buttons["Edit"].tap()
        let editor = app.textViews["journal.edit.text"]
        wait(editor)
        XCTAssertEqual(editor.value as? String, original)
        editor.tap(); editor.typeText(" discarded draft")
        app.navigationBars["Edit entry"].buttons["journal.edit.cancel"].tap()
        waitUntilGone(editor)
        XCTAssertEqual(detail.label, original, "Cancel must not save the draft")

        app.buttons["journal.detail.menu"].tap(); app.buttons["Edit"].tap()
        wait(editor)
        XCTAssertEqual(editor.value as? String, original)
        editor.tap()
        // Replace via the native Select All action, not a guessed caret position.
        editor.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        wait(selectAll); selectAll.tap(); editor.typeText(changed)
        app.navigationBars["Edit entry"].buttons["journal.edit.save"].tap()
        waitUntilGone(editor)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Journal"])
        let edited = app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", changed)).firstMatch
        wait(edited); edited.tap()
        wait(detail)
        XCTAssertEqual(detail.label, changed, "Reopened detail must be the same edited reflection before deletion")
        XCTAssertEqual(any("journal.detail.date").label, originalDate, "Editing must preserve the original entry date")
        shot("manual-crud-edited-detail")

        app.buttons["journal.detail.menu"].tap(); app.buttons["Delete"].tap()
        wait(app.staticTexts["Delete this journal entry?"])
        let cancelConfirmation = app.alerts["Delete this journal entry?"]
        retainDeleteAlertEvidence(cancelConfirmation, phase: "crud-cancel-before-count")
        let cancelAction = try uniqueDeleteAlertAction(cancelConfirmation, identifier: "journal.delete.cancel", label: "Cancel")
        _ = try uniqueDeleteAlertAction(cancelConfirmation, identifier: "journal.delete.confirm", label: "Delete")
        cancelAction.tap()
        waitUntilGone(app.staticTexts["Delete this journal entry?"])
        XCTAssertEqual(detail.label, changed, "Cancel must keep the reflection")
        app.buttons["journal.detail.menu"].tap(); app.buttons["Delete"].tap()
        wait(app.staticTexts["Delete this journal entry?"])
        shot("manual-crud-delete-confirmation")
        let confirmation = app.alerts["Delete this journal entry?"]
        wait(confirmation)
        retainDeleteAlertEvidence(confirmation, phase: "crud-confirm-before-count")
        let confirmButton = try uniqueDeleteAlertAction(confirmation, identifier: "journal.delete.confirm", label: "Delete")
        _ = try uniqueDeleteAlertAction(confirmation, identifier: "journal.delete.cancel", label: "Cancel")
        confirmButton.tap()
        // Capture the post-confirmation state even when the unchanged detail
        // dismissal assertion fails. No back navigation or retry hides failure.
        shot("manual-crud-after-confirmed-delete")
        XCTAssertFalse(app.staticTexts["journal.delete.error"].exists,
                       "Confirmed deletion must commit and verify, not only dismiss an alert")
        waitUntilGone(detail)
        wait(app.navigationBars["Journal"])
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", original)).firstMatch.exists,
            "Confirmed deletion must remove the created reflection from history")
        shot("manual-crud-confirmed-deleted-history")
    }

    func testConfirmedDeleteFailureKeepsDetailAndExplicitRetryRemovesEntry() throws {
        launch(extra: ["-qaReflectionDeleteFailureOnce"])
        app.tabBars.buttons["Journal"].tap()
        wait(app.buttons["journal.newEntry"])
        app.buttons["journal.newEntry"].tap()
        let original = "Delete retry " + UUID().uuidString
        let compose = app.textViews["journal.compose.text"]
        wait(compose); compose.tap(); compose.typeText(original)
        app.buttons["journal.compose.save"].tap()
        wait(app.navigationBars["Journal"])
        let row = app.descendants(matching: .any).matching(identifier: "journal.entry")
            .matching(NSPredicate(format: "label CONTAINS %@", original)).firstMatch
        wait(row); row.tap()
        let detail = any("journal.detail.text")
        wait(detail)
        app.buttons["journal.detail.menu"].tap(); app.buttons["Delete"].tap()
        let alert = app.alerts["Delete this journal entry?"]
        wait(alert)
        retainDeleteAlertEvidence(alert, phase: "failure-retry-before-count")
        let failedSaveDelete = try uniqueDeleteAlertAction(alert, identifier: "journal.delete.confirm", label: "Delete")
        _ = try uniqueDeleteAlertAction(alert, identifier: "journal.delete.cancel", label: "Cancel")
        failedSaveDelete.tap()
        let error = app.staticTexts["journal.delete.error"]
        wait(error)
        XCTAssertEqual(detail.label, original, "Failed commit must not discard the detail")
        XCTAssertTrue(app.navigationBars["Journal entry"].exists)
        shot("manual-delete-failure-retained-detail")
        app.buttons["journal.detail.menu"].tap(); app.buttons["Delete"].tap()
        wait(alert)
        retainDeleteAlertEvidence(alert, phase: "failure-retry-before-count")
        let explicitRetryDelete = try uniqueDeleteAlertAction(alert, identifier: "journal.delete.confirm", label: "Delete")
        _ = try uniqueDeleteAlertAction(alert, identifier: "journal.delete.cancel", label: "Cancel")
        explicitRetryDelete.tap()
        shot("manual-delete-explicit-retry-result")
        waitUntilGone(detail)
        wait(app.navigationBars["Journal"])
        XCTAssertFalse(row.exists, "Only successful explicit retry may remove the target from history")
    }

    func testManualCancelKeepsDraftUntilExplicitDiscard() {
        composeFromHistory()
        let editor = app.textViews["journal.compose.text"]
        editor.tap(); editor.typeText("Generic unsaved draft")
        app.buttons["journal.compose.cancel"].tap()
        let discard = app.alerts["Discard this draft?"]
        wait(discard)
        XCTAssertTrue(discard.buttons["Keep writing"].isHittable)
        XCTAssertTrue(discard.buttons["Discard draft"].isHittable)
        shot("manual-04-discard-choice")
        discard.buttons["Keep writing"].tap()
        XCTAssertEqual(editor.value as? String, "Generic unsaved draft")
        wait(app.keyboards.firstMatch)
        shot("manual-04-kept-draft")
        app.buttons["journal.compose.cancel"].tap()
        wait(discard)
        discard.buttons["Discard draft"].tap()
        wait(app.navigationBars["Journal"])
        waitUntilGone(app.textViews["journal.compose.text"])
        XCTAssertFalse(any("journal.entry").exists)
        shot("manual-04-discarded-history")
    }

    private func verifyFailedSaveIsVisible(extra: [String] = [], landscape: Bool = false,
                                          captureName: String) {
        composeFromHistory(extra: ["-qaJournalOpenState", "unavailable"] + extra)
        defer { XCUIDevice.shared.orientation = .portrait }
        let editor = app.textViews["journal.compose.text"]
        editor.tap(); editor.typeText("Generic retained failure draft")
        wait(app.keyboards.firstMatch)
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait(editor)
            XCTAssertEqual(editor.value as? String, "Generic retained failure draft")
            shot("\(captureName)-rotated-draft")
        }
        shot("\(captureName)-keyboard-before-save")
        app.buttons["journal.compose.save"].tap()
        let failure = app.alerts["Journal entry not saved"]
        wait(failure)
        XCTAssertTrue(failure.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cannot save")).firstMatch.exists)
        XCTAssertTrue(failure.buttons["Continue writing"].isHittable)
        shot("\(captureName)-failure-alert")
        failure.buttons["Continue writing"].tap()
        XCTAssertEqual(editor.value as? String, "Generic retained failure draft")
        wait(app.keyboards.firstMatch)
        wait(any("journal.compose.error"))
        shot("\(captureName)-keyboard-retained-draft")
        // A second explicit save must present the error again without losing or duplicating the draft.
        app.buttons["journal.compose.save"].tap()
        wait(failure)
        failure.buttons["Continue writing"].tap()
        XCTAssertEqual(editor.value as? String, "Generic retained failure draft")
        if landscape {
            XCUIDevice.shared.orientation = .portrait
            wait(editor)
            XCTAssertEqual(editor.value as? String, "Generic retained failure draft")
            shot("\(captureName)-returned-portrait-draft")
        }
        // Both native alerts must coexist without swallowing the explicit cancellation choices.
        app.buttons["journal.compose.cancel"].tap()
        let discard = app.alerts["Discard this draft?"]
        wait(discard)
        XCTAssertTrue(discard.buttons["Keep writing"].isHittable)
        XCTAssertTrue(discard.buttons["Discard draft"].isHittable)
        shot("\(captureName)-cancel-after-failure")
        discard.buttons["Keep writing"].tap()
        XCTAssertEqual(editor.value as? String, "Generic retained failure draft")
        app.buttons["journal.compose.cancel"].tap()
        wait(discard)
        discard.buttons["Discard draft"].tap()
        waitUntilGone(editor)
        wait(app.navigationBars["Journal"])
        XCTAssertFalse(any("journal.entry").exists)
    }

    func testManualSaveUnavailableRetainsDraftAndShowsError() {
        verifyFailedSaveIsVisible(captureName: "manual-05-unavailable")
    }

    func testManualSaveFailureVisibleInCompactLandscape() {
        verifyFailedSaveIsVisible(landscape: true, captureName: "manual-07-compact")
    }

    func testManualSaveFailureVisibleAtXXXL() {
        verifyFailedSaveIsVisible(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"],
                                 captureName: "manual-08-xxxl")
    }

    /// Normal-size coverage, separate from the retained original cross-size case.
    func testManualSaveFailureVisibleAtNormalText() {
        verifyFailedSaveIsVisible(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"],
                                 captureName: "manual-08-normal")
    }

    /// Separate from ordinary XXXL save-error coverage: the root add accessory at the
    /// maximum accessibility category must fit its fixed system height and remain actionable.

    func testJournalRootAddAtMaximumAccessibilitySizeAndSidebarRoundTrip() {
        launch(extra: ["-qaMockHealth", "empty", "-UIPreferredContentSizeCategoryName",
                       "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { XCUIDevice.shared.orientation = .portrait }
        openJournal()
        let accessory = any("bottomAccessory")
        let add = app.buttons["accessoryAdd"]
        shot("manual-09-maxax-root-expanded")
        wait(accessory)
        wait(add)
        XCTAssertTrue(add.isHittable, "The maximum-accessibility root add action must be reachable")
        XCTAssertEqual(add.label, "New journal entry", "VoiceOver must retain the full action name")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertTrue(accessory.frame.contains(add.frame), "The action must fit inside the system accessory")

        XCUIDevice.shared.orientation = .landscapeLeft
        wait(any("sidebar"))
        wait(app.navigationBars["Journal"])
        let toolbarAdd = app.buttons["journal.newEntry"]
        shot("manual-09-maxax-sidebar-root")
        wait(toolbarAdd)
        XCTAssertTrue(toolbarAdd.isHittable, "The sidebar root must retain a reachable journal action")
        toolbarAdd.tap()
        let editor = app.textViews["journal.compose.text"]
        wait(editor)
        editor.tap()
        editor.typeText("Generic maximum accessibility draft")
        XCUIDevice.shared.orientation = .portrait
        wait(editor)
        XCTAssertEqual(editor.value as? String, "Generic maximum accessibility draft")
        shot("manual-09-maxax-returned-portrait-draft")
        app.buttons["journal.compose.cancel"].tap()
        let discard = app.alerts["Discard this draft?"]
        wait(discard)
        XCTAssertTrue(discard.buttons["Discard draft"].isHittable)
        discard.buttons["Discard draft"].tap()
        waitUntilGone(editor)
        wait(app.navigationBars["Journal"])
        wait(add)
        XCTAssertTrue(add.isHittable)
        XCTAssertEqual(add.label, "New journal entry")
        shot("manual-09-maxax-root-returned")
        add.tap()
        wait(editor)
        XCTAssertEqual(editor.value as? String, "",
                       "Explicit discard must not leak the previous draft into a new entry")
        shot("manual-09-maxax-accessory-opened-composer")
    }

    /// Normal-size coverage, separate from the retained original cross-size case.
    func testJournalRootAddAtNormalTextAndSidebarRoundTrip() {
        launch(extra: ["-qaMockHealth", "empty", "-UIPreferredContentSizeCategoryName",
                       "UICTContentSizeCategoryL"])
        defer { XCUIDevice.shared.orientation = .portrait }
        openJournal()
        let accessory = any("bottomAccessory")
        let add = app.buttons["accessoryAdd"]
        shot("manual-09-normal-root-expanded")
        wait(accessory)
        wait(add)
        XCTAssertTrue(add.isHittable, "The normal-text root add action must be reachable")
        XCTAssertEqual(add.label, "New journal entry", "VoiceOver must retain the full action name")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertTrue(accessory.frame.contains(add.frame), "The action must fit inside the system accessory")

        XCUIDevice.shared.orientation = .landscapeLeft
        wait(any("sidebar"))
        wait(app.navigationBars["Journal"])
        let toolbarAdd = app.buttons["journal.newEntry"]
        shot("manual-09-normal-sidebar-root")
        print("JOURNAL-NORMAL-SIDEBAR-ROOT-AX-BEGIN")
        print(app.debugDescription)
        print("JOURNAL-NORMAL-SIDEBAR-ROOT-AX-END")
        wait(toolbarAdd)
        XCTAssertTrue(toolbarAdd.isHittable, "The sidebar root must retain a reachable journal action")
        toolbarAdd.tap()
        let editor = app.textViews["journal.compose.text"]
        wait(editor)
        shot("manual-09-normal-composer-before-tap")
        print("JOURNAL-NORMAL-COMPOSER-BEFORE-TAP-AX-BEGIN")
        print(app.debugDescription)
        print("JOURNAL-NORMAL-COMPOSER-BEFORE-TAP-AX-END")
        editor.tap()
        editor.typeText("Generic normal-size draft")
        XCUIDevice.shared.orientation = .portrait
        wait(editor)
        XCTAssertEqual(editor.value as? String, "Generic normal-size draft")
        shot("manual-09-normal-returned-portrait-draft")
        app.buttons["journal.compose.cancel"].tap()
        let discard = app.alerts["Discard this draft?"]
        wait(discard)
        XCTAssertTrue(discard.buttons["Discard draft"].isHittable)
        discard.buttons["Discard draft"].tap()
        waitUntilGone(editor)
        wait(app.navigationBars["Journal"])
        wait(add)
        XCTAssertTrue(add.isHittable)
        XCTAssertEqual(add.label, "New journal entry")
        shot("manual-09-normal-root-returned")
        add.tap()
        wait(editor)
        XCTAssertEqual(editor.value as? String, "",
                       "Explicit discard must not leak the previous draft into a new entry")
        shot("manual-09-normal-accessory-opened-composer")
    }

    func testManualActionAfterReturningFromInsightsDoesNotRequireHealth() {
        launch(extra: ["-qaMockHealth", "empty"])
        wait(app.tabBars.firstMatch, 15)
        app.tabBars.buttons["Journal"].tap()
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub); hub.tap()
        XCTAssertFalse(any("insights.tile.journal").exists, "The hub must not duplicate the Journal list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(app.navigationBars["Journal"])
        let action = app.buttons["journal.newEntry"]
        wait(action)
        XCTAssertTrue(action.isHittable)
        action.tap()
        wait(app.textViews["journal.compose.text"])
        shot("manual-06-journal-root-no-health")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Writing must not ask for Health permission")
        let editor = app.textViews["journal.compose.text"]
        editor.tap(); editor.typeText("Generic Insights rotation draft")
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(editor)
        XCTAssertEqual(editor.value as? String, "Generic Insights rotation draft")
        shot("manual-06-journal-root-landscape-draft")
        XCUIDevice.shared.orientation = .portrait
        wait(editor)
        XCTAssertEqual(editor.value as? String, "Generic Insights rotation draft")
        shot("manual-06-insights-portrait-draft")
        app.buttons["journal.compose.cancel"].tap()
        let discard = app.alerts["Discard this draft?"]
        wait(discard)
        discard.buttons["Discard draft"].tap()
        waitUntilGone(editor)
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }
    // MARK: Food Journal timeline (#245 step 4). Fixture states are injected by `-qaJournalTimeline`;
    // the real-store and open-state tests use no fixture. The meal-type menu is NOT UI-tested here (unit-tested only).

    /// Timeline rows are single combined accessibility elements, so match them by identifier and label.
    private func row(_ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "journal.timeline.row")
            .matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private func openTimeline() {
        openJournal()
        wait(app.buttons["journal.timelineLink"], 10)
        app.buttons["journal.timelineLink"].tap()
        wait(app.navigationBars["Food Journal"], 10)
    }

    func testTimelineFixtureShowsEveryRecordAcrossDays() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(any("journal.timeline.filter"), 10)
        wait(row("Oat porridge"), 10)
        wait(row("Meal details unavailable"), 10)   // orphan meal stays visible
        wait(row("Soup was the best part"), 10)     // legacy reflection stays visible
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "journal.timeline.row").count, 3,
                       "one row per stored entry, nothing dropped")
        XCTAssertFalse(any("journal.timeline.empty").exists)
        XCTAssertFalse(any("journal.timeline.error").exists)
        shot("jt-01-fixture")
    }

    func testTimelineFixtureReflectionsFilterHidesMeals() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(any("journal.timeline.filter"), 10)
        wait(row("Oat porridge"), 10)
        app.buttons["Reflections"].tap()
        wait(row("Soup was the best part"), 10)
        XCTAssertFalse(row("Oat porridge").exists, "the reflections filter hides meals")
        shot("jt-02-reflections-filter")
    }

    func testTimelineFixtureSearchWithNoHitsIsNotAnEmptyJournal() {
        launch(extra: ["-qaJournalTimeline", "fixture"])
        openTimeline()
        wait(row("Oat porridge"), 10)
        let search = app.searchFields.firstMatch
        wait(search, 10)
        search.tap()
        search.typeText("zzzz-no-match")
        wait(any("journal.timeline.noMatches"), 10)
        XCTAssertFalse(any("journal.timeline.empty").exists, "no hits is not an empty journal")
        shot("jt-03-no-matches")
    }

    func testTimelineReadFailureIsAnErrorNotAnEmptyJournal() {
        launch(extra: ["-qaJournalTimeline", "failure"])
        openTimeline()
        wait(any("journal.timeline.error"), 10)
        wait(app.buttons["Try again"], 10)
        XCTAssertFalse(any("journal.timeline.empty").exists, "a read failure must not look like no entries")
        XCTAssertFalse(text("No journal entries yet").exists)
        shot("jt-04-read-failure")
    }

    /// No fixture: the real (in-memory under UI tests) store through FoodJournalStore.timelineItems.
    func testTimelineRealStoreEmptySaysSo() {
        launch()
        openTimeline()
        wait(any("journal.timeline.empty"), 10)
        shot("jt-05-real-store-empty")
    }

    func testTimelineRecoveredOpenStateShowsBannerAndNoEmptyClaim() {
        launch(extra: ["-qaJournalOpenState", "recovered"])
        openTimeline()
        _ = banner()
        XCTAssertFalse(any("journal.timeline.empty").exists, "a recovered-empty journal must not read as real history")
        shot("jt-06-recovered-banner")
    }

    /// Fixture at an accessibility text size: the first row is shown and the filter control stays reachable.
    func testTimelineFixtureAtLargestTextSizeKeepsRowAndFilterReachable() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTimeline()
        wait(row("Oat porridge"), 10)
        XCTAssertTrue(any("journal.timeline.filter").waitForExistence(timeout: 10))
        XCTAssertTrue(any("journal.timeline.filter").isHittable, "the filter must stay tappable at the largest text size")
        shot("jt-07-fixture-large-text")
    }

    /// Normal-size coverage, separate from the retained original cross-size case.
    func testTimelineFixtureAtNormalTextKeepsRowAndFilterReachable() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        openTimeline()
        wait(row("Oat porridge"), 10)
        XCTAssertTrue(any("journal.timeline.filter").waitForExistence(timeout: 10))
        XCTAssertTrue(any("journal.timeline.filter").isHittable, "the filter must stay tappable at normal text size")
        shot("jt-07-fixture-normal-text")
    }

    /// The last fixture entry must clear the pinned search drawer and bottom chrome at the largest text size.
    /// Geometry cannot prove readable text under a translucent bar, so jt-08 is captured BEFORE any assertion for
    /// visual inspection. A missing row, a missing search bar, no clearance after the bounded scroll, or a timeout is
    /// reported as what it is; none of them is assumed to be an app defect.
    func testTimelineFixtureAtLargestTextSizeLastRowClearsSearchBar() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTimeline()
        let nav = app.navigationBars["Food Journal"]   // the same bar openTimeline() waits for
        let searchBar = app.searchFields.firstMatch    // the pinned navigation-bar drawer
        let bottomAccessory = any("bottomAccessory")
        let tabBar = app.tabBars.firstMatch
        let last = row("Soup was the best part")
        _ = searchBar.waitForExistence(timeout: 10)    // non-asserting; existence is asserted after the screenshot
        // The last row is lazily realized, so it is not waited for before scrolling: the bounded loop brings it in.
        func clear() -> Bool {
            guard last.exists, last.isHittable, nav.exists, searchBar.exists,
                  searchBar.isHittable, tabBar.exists else { return false }
            let top = max(nav.frame.maxY, searchBar.frame.maxY)
            let bottom = bottomAccessory.exists ? min(bottomAccessory.frame.minY, tabBar.frame.minY) : tabBar.frame.minY
            return last.frame.minY >= top && last.frame.maxY <= bottom
        }
        var swipes = 0
        while !clear() && swipes < 6 { app.swipeUp(); swipes += 1 }
        shot("jt-08-fixture-large-text-last-row")
        if bottomAccessory.exists {
            let add = app.buttons["accessoryAdd"]
            XCTAssertTrue(add.isHittable, "the journal add action must stay reachable at the largest text size")
            XCTAssertEqual(add.label, "New journal entry", "VoiceOver must retain the full journal action name")
        }
        XCTAssertTrue(nav.exists, "the Food Journal navigation bar must exist (swipes: \(swipes))")
        XCTAssertTrue(searchBar.exists, "the search field must exist (swipes: \(swipes))")
        XCTAssertTrue(searchBar.isHittable, "the pinned search drawer must remain reachable")
        XCTAssertTrue(tabBar.exists, "the bottom tab bar must exist")
        XCTAssertTrue(last.exists, "the last row was never realized after \(swipes) swipes")
        XCTAssertTrue(clear(),
                      "the last row must clear the navigation/search drawer and bottom chrome (swipes: \(swipes), row: \(last.frame), nav: \(nav.frame), bar: \(searchBar.frame), hittable: \(last.isHittable))")
    }

    /// Normal-size coverage, separate from the retained original cross-size case.
    func testTimelineFixtureAtNormalTextLastRowClearsSearchBar() {
        launch(extra: ["-qaJournalTimeline", "fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        openTimeline()
        let nav = app.navigationBars["Food Journal"]   // the same bar openTimeline() waits for
        let searchBar = app.searchFields.firstMatch    // the pinned navigation-bar drawer
        let bottomAccessory = any("bottomAccessory")
        let tabBar = app.tabBars.firstMatch
        let last = row("Soup was the best part")
        _ = searchBar.waitForExistence(timeout: 10)    // non-asserting; existence is asserted after the screenshot
        // The last row is lazily realized, so it is not waited for before scrolling: the bounded loop brings it in.
        func clear() -> Bool {
            guard last.exists, last.isHittable, nav.exists, searchBar.exists,
                  searchBar.isHittable, tabBar.exists else { return false }
            let top = max(nav.frame.maxY, searchBar.frame.maxY)
            let bottom = bottomAccessory.exists ? min(bottomAccessory.frame.minY, tabBar.frame.minY) : tabBar.frame.minY
            return last.frame.minY >= top && last.frame.maxY <= bottom
        }
        var swipes = 0
        while !clear() && swipes < 6 { app.swipeUp(); swipes += 1 }
        shot("jt-08-fixture-normal-text-last-row")
        if bottomAccessory.exists {
            let add = app.buttons["accessoryAdd"]
            XCTAssertTrue(add.isHittable, "the journal add action must stay reachable at normal text size")
            XCTAssertEqual(add.label, "New journal entry", "VoiceOver must retain the full journal action name")
        }
        XCTAssertTrue(nav.exists, "the Food Journal navigation bar must exist (swipes: \(swipes))")
        XCTAssertTrue(searchBar.exists, "the search field must exist (swipes: \(swipes))")
        XCTAssertTrue(searchBar.isHittable, "the pinned search drawer must remain reachable")
        XCTAssertTrue(tabBar.exists, "the bottom tab bar must exist")
        XCTAssertTrue(last.exists, "the last row was never realized after \(swipes) swipes")
        XCTAssertTrue(clear(),
                      "the last row must clear the navigation/search drawer and bottom chrome (swipes: \(swipes), row: \(last.frame), nav: \(nav.frame), bar: \(searchBar.frame), hittable: \(last.isHittable))")
    }
}
