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
        tab("Journal")
        // Journal is the tab root; Insights & Cooking History is its one named route.
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10), "Journal root must expose Insights & Cooking History")
        hub.tap()
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
        tab("Library")
    }

    private func reveal(_ element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        let carousel = app.scrollViews["insights.progress.results"]
        if element.identifier.hasPrefix("insights.progress."), carousel.exists && !element.isHittable {
            for _ in 0..<3 where !element.isHittable { carousel.swipeLeft() }
            for _ in 0..<3 where !element.isHittable { carousel.swipeRight() }
        }
        wait(element, 15)
        XCTAssertTrue(element.isHittable, "The insight action must be reachable after \(swipes) swipes.")
    }

    /// Switching tabs preserves the pushed hub. Return to Journal explicitly instead of
    /// assuming a second tab selection pops a stack that was not currently selected.
    private func reopenInsightsFromJournal() {
        tab("Journal")
        let title = app.navigationBars["Insights & Cooking History"]
        wait(title)
        let back = title.buttons["Journal"]
        wait(back)
        back.tap()
        wait(app.navigationBars["Journal"])
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub)
        hub.tap()
        wait(title)
    }

    func testInsightCanBeResolvedAndStaysSuppressedAfterRefresh() {
        launch()
        addAndCompleteRecipe()

        reopenInsightsFromJournal()

        let resolve = app.buttons["insights.progress.resolve.weekly-cooking"]
        reveal(resolve)
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

        reopenInsightsFromJournal()

        let action = app.buttons["insights.progress.action.weekly-cooking"]
        reveal(action)
        let evidence = app.staticTexts["insights.progress.evidence.weekly-cooking"]
        wait(evidence, 5)
        XCTAssertTrue(evidence.label.contains("Cooking history"), evidence.label)
        XCTAssertTrue(evidence.label.contains("This week"), evidence.label)
        XCTAssertTrue(evidence.label.contains("Confidence: High"), evidence.label)

        action.tap()

        // A pushed hub must stay on screen and reveal its cooking calendar, not pop to Journal.
        wait(app.navigationBars["Insights & Cooking History"], 8)
        let trackerTab = app.tabBars.buttons["Journal"]
        wait(trackerTab, 8)
        XCTAssertTrue(trackerTab.isSelected, "The contextual action should select the tracker tab.")
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.isHittable, "The cooking-history action must reveal today's calendar button.")
        XCTAssertTrue(today.label.contains("cooked") && today.label.contains("today"), today.label)
        let afterAction = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterAction.name = "insights-cooking-history-action-reveals-today"
        afterAction.lifetime = .keepAlways
        add(afterAction)
    }
    func testOpeningCookingHistoryKeepsInsightUntilExplicitDismissal() {
        launch()
        addAndCompleteRecipe()
        reopenInsightsFromJournal()
        let action = app.buttons["insights.progress.action.weekly-cooking"]
        reveal(action)
        action.tap()
        wait(app.navigationBars["Insights & Cooking History"], 8)
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.isHittable)
        today.tap()
        let daySheet = app.navigationBars["Cooked that day"]
        wait(daySheet, 5)
        daySheet.swipeDown()
        XCTAssertTrue(daySheet.waitForNonExistence(timeout: 5), "The real day-details sheet must close before returning")
        app.navigationBars["Insights & Cooking History"].buttons["Journal"].tap()
        wait(app.navigationBars["Journal"], 5)
        app.buttons["journal.insightsHistory"].tap()
        wait(app.navigationBars["Insights & Cooking History"], 8)
        reveal(action)
        XCTAssertTrue(action.exists, "Opening cooking history and returning must not dismiss its suggestion")
        let afterOpen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterOpen.name = "insight-normal-retained-after-open"
        afterOpen.lifetime = .keepAlways
        add(afterOpen)
        let refresh = app.buttons["insights.refresh"]
        for _ in 0..<6 where !refresh.isHittable { app.swipeDown() }
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        reveal(action)
        XCTAssertTrue(action.exists, "Unchanged seen evidence must remain after refresh")
        let dismiss = app.buttons["insights.progress.dismiss.weekly-cooking"]
        reveal(dismiss)
        dismiss.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5), "Only explicit dismissal should remove this suggestion")
    }

    func testJournalRootReflectionPlacementDraftAndSaveWithoutHealth() {
        launch()
        tab("Journal")
        let hub = app.buttons["journal.insightsHistory"]
        let reflection = app.descendants(matching: .any)["journal.reflection"].firstMatch
        let field = app.descendants(matching: .any)["insights.journalText"].firstMatch
        wait(hub); wait(reflection)
        XCTAssertGreaterThanOrEqual(reflection.frame.minY, hub.frame.maxY,
                                    "Reflection belongs directly below the named hub link")
        wait(app.staticTexts["journal.reflection.manualPrompt"])
        let seed = "Root reflection " + UUID().uuidString
        reveal(field); field.tap(); field.typeText(seed)
        // The hub is above the composer. Move only the Journal list toward its top.
        for _ in 0..<6 where !hub.isHittable { app.swipeDown() }
        XCTAssertTrue(hub.isHittable, "Journal's named hub must be visible before tapping")
        hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
        XCTAssertFalse(app.descendants(matching: .any)["journal.reflection"].firstMatch.exists,
                       "The composer must not be duplicated in the hub")
        app.navigationBars["Insights & Cooking History"].buttons["Journal"].tap()
        wait(field)
        XCTAssertEqual(field.value as? String, seed, "Returning to Journal must retain the same draft")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "journal-normal-root-reflection-retained"; shot.lifetime = .keepAlways; add(shot)
        let save = app.buttons["insights.save"]; reveal(save); save.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", seed)).firstMatch
        reveal(saved); saved.tap()
        wait(app.staticTexts["journal.detail.text"])
        XCTAssertEqual(app.staticTexts["journal.detail.text"].label, seed)
    }

    func testJournalRootReflectionFailedSaveKeepsDraftVisible() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaJournalOpenState", "unavailable"]
        app.launch(); tab("Journal")
        let field = app.descendants(matching: .any)["insights.journalText"].firstMatch
        reveal(field); field.tap(); field.typeText("Keep failed draft")
        let save = app.buttons["insights.save"]; reveal(save); save.tap()
        wait(app.staticTexts["insights.journalSaveError"])
        XCTAssertEqual(field.value as? String, "Keep failed draft")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "journal-normal-root-reflection-save-failure"; shot.lifetime = .keepAlways; add(shot)
    }

    func testCandidateCardsScrollSideBySideWithoutDismissing() {
        launch(); addAndCompleteRecipe(); reopenInsightsFromJournal()
        let weekly = app.buttons["insights.progress.action.weekly-cooking"]
        reveal(weekly)
        let discovery = app.buttons["insights.progress.action.recipe-discovery"]
        wait(discovery)
        let carousel = app.scrollViews["insights.progress.results"]
        wait(carousel)
        let weeklyCard = app.descendants(matching: .any)["insights.progress.candidate.weekly-cooking"].firstMatch
        let discoveryCard = app.descendants(matching: .any)["insights.progress.candidate.recipe-discovery"].firstMatch
        let before = weeklyCard.frame
        XCTAssertGreaterThan(discoveryCard.frame.minX, before.minX,
                             "Next insight must sit beside this one, not below it")
        XCTAssertEqual(discoveryCard.frame.minY, before.minY, accuracy: 2,
                       "The independent cards share a horizontal row")
        XCTAssertLessThan(discoveryCard.frame.minX, carousel.frame.maxX,
                          "The next card must visibly peek inside the initial viewport")
        XCTAssertGreaterThan(discoveryCard.frame.maxX, carousel.frame.maxX,
                             "The peek should indicate more card content to swipe to")
        let firstShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        firstShot.name = "insights-normal-horizontal-first-card-peek"
        firstShot.lifetime = .keepAlways; add(firstShot)
        carousel.swipeLeft()
        XCTAssertTrue(discovery.isHittable)
        XCTAssertLessThan(weeklyCard.frame.minX, before.minX, "Horizontal swipe must move the card lane")
        XCTAssertTrue(app.buttons["insights.progress.dismiss.recipe-discovery"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "insights-normal-horizontal-second-card"; shot.lifetime = .keepAlways; add(shot)
        carousel.swipeRight()
        XCTAssertTrue(weekly.isHittable, "Swiping must not dismiss either suggestion")
        XCTAssertTrue(discovery.exists)
    }

    func testJournalRootReflectionLabelsSampleHealthPrompts() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaMockHealth", "recovery", "-qaHealthRecipes"]
        app.launch(); tab("Journal")
        app.buttons["journal.insightsHistory"].tap()
        wait(app.navigationBars["Insights & Cooking History"])
        let connect = app.buttons["insights.connect"]; reveal(connect); connect.tap()
        wait(app.staticTexts["insights.state"])
        app.navigationBars["Insights & Cooking History"].buttons["Journal"].tap()
        let badge = app.descendants(matching: .any)["journal.reflection.sampleBadge"].firstMatch
        reveal(badge)
        XCTAssertTrue(badge.isHittable, "Moved sample prompts must retain their sample provenance")
        let prompt = app.buttons["insights.prompt"].firstMatch
        wait(prompt)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "journal-normal-reflection-sample-provenance"; shot.lifetime = .keepAlways; add(shot)
    }

}
