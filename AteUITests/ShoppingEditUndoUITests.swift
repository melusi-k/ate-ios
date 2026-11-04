import XCTest

/// Shopping edit/undo behaviour journeys (#72). Logic-level coverage lives in
/// AteTests/ShoppingRecoveryTests; these exercise the real UI paths: in-place edit
/// (save / cancel / invalid quantity), batch Undo restoring original order, and
/// Undo-window expiry finalizing a removal.
final class ShoppingEditUndoUITests: XCTestCase {
    private func launchShopping() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetShopping"]
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

    private func replaceText(of field: XCUIElement, with text: String, in app: XCUIApplication) {
        field.doubleTap()
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), "Select All should appear for \(field)")
        selectAll.tap()
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
        replaceText(of: nameField, with: "Oat milk", in: app)
        let quantityField = app.textFields["shopping.edit.quantity"]
        replaceText(of: quantityField, with: "2", in: app)
        app.buttons["shopping.edit.save"].tap()
        XCTAssertTrue(app.buttons["Edit Oat milk"].waitForExistence(timeout: 5),
                      "the renamed row should replace the old one after Save")
        XCTAssertFalse(app.buttons["Edit Milk"].exists)
        screenshot("edit-save-row-renamed")

        // Invalid journey: an unparseable quantity explains itself and disables Save.
        app.buttons["Edit Oat milk"].tap()
        XCTAssertTrue(app.navigationBars["Edit item"].waitForExistence(timeout: 5))
        let quantity = app.textFields["shopping.edit.quantity"]
        replaceText(of: quantity, with: "2.5.3", in: app)
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
        let app = launchShopping()
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
