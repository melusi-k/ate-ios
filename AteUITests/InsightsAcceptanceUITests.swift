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

    /// Handle only the identified iOS slide-to-type onboarding, not a generic Continue.
    private func dismissSystemTypingTipIfPresented() {
        let hosts = [app!, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        let message = "Speed up your typing by sliding your finger"
        let tips = hosts.map {
            $0.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", message)).firstMatch
        }.filter { $0.exists }
        guard !tips.isEmpty else { return }
        var eligible: [XCUIElement] = []
        for host in hosts {
            let buttons = host.buttons.matching(NSPredicate(format: "label ==[c] 'Continue'"))
            for index in 0..<buttons.count {
                let button = buttons.element(boundBy: index)
                guard button.exists, button.isHittable else { continue }
                let frame = button.frame
                guard tips.contains(where: { tip in
                    let textFrame = tip.frame
                    return !textFrame.isEmpty && app.frame.intersects(textFrame)
                        && frame.minY >= textFrame.maxY - 1
                        && frame.minY <= textFrame.maxY + 160
                        && min(frame.maxX, textFrame.maxX) > max(frame.minX, textFrame.minX)
                        && abs(frame.midX - textFrame.midX) <= textFrame.width / 2
                }) else { continue }
                // App and SpringBoard can expose aliases of one physical control.
                guard !eligible.contains(where: { existing in
                    let old = existing.frame
                    return abs(old.minX - frame.minX) < 1 && abs(old.minY - frame.minY) < 1
                        && abs(old.width - frame.width) < 1 && abs(old.height - frame.height) < 1
                }) else { continue }
                eligible.append(button)
            }
        }
        guard eligible.count == 1 else {
            XCTFail("The system typing tip must have exactly one distinct reachable Continue action")
            return
        }
        eligible[0].tap()
        for host in hosts {
            let tip = host.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", message)).firstMatch
            XCTAssertTrue(tip.waitForNonExistence(timeout: 3),
                          "The system typing tip must close in both queried hosts")
        }
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

    private func assertQuietInsightControls(_ id: String) {
        let card = app.descendants(matching: .any)["insights.progress.candidate." + id].firstMatch
        wait(card)
        XCTAssertFalse(app.staticTexts["insights.progress.evidence." + id].exists,
                       "Evidence and confidence stay internal, not customer-facing card copy")
        let done = app.buttons["insights.progress.resolve." + id]
        wait(done)
        XCTAssertEqual(done.label, "Done")
        XCTAssertEqual(card.buttons.matching(NSPredicate(format: "label == %@", "Done")).count, 1)
        XCTAssertEqual(app.buttons["insights.progress.snooze." + id].label, "Remind me later")
        XCTAssertEqual(app.buttons["insights.progress.dismiss." + id].label, "Dismiss")
    }

    // Existing selector is retained for CI routing; evidence now means internal provenance.
    func testWeeklyCookingInsightShowsEvidenceAndNavigatesToTracker() {
        launch()
        addAndCompleteRecipe()

        reopenInsightsFromJournal()

        let action = app.buttons["insights.progress.action.weekly-cooking"]
        reveal(action)
        assertQuietInsightControls("weekly-cooking")

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
        let beforeOpen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beforeOpen.name = "insight-normal-before-open"
        beforeOpen.lifetime = .keepAlways
        add(beforeOpen)
        action.tap()
        wait(app.navigationBars["Insights & Cooking History"], 8)
        let day = Calendar.current.component(.day, from: Date())
        let today = app.buttons["tracker.day.\(day)"]
        wait(today, 5)
        XCTAssertTrue(today.isHittable)
        today.tap()
        let daySheet = app.navigationBars["Cooked that day"]
        wait(daySheet, 5)
        // This journey checks one outside tap, not swipe support or AX shield count.
        let dismissRegions = app.otherElements.matching(identifier: "PopoverDismissRegion")
        let regionCount = dismissRegions.count
        let regionObservation = XCTAttachment(string:
            "PopoverDismissRegion count=\(regionCount); duplicate exposure is diagnostic, not dismissal behaviour")
        regionObservation.name = "day-sheet-dismiss-region-observation"
        regionObservation.lifetime = .keepAlways
        add(regionObservation)
        let hubBar = app.navigationBars["Insights & Cooking History"]
        let appFrame = app.frame
        let sheetNavigationFrame = daySheet.frame
        // Bind geometry to the smallest real container that contains this sheet bar.
        // Equal nested container frames are harmless; no dismissal shield is selected.
        let sheetFrames = app.otherElements
            .containing(.navigationBar, identifier: "Cooked that day")
            .allElementsBoundByIndex.map { $0.frame }
            .filter { !$0.isEmpty && $0.contains(sheetNavigationFrame) && appFrame.contains($0) }
        let sheetFrame = sheetFrames.min { $0.width * $0.height < $1.width * $1.height }
        // The retained native frame places this explanatory copy on the dimmed
        // tracker, well above the day sheet. Do not tap a calendar day or control.
        let explanation = app.staticTexts[
            "Finish cooking in Cook Mode to record a day. Tap a date to see what you cooked."
        ]
        let explanationFrame = explanation.frame
        let target = CGPoint(x: explanationFrame.midX, y: explanationFrame.midY)
        let beforeTap = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beforeTap.name = "day-sheet-before-outside-tap"
        beforeTap.lifetime = .keepAlways
        add(beforeTap)
        let beforeAX = XCTAttachment(string: app.debugDescription)
        beforeAX.name = "day-sheet-before-outside-tap-AX"
        beforeAX.lifetime = .keepAlways
        add(beforeAX)
        guard let sheetFrame, explanation.exists, hubBar.exists,
              !appFrame.isEmpty, !sheetNavigationFrame.isEmpty, !explanationFrame.isEmpty,
              appFrame.contains(explanationFrame),
              explanationFrame.minY > hubBar.frame.maxY + 16,
              sheetFrame.height < appFrame.height,
              explanationFrame.maxY < sheetFrame.minY - 16,
              appFrame.contains(target) else {
            XCTFail("No verified non-control tracker background above the real day sheet")
            return
        }
        // Check underlying controls too, even while the sheet makes them unhittable.
        let controlTypes: [XCUIElement.ElementType] = [
            .button, .textField, .secureTextField, .textView, .switch, .slider,
            .picker, .pickerWheel, .segmentedControl, .link
        ]
        for type in controlTypes {
            for control in app.descendants(matching: type).allElementsBoundByIndex {
                if control.exists && control.frame.insetBy(dx: -8, dy: -8).contains(target) {
                    XCTFail("Outside-tap point overlaps a control: \(control.identifier)")
                    return
                }
            }
        }
        let geometry = XCTAttachment(string:
            "outsideTap=\(target); trackerExplanation=\(explanationFrame); sheet=\(sheetFrame); sheetNavigation=\(sheetNavigationFrame)")
        geometry.name = "day-sheet-outside-tap-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        // One app coordinate tap only. No shield-node selection, retry or second gesture.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x - appFrame.minX,
                                 dy: target.y - appFrame.minY)).tap()
        let daySheetClosed = daySheet.waitForNonExistence(timeout: 5)
        let afterTap = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterTap.name = "day-sheet-after-outside-tap"
        afterTap.lifetime = .keepAlways
        add(afterTap)
        let afterAX = XCTAttachment(string: app.debugDescription)
        afterAX.name = "day-sheet-after-outside-tap-AX"
        afterAX.lifetime = .keepAlways
        add(afterAX)
        if !daySheetClosed {
            // Capture at the failed disappearance wait, before XCTest stops this journey.
            let failureShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            failureShot.name = "day-sheet-disappearance-failure"
            failureShot.lifetime = .keepAlways
            add(failureShot)
            let failureAX = XCTAttachment(string: app.debugDescription)
            failureAX.name = "day-sheet-disappearance-failure-AX"
            failureAX.lifetime = .keepAlways
            add(failureAX)
        }
        XCTAssertTrue(daySheetClosed, "The real day-details sheet must close before returning")
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
        let afterDismiss = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterDismiss.name = "insight-normal-after-explicit-dismiss"
        afterDismiss.lifetime = .keepAlways
        add(afterDismiss)
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
        dismissSystemTypingTipIfPresented()
        // The hub is above the composer. Move only the Journal list toward its top.
        for _ in 0..<6 where !hub.isHittable { app.swipeDown() }
        XCTAssertTrue(hub.isHittable, "Journal's named hub must be visible before tapping")
        hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
        XCTAssertFalse(app.descendants(matching: .any)["journal.reflection"].firstMatch.exists,
                       "The composer must not be duplicated in the hub")
        app.navigationBars["Insights & Cooking History"].buttons["Journal"].tap()
        wait(field)
        dismissSystemTypingTipIfPresented()
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
        dismissSystemTypingTipIfPresented()
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

    func testExploreOpensNewSuggestionsNotLibraryAndUnavailableAIIsHonest() {
        launch(); addAndCompleteRecipe(); reopenInsightsFromJournal()
        let action = app.buttons["insights.progress.action.recipe-discovery"]
        reveal(action)
        assertQuietInsightControls("recipe-discovery")
        let header = app.staticTexts["Recipe & cooking insights"]
        let title = app.staticTexts["insights.progress.title.recipe-discovery"]
        wait(header); wait(title)
        XCTAssertLessThan(header.frame.maxY, title.frame.minY,
                          "The secondary section label must sit clearly above the primary insight title")
        seededShot("insights-normal-quiet-header-primary-title-controls")
        action.tap()
        wait(app.navigationBars["Suggested new recipes"])
        let status = app.staticTexts["discovery.status"]
        wait(status)
        XCTAssertTrue(status.label.contains("On-device AI is not available"), status.label)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery.save.")).count, 0,
                       "A simulator or mock backend must never substitute saved or Demo recipes")
        seededShot("insights-new-suggestions-unavailable-no-demo")
        app.navigationBars["Suggested new recipes"].buttons["Close"].tap()
        wait(app.navigationBars["Insights & Cooking History"])
        reveal(action)
        XCTAssertTrue(action.isHittable, "Opening suggestions must not auto-dismiss the insight")
    }

    private func launchSeededDestinations() {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-qaResetCookingHistory", "-qaResetInsightLifecycle",
                               "-qaInsightDestinations", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let journal = app.tabBars.buttons["Journal"]
        wait(journal); journal.tap()
        wait(app.navigationBars["Journal"])
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub); hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
    }

    private func seededShot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// These actions dismiss their pushed hub before switching tabs. Assert the
    /// resulting Journal root, rather than assuming a preserved pushed stack.
    private func returnToSeededInsight(_ id: String) {
        let journal = app.tabBars.buttons["Journal"]
        wait(journal); journal.tap()
        wait(app.navigationBars["Journal"])
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub); hub.tap()
        wait(app.navigationBars["Insights & Cooking History"])
        let action = app.buttons["insights.progress.action." + id]
        reveal(action)
        XCTAssertTrue(action.exists && action.isHittable, "Opening a destination must not dismiss unchanged evidence")
        seededShot("195-" + id + "-retained-after-return-normal")
    }

    func testSeededShoppingInsightOpensRealListAndRetainsSuggestion() {
        launchSeededDestinations()
        let action = app.buttons["insights.progress.action.shopping-multi-recipe"]
        reveal(action)
        assertQuietInsightControls("shopping-multi-recipe")
        seededShot("195-shopping-insight-before-action-normal")
        action.tap()
        wait(app.navigationBars["Shopping list"])
        XCTAssertTrue(app.tabBars.buttons["Shopping"].isSelected)
        let rice = app.buttons["shopping.edit.qa-insight-rice"]
        wait(rice)
        XCTAssertTrue(rice.isHittable, "Destination must contain the real seeded pending item")
        wait(app.staticTexts["3 to buy"])
        seededShot("195-shopping-real-seeded-destination-normal")
        // Reaching lower Shopping content can minimize iOS 26 tab chrome. One
        // reverse content gesture reveals it before the one Journal tap. No retry.
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
        seededShot("195-shopping-tab-chrome-revealed-normal")
        returnToSeededInsight("shopping-multi-recipe")
    }

    func testSeededDiaryInsightOpensRealDiaryAndRetainsSuggestion() {
        launchSeededDestinations()
        let action = app.buttons["insights.progress.action.nutrition-diary-coverage"]
        reveal(action)
        assertQuietInsightControls("nutrition-diary-coverage")
        seededShot("195-diary-insight-before-action-normal")
        action.tap()
        let diary = app.navigationBars["Food diary"]
        wait(diary)
        XCTAssertEqual(app.navigationBars.count, 1)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "nutritionDiary.entry."))
        // Food diary is a lazy List: daily and weekly totals precede the meal rows.
        // The final-head failure AX/pixels show those totals, not an empty diary.
        // Scroll the one mounted diary list before asking for its three real records.
        let lists = app.collectionViews
        XCTAssertEqual(lists.count, 1, "Food diary must own one visible content list")
        let list = lists.element(boundBy: 0)
        wait(list)
        seededShot("195-diary-destination-before-meal-scroll-normal")
        for _ in 0..<4 where rows.count < 3 { list.swipeUp() }
        wait(rows.firstMatch)
        XCTAssertEqual(rows.count, 3, "The actual diary must read the three synthetic records")
        let food = rows.matching(NSPredicate(format: "label CONTAINS %@", "QA insight food 1")).firstMatch
        wait(food)
        seededShot("195-diary-real-seeded-destination-normal")
        let back = diary.buttons["Settings"]
        wait(back); back.tap()
        wait(app.navigationBars["Settings"])
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertEqual(app.tabBars.buttons.matching(identifier: "Settings").count, 1,
                       "Back must expose exactly one selected Settings capsule")
        XCTAssertTrue(settingsTab.isSelected)
        XCTAssertTrue(settingsTab.isHittable, "The selected Settings capsule must be reachable")
        seededShot("195-diary-settings-before-tab-expansion-normal")
        // Diary's real-row scroll can minimize the system tab bar. Native Back
        // returns to Settings but does not promise an expanded tab strip. Expand
        // once through its selected capsule, just like the strict header journey;
        // then retain the single Journal tap and all hub/evidence assertions.
        settingsTab.tap()
        wait(app.navigationBars["Settings"])
        XCTAssertTrue(settingsTab.isSelected, "Expanding chrome must not switch destinations")
        seededShot("195-diary-settings-after-tab-expansion-normal")
        returnToSeededInsight("nutrition-diary-coverage")
    }

}
