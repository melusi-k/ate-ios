import XCTest

/// Additional AX contract; the original full sheet journey remains unchanged.
final class RecipeStaticRowAccessibilityUITests: XCTestCase {
    func testCombinedRecipeRowsRetainQuantityNameStepNumberAndInstruction() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["accessoryAdd"].tap()
        XCTAssertTrue(app.buttons["Prompt"].waitForExistence(timeout: 10))
        app.buttons["Prompt"].tap()
        let editor = app.textViews["promptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap()
        XCTAssertTrue(app.buttons["Cook mode"].waitForExistence(timeout: 10))
        let ingredient = app.descendants(matching: .any).matching(identifier: "recipe.ingredient.1")
        let step = app.descendants(matching: .any).matching(identifier: "recipe.step.1")
        XCTAssertEqual(ingredient.count, 1)
        XCTAssertEqual(step.count, 1)
        XCTAssertTrue(ingredient.element.label.contains("2"), "Ingredient quantity must remain spoken")
        XCTAssertTrue(ingredient.element.label.localizedCaseInsensitiveContains("salmon fillets"),
                      "Ingredient name must remain in the same spoken row")
        XCTAssertTrue(step.element.label.contains("1"), "Step number must remain in the combined spoken row")
        XCTAssertTrue(step.element.label.contains("Heat the oven"), "Full instruction must remain spoken")
        XCTAssertEqual(app.staticTexts.matching(identifier: "recipe.steps.heading").count, 1)
    }
}
