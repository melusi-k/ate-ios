import XCTest

/// Real canonical views, typed diary route and disk-backed synthetic legacy upgrade.
/// This does not activate production composition or prove archive/reset/process-kill safety.
final class CanonicalUpgradeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testLegacyMealAndReflectionAppearAndSurviveAppRelaunchInTypedDiary() {
        let app = XCUIApplication()
        let identity = UUID().uuidString
        app.launchArguments = ["-UITesting", "-qaCanonicalUpgrade", identity]
        app.launch()
        XCTAssertTrue(app.navigationBars["Food Journal"].waitForExistence(timeout: 20))
        let rows = app.descendants(matching: .any).matching(identifier: "journal.timeline.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        // A row identifier may occur on both the row and its accessibility container. Use
        // the visible labels instead of claiming count from an unverified element type.
        let mealRow = rows.matching(NSPredicate(format: "label CONTAINS %@", "Sample upgrade lunch")).firstMatch
        let reflectionRow = rows.matching(NSPredicate(format: "label CONTAINS %@", "Sample reflection before upgrade")).firstMatch
        XCTAssertTrue(mealRow.exists)
        XCTAssertTrue(reflectionRow.exists)
        shot("upgrade-01-real-timeline-meal-and-reflection")
        app.buttons["upgradeQA.diary"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
        let meal = app.buttons["nutritionDiary.entry.24500000-0000-4000-8000-000000000002"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        XCTAssertTrue(meal.label.contains("Sample upgrade lunch"))
        shot("upgrade-02-typed-diary-same-migrated-meal")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Food Journal"].waitForExistence(timeout: 20))
        XCTAssertTrue(mealRow.waitForExistence(timeout: 10))
        XCTAssertTrue(reflectionRow.exists)
        shot("upgrade-03-relaunch-disk-timeline")
        app.buttons["upgradeQA.diary"].tap()
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        meal.tap()
        let food = app.textFields["nutritionDiary.foodName"]
        XCTAssertTrue(food.waitForExistence(timeout: 10))
        XCTAssertEqual(food.value as? String, "Sample upgrade lunch")
        shot("upgrade-04-relaunch-preserved-entry-editor")
        // No production files are deleted. The unique synthetic namespace intentionally
        // remains for diagnostics after a failure and is never reused by another test.
    }
    func testTypedGoalsReadsAndSavesIsolatedRuntimeDomainAcrossRelaunch() {
        let app = XCUIApplication()
        let identity = UUID().uuidString
        app.launchArguments = ["-UITesting", "-qaCanonicalUpgrade", identity]
        app.launch()
        XCTAssertTrue(app.buttons["upgradeQA.goals"].waitForExistence(timeout: 20))
        app.buttons["upgradeQA.goals"].tap()
        let energy = app.textFields["nutritionGoals.value.energy"]
        XCTAssertTrue(energy.waitForExistence(timeout: 10))
        XCTAssertEqual(energy.value as? String, "2345", "Must load isolated runtime goals, not default production goals")
        shot("upgrade-goals-01-typed-route-runtime-values")
        let clear = app.buttons["nutritionGoals.clearAll"]
        reveal(clear, in: app)
        clear.tap()
        let save = app.buttons["nutritionGoals.save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["upgradeQA.goals"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["upgradeQA.goals"].waitForExistence(timeout: 20))
        app.buttons["upgradeQA.goals"].tap()
        let enabled = app.switches["nutritionGoals.enabled.energy"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: enabled)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertEqual(enabled.value as? String, "0", "Cleared draft must save to the same runtime domain and survive relaunch")
        XCTAssertFalse(energy.exists)
        shot("upgrade-goals-02-saved-runtime-domain-after-relaunch")
    }


    func testMealBackupReviewCancelThenConfirmOnceOnRealIsolatedStore() {
        let app = launchBackupWorld()
        app.buttons["upgradeQA.backupReview"].tap()
        XCTAssertTrue(app.navigationBars["Review meal backup"].waitForExistence(timeout: 10))
        shot("upgrade-backup-01-review-before-cancel")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["upgradeQA.backupReview"].waitForExistence(timeout: 10))
        XCTAssertFalse(recoveredRow(app).exists, "Cancel review must not import the sample")
        app.buttons["upgradeQA.backupReview"].tap()
        let confirm = app.buttons["mealBackup.confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["mealBackup.result"].waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.isEnabled, "A completed attempt cannot be submitted twice")
        shot("upgrade-backup-02-confirm-once-import-disabled")
        app.buttons["Done"].tap()
        XCTAssertTrue(recoveredRow(app).waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(recoveredRow(app).waitForExistence(timeout: 20))
        shot("upgrade-backup-03-confirmed-record-after-relaunch")
    }

    func testMealBackupCommittedButUnverifiedCannotRetryFromSheet() {
        let app = launchBackupWorld(failVerification: true)
        app.buttons["upgradeQA.backupReview"].tap()
        let confirm = app.buttons["mealBackup.confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let failure = app.staticTexts["mealBackup.failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertTrue(failure.label.contains("could not confirm"))
        XCTAssertFalse(confirm.isEnabled, "An uncertain committed result must not be retried automatically")
        shot("upgrade-backup-04-committed-unverified-import-disabled")
        app.buttons["Done"].tap()
        XCTAssertTrue(recoveredRow(app).waitForExistence(timeout: 10), "Actual committed record remains available for review")
        app.terminate(); app.launch()
        XCTAssertTrue(recoveredRow(app).waitForExistence(timeout: 20))
        shot("upgrade-backup-05-unverified-commit-after-relaunch")
    }

    func testActualFilesPickerCancellationDoesNotShowImportErrorOrAddMeal() {
        let app = launchBackupWorld()
        app.buttons["upgradeQA.diary"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
        let restore = app.buttons["nutritionDiary.restoreMealBackup"]
        reveal(restore, in: app)
        restore.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Actual Files document picker must present Cancel")
        shot("upgrade-backup-06-actual-files-picker")
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["nutritionDiary.error"].exists, "Picker cancellation is no action")
        XCTAssertFalse(app.navigationBars["Review meal backup"].exists)
        XCTAssertFalse(app.buttons["nutritionDiary.entry.24500000-0000-4000-8000-000000000003"].exists)
        shot("upgrade-backup-07-picker-cancel-no-import-error")
    }

    private func launchBackupWorld(failVerification: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaCanonicalUpgrade", UUID().uuidString]
        if failVerification { app.launchArguments.append("-qaRestoreVerificationFailure") }
        app.launch()
        XCTAssertTrue(app.buttons["upgradeQA.backupReview"].waitForExistence(timeout: 20))
        return app
    }
    private func recoveredRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
            "journal.timeline.row", "Sample recovered snack")).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            let top = app.navigationBars.firstMatch.frame.maxY + 4
            let bottom = app.windows.firstMatch.frame.maxY - 12
            if element.exists, element.isHittable, !element.frame.isEmpty,
               element.frame.midY > top, element.frame.midY < bottom { return }
            app.swipeUp(velocity: .slow)
        }
        XCTFail("Control never became visible inside the navigation/window band: \(element)")
    }

}
