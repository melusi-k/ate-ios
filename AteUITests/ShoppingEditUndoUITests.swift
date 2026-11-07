import XCTest

/// Shopping edit/undo behaviour journeys (#72). Logic-level coverage lives in
/// AteTests/ShoppingRecoveryTests; these exercise the real UI paths: in-place edit
/// (save / cancel / invalid quantity), batch Undo restoring original order, and
/// Undo-window expiry finalizing a removal.
final class ShoppingEditUndoUITests: XCTestCase {
    private func launchShopping(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetShopping"] + extraArgs
        app.launch()
        let tab = app.tabBars.buttons["Shopping"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Shopping should be a first-class tab")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Shopping list"].waitForExistence(timeout: 10))
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func add(_ app: XCUIApplication, _ name: String) {
        let field = app.textFields["shoppingAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the add field should be visible")
        field.tap()
        field.typeText(name + "\n")
        XCTAssertTrue(app.buttons["Edit \(name)"].waitForExistence(timeout: 5),
                      "a row for \(name) should appear after adding")
    }

    /// Same field-replacement pattern as KeyFlowsQATests.replace: tap to focus, tap the
    /// trailing edge to move the caret to the end, delete the current value, then type.
    /// (The iOS edit menu's "Select All" item is not reliably exposed in UI tests.)
    private func replaceText(of field: XCUIElement, with text: String) {
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(text)
    }

    func testEditSaveCancelAndInvalidQuantityJourneys() {
        let app = launchShopping()
        add(app, "Milk")

        // Save journey: rename the item and set a quantity; the row keeps its place.
        app.buttons["Edit Milk"].tap()
        XCTAssertTrue(app.navigationBars["Edit item"].waitForExistence(timeout: 5))
        let nameField = app.textFields["shopping.edit.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        replaceText(of: nameField, with: "Oat milk")
        let quantityField = app.textFields["shopping.edit.quantity"]
        replaceText(of: quantityField, with: "2")
        app.buttons["shopping.edit.save"].tap()
        XCTAssertTrue(app.buttons["Edit Oat milk"].waitForExistence(timeout: 5),
                      "the renamed row should replace the old one after Save")
        XCTAssertFalse(app.buttons["Edit Milk"].exists)
        screenshot("edit-save-row-renamed")

        // Invalid journey: an unparseable quantity explains itself and disables Save.
        app.buttons["Edit Oat milk"].tap()
        XCTAssertTrue(app.navigationBars["Edit item"].waitForExistence(timeout: 5))
        let quantity = app.textFields["shopping.edit.quantity"]
        replaceText(of: quantity, with: "2.5.3")
        XCTAssertTrue(app.staticTexts["Enter a quantity of zero or more."].waitForExistence(timeout: 3),
                      "the editor must say why the quantity is rejected")
        XCTAssertFalse(app.buttons["shopping.edit.save"].isEnabled,
                       "Save must stay disabled while the quantity cannot be parsed")
        screenshot("edit-invalid-quantity-save-disabled")

        // Cancel journey: leaving without saving keeps the stored values.
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Edit Oat milk"].waitForExistence(timeout: 5),
                      "Cancel must not apply the edited values")
    }

    func testBatchUndoRestoresBothRemovalsInOriginalOrder() {
        // The production 5s Undo window is too short for XCTest to observe the toast,
        // capture its screenshot and synthesize the tap (observed ~5.5s in the runner, so
        // the window expired just before the tap landed). Widen the window for this
        // journey; window-expiry behaviour itself is covered by testUndoWindowExpiryFinalizesRemoval.
        let app = launchShopping(extraArgs: ["-qaShoppingUndoSeconds", "30"])
        // Same-aisle fixture (all dairy): aisle grouping lists bakery before dairy, so a
        // mixed-aisle fixture would not reflect list order visually either way grouped.
        add(app, "Milk")
        add(app, "Eggs")
        add(app, "Yogurt")

        app.buttons["Remove Milk"].tap()
        app.buttons["Remove Eggs"].tap()
        XCTAssertTrue(app.staticTexts["Removed 2 items"].waitForExistence(timeout: 3),
                      "the second quick removal must join one batch toast")
        let undo = app.buttons["toastAction"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertEqual(undo.label, "Undo")
        screenshot("batch-undo-toast-two-items")
        undo.tap()

        let milk = app.buttons["Edit Milk"]
        let eggs = app.buttons["Edit Eggs"]
        let yogurt = app.buttons["Edit Yogurt"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertTrue(eggs.waitForExistence(timeout: 5))
        XCTAssertTrue(yogurt.waitForExistence(timeout: 5))
        XCTAssertLessThan(milk.frame.minY, eggs.frame.minY, "Milk must come back before Eggs")
        XCTAssertLessThan(eggs.frame.minY, yogurt.frame.minY, "Eggs must come back before Yogurt")
        screenshot("batch-undo-restored-order")
    }


    /// Completion feedback: the progress row reflects bought items and one tap moves them
    /// all back to the to-buy list (the toast offers Undo).
    func testProgressShowsBoughtAndMoveAllBackReturnsThemToList() {
        let app = launchShopping(extraArgs: ["-qaShoppingUndoSeconds", "30"])
        add(app, "Milk")
        add(app, "Eggs")
        let progress = app.descendants(matching: .any)["shopping.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "a progress indicator should show once the list has items")
        XCTAssertFalse(app.buttons["shopping.moveBoughtBack"].exists, "nothing bought: no move-back action")
        app.buttons["Mark Milk as bought"].tap()
        XCTAssertTrue(NSPredicate(format: "value == %@", "1 of 2 bought").evaluate(with: progress) ||
                      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1 of 2 bought"), object: progress)], timeout: 5) == .completed,
                      "progress reads 1 of 2 bought, got \(String(describing: progress.value))")
        let back = app.buttons["shopping.moveBoughtBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        screenshot("shopping-progress-one-bought")
        back.tap()
        XCTAssertTrue(app.buttons["Mark Milk as bought"].waitForExistence(timeout: 5),
                      "Milk is back on the to-buy list")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0 of 2 bought"), object: progress)], timeout: 5), .completed,
                       "progress reads 0 of 2 bought, got \(String(describing: progress.value))")
        XCTAssertFalse(back.exists)
        XCTAssertTrue(app.staticTexts["1 item back on the list"].waitForExistence(timeout: 3))
        screenshot("shopping-moved-back-toast")
        app.buttons["toastAction"].tap()
        XCTAssertTrue(app.buttons["Mark Milk as not bought"].waitForExistence(timeout: 5),
                      "Undo re-marks Milk as bought")
    }

    /// Timely-restore acceptance journey: a real UI Undo tap landing inside the
    /// production 5-second window must restore the item. Runs WITHOUT the
    /// -qaShoppingUndoSeconds seam, so the production window applies. The sequence is
    /// deliberately lean (no screenshots or assertions between the removal tap and the
    /// Undo tap) because XCTest observe + synthesize latency is the only thing that can
    /// push the tap past the window.
    ///
    /// Verdict semantics (see workflow gate comments):
    /// - GREEN proves the production-config restore path works via the UI tap. It says
    ///   nothing about general human usability or app responsiveness.
    /// - RED is INCONCLUSIVE by default: xcodebuild "Synthesize event" completion
    ///   timestamps are only bounds on the real removal/expiry/event-delivery instants,
    ///   so even a synthetic tap-to-tap interval under 5s does not prove an app defect.
    ///   Classify from the raw timestamp bounds plus visible toast/item state; call it
    ///   an app defect only if app-owned timing evidence corroborates that the tap
    ///   landed before expiry.
    func testTimelyUndoRestoreWithinProductionWindow() {
        let app = launchShopping()
        add(app, "Milk")

        app.buttons["Remove Milk"].tap()
        let undo = app.buttons["toastAction"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2),
                      "the Undo toast should appear promptly after a removal")
        undo.tap()

        XCTAssertTrue(app.buttons["Edit Milk"].waitForExistence(timeout: 5),
                      "a tap inside the production window must restore the removed item")
        screenshot("timely-undo-restored")
    }

    func testUndoWindowExpiryFinalizesRemoval() {
        let app = launchShopping()
        add(app, "Milk")
        app.buttons["Remove Milk"].tap()
        let undo = app.buttons["toastAction"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))

        let expired = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: undo)
        XCTAssertEqual(XCTWaiter.wait(for: [expired], timeout: 12), .completed,
                       "the Undo toast must expire on its 5-second schedule")
        XCTAssertFalse(app.buttons["Edit Milk"].exists,
                       "a finalized removal must stay removed")
        screenshot("undo-expired-removal-final")
    }
}
