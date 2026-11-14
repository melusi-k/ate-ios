import XCTest

final class IngredientDisplayUITests: XCTestCase {
    func testDuplicateLemonAppearsOnceInRealDetailAndNutritionWarningsAtNormalText() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaDuplicateLemonDisplay", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let card = app.buttons["listCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let expand = app.buttons["expandRecipeDetails"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        let full = app.buttons["recipeSheet.expandFully"]
        XCTAssertTrue(full.waitForExistence(timeout: 5)); full.tap()
        let scroll = app.scrollViews["recipe.detail.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let rows = scroll.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe.ingredient."))
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let footer = app.buttons["Cook mode"]
        let header = app.buttons["favouriteButton"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        RecipeDetailVisibility.reveal(row, scroll: scroll, header: header, footer: footer)
        retain("recipe-detail-identical-lemon-row-once-normal")
        XCTAssertTrue(RecipeDetailVisibility.contains(row, scroll: scroll, header: header, footer: footer),
                      "The complete ingredient row must be visible between pinned header and Cook footer")
        XCTAssertEqual(rows.count, 1, "Two old saved lemon rows render as one ingredient, not two")
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("for serving"), row.label)
        XCTAssertTrue(row.label.lowercased().contains("sliced"), row.label)
        let warning = scroll.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No verified food match:")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        for _ in 0..<5 where !warning.isHittable { scroll.swipeUp() }
        XCTAssertTrue(warning.isHittable)
        XCTAssertEqual(warning.label, "No verified food match: for serving",
                       "Nutrition warning display must list the unmatched ingredient only once")
        retain("recipe-nutrition-identical-unmatched-name-once-normal")
    }
    private func retain(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
