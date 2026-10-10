import XCTest

/// Widgets & Intents bundle: the app side of widget deep links, Quick add and the Beta page checks.
/// (Widgets themselves can't be driven by XCUITest; their logic is covered by WidgetLogicTests / AppIntentsTests.)
final class WidgetsIntentsUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch(); return app
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testQuickAddDeepLink() {
        launch(["-ateOpenURL", "ate://add/prompt"])
        XCTAssertTrue(app.buttons["addCancel"].waitForExistence(timeout: 10), "Quick add should open Add recipe")
        let prompt = app.segmentedControls.buttons["Prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(prompt.isSelected, "Quick add › Prompt should select the Prompt tab")
        shot("quick-add-prompt")
        app.buttons["addCancel"].tap()
        XCTAssertTrue(app.buttons["addCancel"].waitForNonExistence(timeout: 5))
    }

    func testWidgetDeepLinkOpensRecipe() {
        launch(["-qaHealthRecipes", "-ateOpenURL", "ate://open/qa-h2"])
        XCTAssertTrue(app.navigationBars["Lentil soup"].waitForExistence(timeout: 10), "Widget link should open the recipe")
        shot("widget-open-recipe")
        // Standard Back returns to the Library (never a dead end).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
    }

    func testUnknownWidgetRecipeShowsNotFound() {
        launch(["-ateOpenURL", "ate://open/does-not-exist"])
        let nf = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "not found")).firstMatch
        XCTAssertTrue(nf.waitForExistence(timeout: 10))
    }

    func testBetaPageListsWidgetChecks() {
        launch()
        app.tabBars.buttons["More"].tap()
        app.buttons["more.betaTesting"].tap()
        let diag = app.descendants(matching: .any)["beta.widgetDiagnostics"].firstMatch
        var n = 0
        while !(diag.exists && diag.isHittable) && n < 10 { app.swipeUp(); n += 1 }
        XCTAssertTrue(diag.exists, "Beta page should show the widget diagnostics row")
        XCTAssertTrue(diag.label.contains("App Group"))
        let item = app.descendants(matching: .any)["beta.A-WIDGET-01"].firstMatch
        n = 0
        while !item.exists && n < 25 { app.swipeUp(); n += 1 }
        XCTAssertTrue(item.exists, "Widget checks should appear on the Beta page")
        shot("beta-widget-checks")
    }
}
