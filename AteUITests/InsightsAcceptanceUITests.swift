import XCTest

/// End-to-end acceptance for the evidence-backed Insights card and its contextual navigation.
final class InsightsAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch() -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-qaResetInsightLifecycle"]
        app.launch()
        return app
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)",
                      file: file, line: line)
    }

    private func tab(_ name: String) {
        var attempts = 0
        while !app.tabBars.firstMatch.exists && attempts < 4 {
            let backBar = app.buttons["backBar"].firstMatch
            let navigationBack = app.navigationBars.buttons.element(boundBy: 0)
            if backBar.exists {
                backBar.tap()
            } else if navigationBack.exists {
                navigationBack.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
            }
            sleep(1)
            attempts += 1
        }
        let button = app.tabBars.buttons[name]
        wait(button, 8)
        button.tap()
    }

    private func addAndCompleteRecipe() {
        app.buttons["Add recipe"].tap()
        wait(app.staticTexts["Add a recipe"])
        app.buttons["Prompt"].tap()
        let prompt = app.textViews["promptEditor"]
        wait(prompt)
        prompt.tap()
        prompt.typeText("Miso salmon for two")
        app.buttons["generateButton"].tap()
        wait(app.staticTexts["Review your card"], 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)

        app.buttons["Cook mode"].tap()
        var steps = 0
        while !app.buttons["cookFinish"].exists && steps < 6 {
            let next = app.buttons["Next step"]
            wait(next, 5)
            next.tap()
            steps += 1
        }
        let finish = app.buttons["cookFinish"]
        wait(finish, 5)
        finish.tap()
        wait(app.buttons["Cook mode"], 8)

        // Verify the cooking event is visible in the tracker before testing its downstream insight.
        tab("Insights")
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
        tab("Library")
    }

    func testInsightCanBeResolvedAndStaysSuppressedAfterRefresh() {
        launch()
        addAndCompleteRecipe()

        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        let insightsEntry = app.buttons["library.insights"]
        wait(insightsEntry)
        insightsEntry.tap()

        let resolve = app.buttons["insights.progress.resolve.weekly-cooking"]
        wait(resolve, 15)
        resolve.tap()

        let weeklyAction = app.buttons["insights.progress.action.weekly-cooking"]
        XCTAssertTrue(weeklyAction.waitForNonExistence(timeout: 5),
                      "Resolving an insight should remove that evidence version immediately.")

        let refresh = app.buttons["insights.refresh"]
        wait(refresh, 5)
        let refreshDeadline = Date().addingTimeInterval(5)
        while !refresh.isEnabled && Date() < refreshDeadline { usleep(100_000) }
        XCTAssertTrue(refresh.isEnabled, "Refresh should be enabled after the insight action finishes.")
        refresh.tap()
        XCTAssertTrue(weeklyAction.waitForNonExistence(timeout: 5),
                      "A resolved insight must remain suppressed when refreshed with unchanged evidence.")
    }

    func testWeeklyCookingInsightShowsEvidenceAndNavigatesToTracker() {
        launch()
        addAndCompleteRecipe()

        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        let insightsEntry = app.buttons["library.insights"]
        wait(insightsEntry)
        insightsEntry.tap()

        let action = app.buttons["insights.progress.action.weekly-cooking"]
        wait(action, 15)
        let evidence = app.staticTexts["insights.progress.evidence.weekly-cooking"]
        wait(evidence, 5)
        XCTAssertTrue(evidence.label.contains("Cooking history"), evidence.label)
        XCTAssertTrue(evidence.label.contains("This week"), evidence.label)
        XCTAssertTrue(evidence.label.contains("Confidence: High"), evidence.label)

        action.tap()

        // The Insights Explore sheet must close before the app switches to the tracker tab.
        let trackerTab = app.tabBars.buttons["Insights"]
        wait(trackerTab, 8)
        XCTAssertTrue(trackerTab.isSelected, "The contextual action should select the tracker tab.")
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
    }
}
