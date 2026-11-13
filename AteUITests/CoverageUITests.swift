import XCTest

/// Features without UI coverage until build 49, plus simulator-side Pilot-gate automation
/// (A-SHARE-05 backend down, A-CREATE-05 killed mid-generation, A-AUTH-06 expired-session refresh).
/// Runs as its own ui-suite shard so the whole suite fits the job timeout.
final class CoverageUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    @discardableResult
    func launch(_ extra: [String] = []) -> XCUIApplication {
        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch(); return app
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    /// The opened browse menu: the collection view containing the menu's own "Collections" section
    /// header (matched by label via predicate - XCUIT has no containing(_:label:) overload). That header
    /// is part of the menu definition (LibraryView.swift Section("Collections")) and appears nowhere else
    /// in the observed hierarchy, so this scopes queries to the open menu.
    var browseMenu: XCUIElement {
        app.collectionViews.containing(NSPredicate(format: "label == %@", "Collections")).firstMatch
    }
    /// Browse-menu item by exact label, scoped to the opened menu. Observed on the iOS 27 runtime
    /// (identical source resolves them on iOS 26): SwiftUI Menu item buttons no longer expose their
    /// accessibility identifiers (library.collection.* and friends) to XCUIT;
    /// the open menu renders them as labelled buttons, so identifier queries can never match there.
    /// Taps and destination assertions are unchanged. Menu-item identifier contract coverage is lost
    /// on this runtime. `icon` anchors duplicates structurally, not by element order: "Recently added"
    /// exists as both the Collections entry (icon clock.arrow.trianglehead.counterclockwise.rotate.90)
    /// and a Group by option (icon calendar), and the SF-symbol image identifiers still surface inside
    /// each button in the observed hierarchy.
    func browseMenuItem(_ label: String, icon: String? = nil) -> XCUIElement {
        let menu: XCUIElement
        if label == "Journal" || label == "Insights & journal" {
            // Target anchoring survives the native popup scrolling Collections away.
            let menus = app.collectionViews.containing(NSPredicate(format: "label == %@", label))
            wait(menus.firstMatch)
            XCTAssertEqual(menus.count, 1, "Explore menu must be unique")
            menu = menus.firstMatch
        } else {
            menu = browseMenu
        }
        var q = menu.descendants(matching: .button).matching(NSPredicate(format: "label == %@", label))
        if let icon = icon { q = q.containing(.image, identifier: icon) }
        return q.firstMatch
    }
    func wait(_ e: XCUIElement, _ t: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
    }
    /// Search both directions for lazy rows. Callers with a known section order can choose the first direction.
    func scrollTo(_ e: XCUIElement, max: Int = 25, searchDownFirst: Bool = true) {
        _ = e.waitForExistence(timeout: 2)
        var n = 0
        while !(e.exists && e.isHittable) && n < max {
            if searchDownFirst { app.swipeUp() } else { app.swipeDown() }
            n += 1
        }
        n = 0
        while !(e.exists && e.isHittable) && n < max * 2 {
            if searchDownFirst { app.swipeDown() } else { app.swipeUp() }
            n += 1
        }
    }
    func tab(_ name: String) {
        var n = 0
        while !app.tabBars.firstMatch.exists && n < 4 {
            let bar = app.buttons["backBar"].firstMatch, back = app.navigationBars.buttons.element(boundBy: 0)
            if bar.exists { bar.tap() } else if back.exists { back.tap() }
            sleep(1); n += 1
        }
        let b = app.tabBars.buttons[name]
        if name == "Journal" {
            XCTAssertTrue(b.waitForExistence(timeout: 5), "Journal must be selected through its tab, not a pushed-screen back button")
            let hittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"), object: b)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed,
                           "Journal tab must be hittable before its single tap")
            b.tap()
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "selected == true"), object: b)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                           "Journal tab tap must land before looking for Journal content")
            XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5),
                          "Selected Journal tab must show the Journal root before looking for its routes")
        } else if b.waitForExistence(timeout: 5) { b.tap() } else { app.buttons[name].firstMatch.tap() }
    }
    func startPrompt(_ s: String) {
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText(s)
        app.buttons["generateButton"].tap()
    }
    func addPrompt(_ s: String) {
        startPrompt(s)
        wait(text("Review your card"), 15)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
    }
    func replaceText(_ e: XCUIElement, _ newText: String) {
        wait(e); e.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if let v = e.value as? String, !v.isEmpty, v != e.placeholderValue {
            e.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        e.typeText(newText)
    }

    /// Caller-owned Settings surface: never resolve content against an underlying sheet
    /// or another tab. The retained iOS 27 hierarchy exposes Settings Form as a CollectionView.
    private func settingsContent() -> XCUIElement {
        let navigation = app.navigationBars["Settings"]
        XCTAssertTrue(navigation.exists && !navigation.frame.isEmpty && navigation.isHittable,
                      "Settings must be the active screen before querying its Form")
        let collections = app.windows.firstMatch.collectionViews
        XCTAssertEqual(collections.count, 1,
                       "Active Settings must expose exactly one content collection; never choose an arbitrary first match")
        let content = collections.element(boundBy: 0)
        XCTAssertTrue(content.exists && !content.frame.isEmpty,
                      "Settings Form must expose its content collection")
        return content
    }

    // MARK: covers

    func test31_CoverControlsHeroAndTile() {
        launch(["-qaNoPlayground"])
        startPrompt("Chakalaka")
        wait(text("Review your card"), 15)
        let hero = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(hero, 5)
        XCTAssertFalse(app.buttons["generateCover"].exists, "Generate must be hidden when Image Playground is unavailable")
        sleep(2) // initial cover resolution is async
        if app.buttons["removeCover"].exists { app.buttons["removeCover"].tap(); sleep(1) }
        wait(app.buttons["changeCover"], 3)
        shot("cover-review-tile")
        app.buttons["sampleCover"].tap()
        wait(app.buttons["removeCover"], 5)
        XCTAssertEqual(hero.value as? String, "photo")
        shot("cover-review-photo")
        app.buttons["removeCover"].tap()
        XCTAssertTrue(app.buttons["removeCover"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(hero.value as? String, "tile")
        shot("cover-review-removed")
        app.buttons["sampleCover"].tap()
        wait(app.buttons["removeCover"], 5)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        let detailHero = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(detailHero, 5)
        XCTAssertEqual(detailHero.value as? String, "photo")
        shot("cover-detail-hero")
        // A second recipe without a cover gets the branded tile.
        tab("Library")
        addPrompt("Plain rice")
        let tile = app.descendants(matching: .any)["recipeHero"].firstMatch
        wait(tile, 5)
        XCTAssertEqual(tile.value as? String, "tile")
        shot("cover-detail-branded-tile")
    }

    func test32b_GridFavouriteCanBeToggledDirectly() {
        launch()
        addPrompt("Miso salmon for two")
        tab("Library")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let favourite = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gridFavourite.")).firstMatch
        wait(favourite, 10)
        XCTAssertTrue(favourite.label.hasPrefix("Add "), "Unfavourited grid card should expose an Add to Favourites action")
        shot("library-grid-favourite-before")
        favourite.tap()
        XCTAssertTrue(favourite.waitForExistence(timeout: 3))
        XCTAssertTrue(favourite.label.hasPrefix("Remove "), "Favourite action label should update after toggling")
        shot("library-grid-favourite-after")
    }

    // MARK: Library discovery + Settings tools/About

    func test32c_ExpandableRecipeSheetOpensExpandsAndDismisses() {
        launch()
        addPrompt("Miso salmon for two")
        tab("Library")
        defer { XCUIDevice.shared.orientation = .portrait }

        let listCard = app.buttons["listCard"].firstMatch
        wait(listCard, 10)
        scrollTo(listCard)
        XCTAssertTrue(listCard.isHittable, "A Library list row must be visible before it is tapped")
        listCard.tap()
        XCTAssertTrue(app.exists, "App should remain running after tapping a Library list row")

        let title = app.staticTexts["recipeQuickLookTitle"]
        wait(title, 5)
        XCTAssertTrue(title.label.localizedCaseInsensitiveContains("Miso salmon"), "Preview must show the selected recipe")
        let expand = app.buttons["expandRecipeDetails"]
        wait(expand, 5)
        shot("recipe-sheet-compact-portrait")
        expand.tap()
        let servings = app.segmentedControls["servingsPicker"]
        wait(servings, 5)
        XCTAssertTrue(servings.isHittable, "Expanded recipe must expose actual detail content")
        servings.buttons["2×"].tap()
        let fully = app.buttons["recipeSheet.expandFully"]
        wait(fully, 3)
        fully.tap()
        let detailScroll = app.scrollViews["recipe.detail.scroll"]
        wait(detailScroll, 5)
        let steps = detailScroll.staticTexts["recipe.steps.heading"]
        // Overline text is exposed as uppercase STEPS. Use the stable identifier,
        // and scroll only the mounted detail rather than the sheet or Library.
        wait(steps, 5)
        for _ in 0..<5 where !steps.isHittable { detailScroll.swipeUp() }
        shot("recipe-sheet-expanded-steps-portrait")
        XCTAssertTrue(steps.exists && steps.isHittable, "Full recipe must allow scrolling to steps")
        app.buttons["recipeSheet.collapse"].tap()
        wait(expand, 3)
        XCTAssertTrue(title.exists, "Collapse must restore the compact preview")
        expand.tap()
        wait(servings, 5)
        // The preserved hierarchy must keep detail state, not reconstruct a new recipe view.
        // Scroll upward within the visible detail if expansion preserved a lower position.
        for _ in 0..<5 where !servings.isHittable { detailScroll.swipeDown() }
        XCTAssertTrue(servings.isHittable, "Retained detail must allow scrolling back to servings")
        XCTAssertTrue(servings.buttons["2×"].isSelected, "Collapsing and expanding must retain servings")
        app.buttons["recipeSheet.close"].tap()
        XCTAssertTrue(expand.waitForNonExistence(timeout: 3), "Close must dismiss the recipe sheet")
        wait(listCard, 5)
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected, "Dismissal must return to the original Library tab")
        shot("recipe-sheet-return-library-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let card = app.buttons["gridCard"].firstMatch
        wait(card, 10)
        scrollTo(card)
        XCTAssertTrue(card.isHittable, "A Library grid card must be visible before it is tapped")
        card.tap()
        XCTAssertTrue(app.exists, "App should remain running after tapping a Library grid card")
        wait(title, 5)
        XCTAssertTrue(title.label.localizedCaseInsensitiveContains("Miso salmon"), "Landscape preview must show the selected recipe")
        wait(expand, 3)
        expand.tap()
        wait(servings, 5)
        XCTAssertTrue(servings.isHittable, "Compact-height expansion must expose recipe details")
        XCTAssertFalse(app.buttons["recipeSheet.expandFully"].exists, "Landscape must expand directly to the supported large detent")
        shot("recipe-sheet-expanded-landscape")
        app.buttons["recipeSheet.collapse"].tap()
        wait(expand, 3)
        app.buttons["recipeSheet.close"].tap()
        XCTAssertTrue(expand.waitForNonExistence(timeout: 3))
        wait(card, 5)
        // iPhone landscape uses LandscapeSplitView's sidebar, not a TabBar.
        let librarySidebar = app.buttons["sidebar.Library"]
        XCTAssertTrue(librarySidebar.isSelected)
        let shoppingSidebar = app.buttons["sidebar.Shopping list"]
        wait(shoppingSidebar, 5)
        shoppingSidebar.tap()
        XCTAssertTrue(shoppingSidebar.isSelected)
        librarySidebar.tap()
        XCTAssertTrue(librarySidebar.isSelected)
        wait(card, 5)
        XCTAssertFalse(app.buttons["recipeSheet.close"].exists, "A dismissed sheet must not reappear after changing tabs")

    }

    func test32_MoreCollectionsToolsAbout() {
        launch()
        addPrompt("Miso salmon for two")
        tab("Library")
        app.buttons["libraryBrowseMenu"].tap()
        wait(browseMenuItem("Recently added", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"))
        XCTAssertTrue(browseMenuItem("Favourites").exists || browseMenuItem("Favorites").exists)
        shot("library-collections")
        browseMenuItem("Recently added", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90").tap()
        wait(app.tabBars.buttons["Library"], 5)
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected, "collection should open the Library tab")
        wait(text("Miso salmon"), 5)
        shot("collection-filtered-library")
        tab("Settings")
        let settings = settingsContent()
        let export = settings.buttons["settings.export"]; scrollTo(export); wait(export, 3)
        XCTAssertTrue(settings.buttons["settings.import"].exists)
        XCTAssertTrue(settings.buttons["settings.replayOnboarding"].exists)
        shot("settings-tools")
        // Check Settings before opening Export. Keep the exact identifiers and
        // original scroll/wait budgets, querying the Form's actual Switch elements.
        let timerSettings = settingsContent()
        let settingsStepAlerts = timerSettings.switches["toggle.Step-by-step alerts"].firstMatch
        let settingsQuietHours = timerSettings.switches["toggle.Quiet hours"].firstMatch

        // Settings uses lazily materialized rows: scroll to each toggle before asserting it exists.
        // Export is in Tools, below Timer notifications. Search toward the earlier section first,
        // retaining the opposite-direction fallback if the viewport differs.
        scrollTo(settingsQuietHours, searchDownFirst: false); wait(settingsQuietHours, 3)
        XCTAssertTrue(settingsQuietHours.isHittable, "Quiet hours toggle should be reachable in Timer notifications")
        scrollTo(settingsStepAlerts); wait(settingsStepAlerts, 3)
        XCTAssertTrue(settingsStepAlerts.isHittable, "Step-by-step alerts toggle should be reachable in Timer notifications")
        let about = timerSettings.staticTexts["aboutVersion"]; scrollTo(about); wait(about, 3)
        XCTAssertTrue(about.label.contains("(build "))
        // The SwiftUI combined container is not consistently hittable across simulator
        // runtimes, even when its child heading is visible. Scroll to the stable visible
        // heading so this journey cannot spend minutes swiping toward a non-hittable parent.
        // Read-only combined text does not need to accept taps. XCUITest can report
        // isHittable=false for these visible, selectable SwiftUI rows. Prove actual
        // viewport clearance instead of spending the existing swipe budget seeking
        // a tappable parent. Keep the same directional bounds and content assertions.
        func revealReadOnlySettingsRow(_ heading: XCUIElement) {
            func fullyVisible() -> Bool {
                guard heading.exists else { return false }
                let row = heading.frame
                let window = app.windows.firstMatch
                let navigation = app.navigationBars["Settings"]
                let tabs = app.tabBars.firstMatch
                // Chrome is a sibling of the Form, not a descendant of timerSettings.
                // This portrait journey requires the active Settings navigation and tab bar;
                // missing chrome must fail rather than silently widening the viewport.
                guard window.exists, navigation.exists, tabs.exists else { return false }
                let screen = window.frame
                let navFrame = navigation.frame
                let tabFrame = tabs.frame
                guard !screen.isEmpty, !navFrame.isEmpty, !tabFrame.isEmpty,
                      !screen.isInfinite, !navFrame.isInfinite, !tabFrame.isInfinite,
                      !screen.isNull, !navFrame.isNull, !tabFrame.isNull else { return false }
                let top = max(screen.minY, navFrame.maxY)
                var bottom = min(screen.maxY, tabFrame.minY)
                let accessory = app.descendants(matching: .any)["bottomAccessory"].firstMatch
                if accessory.exists {
                    let frame = accessory.frame
                    guard !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return false }
                    if frame.intersects(screen) { bottom = min(bottom, frame.minY) }
                }
                return !row.isEmpty && !row.isInfinite && !row.isNull
                    && row.minX >= screen.minX && row.maxX <= screen.maxX
                    && row.minY >= top && row.maxY <= bottom
            }
            var swipes = 0
            while !fullyVisible() && swipes < 25 { timerSettings.swipeUp(); swipes += 1 }
            swipes = 0
            while !fullyVisible() && swipes < 50 { timerSettings.swipeDown(); swipes += 1 }
            XCTAssertTrue(fullyVisible(), "Settings read-only row must clear the live Settings navigation, tab bar and bottom accessory")
        }
        let buildNotesHeading = timerSettings.staticTexts["aboutBuildNotesHeading"]
        revealReadOnlySettingsRow(buildNotesHeading); wait(buildNotesHeading, 3)
        let buildNotes = timerSettings.staticTexts["aboutBuildNotes"].firstMatch
        wait(buildNotes, 3)
        XCTAssertFalse(buildNotes.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "About should show generated build notes or an explicit fallback")
        let diagnosticsHeading = timerSettings.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "AI diagnostics")
        ).firstMatch
        revealReadOnlySettingsRow(diagnosticsHeading); wait(diagnosticsHeading, 3)
        let diagnostics = timerSettings.descendants(matching: .any)["aiDiagnostics"].firstMatch
        wait(diagnostics, 3)
        XCTAssertFalse(diagnostics.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "About must retain its AI diagnostics content")
        let transparency = timerSettings.descendants(matching: .any)["aiTransparency"].firstMatch
        revealReadOnlySettingsRow(transparency); wait(transparency, 3)
        shot("settings-about")

        // About is below Tools. Return toward the earlier Export row first,
        // rather than spending the full downward search at the bottom of Settings.
        // Keep the same bounded opposite-direction fallback and all export assertions.
        scrollTo(export, searchDownFirst: false)
        export.tap()
        shot("settings-export-immediately-after-tap")
        print("SETTINGS-EXPORT-IMMEDIATE-AFTER-TAP-AX-BEGIN")
        print(app.debugDescription)
        print("SETTINGS-EXPORT-IMMEDIATE-AFTER-TAP-AX-END")
        // Export opens is retained; dismissal is device-verified on build408.
        // Owner decision 2026-11-08: do not test simulator share-sheet dismissal.
        let exportActivity = app.otherElements["ActivityListView"]
        let readinessBudget: TimeInterval = 2
        let exportPresentedPredicate = NSPredicate { _, _ in
            exportActivity.exists && !exportActivity.frame.isEmpty
        }
        var exportIsPresented = exportPresentedPredicate.evaluate(with: nil)
        if !exportIsPresented && readinessBudget > 0 {
            let exportPresented = XCTNSPredicateExpectation(predicate: exportPresentedPredicate, object: nil)
            exportIsPresented = XCTWaiter.wait(for: [exportPresented], timeout: readinessBudget) == .completed
        }
        guard exportIsPresented else {
            XCTFail("Export ActivityListView must present")
            return
        }
        shot("more-export-sheet")
        print("SETTINGS-EXPORT-PRESENTATION-AX-BEGIN")
        print(app.debugDescription)
        print("SETTINGS-EXPORT-PRESENTATION-AX-END")
    }

    // MARK: photo dish step

    func test33_WhatDishIsThisSpread() {
        launch(["-qaSpreadPhoto"])
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        app.buttons["Image"].tap()
        app.buttons["sampleFoodPhoto"].tap()
        app.buttons["generateButton"].tap()
        wait(app.descendants(matching: .any)["photoDishQuestion"].firstMatch, 10)
        wait(text("What dish is this?"), 3)
        XCTAssertTrue(text("spread of several dishes").exists)
        shot("photo-what-dish-spread")
        app.buttons["mogodu"].tap()
        app.buttons["ujeqe"].tap()
        shot("photo-spread-picked")
        app.buttons["generateButton"].tap()
        wait(text("Review your card"), 15)
        wait(text("Mogodu"), 5)
        shot("photo-spread-review-first")
        // The "Saved 1 more card" toast is transient (2.6 s); the library check below is the real assertion.
        _ = text("Saved 1 more card").waitForExistence(timeout: 4)
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        tab("Library")
        wait(text("Ujeqe"), 5)
        wait(text("Mogodu"), 5)
        shot("photo-spread-library")
    }

    // MARK: sign-up

    func openSignUp() {
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        app.segmentedControls["authModePicker"].buttons["Create account"].tap()
    }

    func test34_SignUpStrengthMeterAndExistingEmail() {
        launch()
        openSignUp()
        replaceText(app.textFields["authEmail"], "new@example.com")
        let p = app.secureTextFields["authPassword"]
        replaceText(p, "abc")
        let meter = app.descendants(matching: .any)["passwordStrength"].firstMatch
        wait(meter, 5)
        let reason = app.staticTexts["authSubmitReason"]
        wait(reason, 5)
        XCTAssertFalse(app.buttons["authSubmit"].isEnabled, "weak password must disable Create account")
        XCTAssertFalse(reason.label.isEmpty)
        shot("signup-weak-password")
        replaceText(p, "Cooking2026")
        XCTAssertTrue(reason.waitForNonExistence(timeout: 5), "reason should clear for a valid password")
        XCTAssertTrue(app.buttons["authSubmit"].isEnabled)
        shot("signup-strong-password")
        replaceText(app.textFields["authEmail"], "exists@example.com")
        app.buttons["authSubmit"].tap()
        wait(app.buttons["existsSignIn"], 8)
        XCTAssertTrue(app.buttons["existsReset"].exists)
        wait(text("may already exist"), 3)
        shot("signup-existing-email")
        app.buttons["existsSignIn"].tap()
        XCTAssertTrue(app.segmentedControls["authModePicker"].buttons["Sign in"].isSelected)
    }

    func test34b_SignUpRateLimitedShowsMessage() {
        launch()
        openSignUp()
        replaceText(app.textFields["authEmail"], "ratelimit@example.com")
        replaceText(app.secureTextFields["authPassword"], "Cooking2026")
        app.buttons["authSubmit"].tap()
        let err = app.descendants(matching: .any)["authError"].firstMatch
        wait(err, 8)
        XCTAssertTrue(err.label.contains("Email limit"), "rate-limited sign-up must show a visible message, got: \(err.label)")
        shot("signup-rate-limited")
    }

    // MARK: Beta testing screen

    func test35_BetaScreenManualExportReset() {
        launch(["-qaCIResults"])
        tab("Settings")
        app.buttons["settings.betaTesting"].tap()
        wait(app.staticTexts["betaProgress"])
        wait(app.staticTexts["betaCISummary"], 3)
        XCTAssertTrue(app.staticTexts["betaCISummary"].label.contains("1/2"))
        shot("beta-screen")
        let before = passed()
        let row = app.descendants(matching: .any)["beta.A-SYNC-02"].firstMatch
        scrollTo(row); wait(row, 5)
        XCTAssertTrue(row.label.contains("CI"), row.label)
        let manual = app.descendants(matching: .any)["beta.A-AUTH-03"].firstMatch
        scrollTo(manual); manual.tap()
        wait(app.buttons["Pass"], 5)
        app.buttons["Pass"].tap()
        wait(text("pass"), 5)
        shot("beta-item-pass")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<6 { app.swipeDown() }
        wait(text("This build: \(before + 1)/"), 5)
        let item2 = app.descendants(matching: .any)["beta.A-AUTH-04"].firstMatch
        scrollTo(item2); item2.tap()
        wait(app.buttons["Fail"], 5); app.buttons["Fail"].tap()
        wait(text("fail"), 5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let export = app.buttons["Export results (JSON + Markdown)"]
        scrollTo(export); export.tap(); sleep(2)
        shot("beta-export-sheet")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        let reset = app.buttons["Reset this build's results"]
        scrollTo(reset); reset.tap()
        let confirm = app.buttons["Reset this build"].firstMatch
        wait(confirm, 5)
        XCTAssertTrue(text("Earlier-build history is kept.").exists)
        shot("beta-reset-current-build-confirmation")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(confirm.exists)
        reset.tap(); wait(confirm, 5); confirm.tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        wait(text("This build: 0/"), 5)
        shot("beta-reset")
    }

    /// Regression for the reported crash: destructive data clearing must not leave navigation
    /// state that crashes when Settings › Beta testing is opened afterward.
    func test35b_BetaOpensAfterLibraryClear() {
        launch()
        tab("Settings")
        let clear = app.buttons["Clear all"].firstMatch
        scrollTo(clear); wait(clear, 5); clear.tap()
        let confirm = app.buttons["Clear all"].firstMatch
        wait(confirm, 3); confirm.tap()
        wait(text("Library cleared"), 5)
        tab("Settings")
        let beta = app.buttons["settings.betaTesting"]
        wait(beta, 5); beta.tap()
        wait(app.staticTexts["betaProgress"], 8)
        XCTAssertTrue(app.navigationBars.staticTexts["Beta testing"].exists)
        shot("beta-after-library-clear")
    }

    /// Regression for the direct user journey: tapping Settings › Beta testing from a
    /// fresh launch must push the Beta page without terminating the app.
    func test35c_BetaOpensFromFreshSettingsScreen() {
        launch()
        tab("Settings")
        let beta = app.buttons["settings.betaTesting"]
        wait(beta, 5)
        beta.tap()
        wait(app.staticTexts["betaProgress"], 8)
        XCTAssertTrue(app.navigationBars.staticTexts["Beta testing"].exists)
        XCTAssertTrue(app.staticTexts["betaCISummary"].exists)
        XCTAssertEqual(app.staticTexts["betaCISummary"].label, "CI: no published evidence for this exact build")
        shot("beta-fresh-settings")
        shot("beta-ci-no-published-evidence")
    }

    /// Presentation fixtures do not prove a live network failure or signed-out account race.
    func test35d_BetaCINotLoadedAndUnknownAreNotNoEvidence() {
        launch(["-qaBetaCINotLoaded"])
        tab("Settings"); app.buttons["settings.betaTesting"].tap()
        let summary = app.staticTexts["betaCISummary"]
        wait(summary)
        XCTAssertEqual(summary.label, "CI: not loaded")
        XCTAssertFalse(summary.label.contains("no published evidence"))
        shot("beta-ci-not-loaded")
        app.terminate()
        launch(["-qaBetaCIRefreshFailure"])
        tab("Settings"); app.buttons["settings.betaTesting"].tap()
        wait(app.staticTexts["betaCIError"])
        XCTAssertEqual(app.staticTexts["betaCISummary"].label, "CI: status unknown")
        XCTAssertTrue(app.staticTexts["betaCIError"].label.contains("Simulated refresh failure"))
        shot("beta-ci-refresh-unknown")
    }

    func test35e_BetaLocalBuildExplainsUnverifiedVerdicts() {
        launch()
        tab("Settings"); app.buttons["settings.betaTesting"].tap()
        let notice = app.staticTexts["betaUnverifiedBuildNotice"]
        scrollTo(notice); wait(notice)
        XCTAssertTrue(notice.label.contains("no verifiable release identity"))
        XCTAssertTrue(notice.label.contains("not counted as current-build verification"))
        shot("beta-local-build-identity-notice")
    }

    func passed() -> Int {
        let l = app.staticTexts["betaProgress"].label   // "Pilot gate: 3/96 passed"
        return Int(l.components(separatedBy: ": ").last?.components(separatedBy: "/").first ?? "") ?? -1
    }

    // MARK: Pilot-gate simulator automation

    /// A-SHARE-05: backend errors show the ErrorRetryCard and leave the local library intact.
    func test36_BackendDownRetryCardLibraryIntact() {
        launch(["-qaBackendDown"])
        addPrompt("Keep this stew")        // first generation succeeds, every later one fails
        tab("Library")
        startPrompt("Second dish")
        wait(app.buttons["generateRetry"], 10)
        wait(text("isn't responding"), 3)
        shot("backend-down-retry-card")
        app.buttons["generateRetry"].tap()
        wait(app.buttons["generateRetry"], 10)
        // Failed input is intentionally retained by interactiveDismissDisabled.
        // Use the actual explicit discard route; a swipe leaves a blocking sheet
        // and the historical tab taps then had hit point (-1,-1).
        let cancel = app.buttons["addCancel"]
        wait(cancel); cancel.tap()
        let discard = app.buttons["Discard"]
        wait(discard); discard.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Discard must actually close Add before tab navigation")
        tab("Library")
        wait(text("Keep this stew"), 5)
        // Signed-in sync against a failing server keeps the library too.
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap(); wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "cook@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        sleep(2)
        shot("backend-down-sync")
        tab("Library")
        wait(text("Keep this stew"), 5)
        shot("backend-down-library-intact")
    }

    /// A-SHARE-05: publish outage offers retry or text sharing and preserves the local recipe.
    func test39_SharePublishOutageFallsBackToTextAndKeepsLibrary() {
        launch(["-qaSharePublishDown"])
        addPrompt("Keep this stew")
        app.buttons["Share recipe"].tap()
        wait(app.buttons["Share link"], 5)
        app.buttons["Share link"].tap()

        // The failure must be visible and actionable; don't hide the error behind an activity sheet.
        wait(text("Could not create a share link"), 5)
        wait(app.buttons["Try again"], 5)
        wait(app.buttons["Share as text"], 5)
        shot("share-publish-outage-fallback-alert")

        // Retry is expected to fail with this fixture; the user can still choose text sharing.
        app.buttons["Try again"].tap()
        wait(text("Could not create a share link"), 5)
        wait(app.buttons["Share as text"], 5)
        app.buttons["Share as text"].tap()

        let sheet = app.otherElements["ActivityListView"].firstMatch
        let opened = sheet.waitForExistence(timeout: 8)
            || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2)
        XCTAssertTrue(opened, "text fallback activity sheet")
        shot("share-publish-outage-text-fallback")

        app.swipeDown(velocity: .fast)
        tab("Library")
        wait(text("Keep this stew"), 5)
        shot("share-publish-outage-library-intact")
    }

    /// A-SYNC-04: a failed pull for a newly selected account must not erase the local library.
    func test40_AccountSwitchSyncFailurePreservesLocalLibrary() {
        launch(["-qaBackendDown"])
        addPrompt("Keep this stew")

        tab("Settings")
        wait(text("Account & sync"))
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "cook@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Sync failed"), 5)

        // Sign out while keeping local recipes, then sign in as a different account while
        // the sync endpoint remains unavailable. The failed pull must not clear the old copy.
        app.buttons["signOutButton"].tap()
        let keep = app.buttons["Sign out, keep recipes on this iPhone"]
        wait(keep, 5)
        keep.tap()
        wait(app.buttons["openSignIn"], 5)
        app.buttons["openSignIn"].tap()
        wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "other@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        // The failed pull may sign account B out before its account row is ever rendered.
        wait(text("Account switch couldn't be completed. Your previous library is safe on this iPhone. Reconnect and sign in again."), 5)

        // A failed account switch must not leave account B active over account A's local data.
        // The app should sign out safely and preserve the previous library for a later retry.
        wait(app.buttons["openSignIn"], 5)
        XCTAssertFalse(app.staticTexts["accountEmail"].exists,
                       "the new account must not remain active while the previous account's library is visible")

        tab("Library")
        wait(text("Keep this stew"), 5)
        shot("account-switch-sync-failure-library-preserved")
    }

    /// Issue #89: the first request fails transiently; Retry must submit a fresh request and recover.
    func test36b_RecipeGenerationRetryRecoversAfterTransientFailure() {
        launch(["-qaBackendFailOnce"])
        startPrompt("Retryable stew")
        wait(app.buttons["generateRetry"], 10)
        wait(text("isn't responding"), 3)
        shot("recipe-generation-retry-before")
        app.buttons["generateRetry"].tap()
        wait(text("Review your card"), 15)
        wait(text("Retryable stew"), 5)
        XCTAssertFalse(app.buttons["generateRetry"].exists, "successful retry must leave the error state")
        shot("recipe-generation-retry-recovered")
    }

    /// A-CREATE-05: kill the app mid-generation, relaunch → clear "interrupted, retry"; and an unsaved card is restored.
    func test37_KilledMidGenerationRecovers() {
        launch(["-qaPersistDraft", "-qaResetDraft", "-qaSlowGenerate"])
        startPrompt("Umngqusho")
        wait(text("Cooking up your card"), 5)
        sleep(2)
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("interrupted"), 8)
        wait(app.buttons["generateRetry"], 3)
        shot("generation-interrupted-retry")
        // Opening the retry UI must not consume the only persisted request. If the user
        // closes Ate before tapping Retry, the next launch must still recover the input.
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("interrupted"), 8)
        wait(app.buttons["generateRetry"], 3)
        shot("generation-interrupted-retry-survives-second-relaunch")

        // Retry must launch a fresh attempt using the recovered input, finish into review,
        // and clear the pending request without creating a library card before Save.
        app.buttons["generateRetry"].tap()
        wait(text("Review your card"), 15)
        XCTAssertTrue(app.buttons["saveRecipe"].exists, "successful retry must leave the interrupted state")
        XCTAssertEqual(app.buttons.matching(identifier: "saveRecipe").count, 1,
                       "one retry must produce one review/save action")
        app.terminate()
        // The successfully generated but unsaved card survives a kill.
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("Review your card"), 8)
        // The restored-card toast is transient and not consistently exposed as StaticText by
        // SwiftUI across simulator runtimes. The review state and Save action are the durable
        // evidence that the persisted unsaved draft was restored.
        wait(app.buttons["saveRecipe"], 5)
        shot("generation-draft-restored")
        app.buttons["saveRecipe"].tap()
        wait(app.buttons["Cook mode"], 10)
        app.terminate()
        launch(["-qaPersistDraft"])
        app.buttons["Add recipe"].tap()
        wait(text("Add a recipe"))
        // Retain final-relaunch evidence before the original negative query.
        shot("generation-after-save-relaunch-before-persistence-query")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "generation-after-save-relaunch-before-persistence-query-AX"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertFalse(text("Restored your unsaved card").exists, "saved draft must not come back")
    }

    /// A-AUTH-06: an expired access token is refreshed silently and sync still succeeds.
    func test38_ExpiredSessionRefreshes() {
        launch(["-qaExpireOnce"])
        addPrompt("Refresh me")
        tab("Settings"); wait(text("Account & sync"))
        app.buttons["openSignIn"].tap(); wait(app.staticTexts["authTitle"])
        replaceText(app.textFields["authEmail"], "cook@example.com")
        replaceText(app.secureTextFields["authPassword"], "password123")
        app.buttons["authSubmit"].tap()
        wait(app.staticTexts["accountEmail"], 8)
        wait(text("Synced"), 10)
        XCTAssertFalse(text("Your session expired").exists)
        shot("auth-expired-session-refreshed")
    }
}

/// Health insights MVP with mock Health data (`-qaMockHealth`). Extension so it runs in the CoverageUITests shard.
extension CoverageUITests {
    func openInsights(_ scenario: String) {
        launch(["-qaMockHealth", scenario, "-qaHealthRecipes"])
        tab("Journal")
        // Journal is the tab root; Insights & Cooking History is its one named route.
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub); hub.tap()
    }
    func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    /// Connects, checks title + prompts, returns suggestion titles, saves a journal entry.
    @discardableResult
    func runHealthScenario(_ scenario: String, title: String, save: Bool = false) -> [String] {
        openInsights(scenario)
        let connect = app.buttons["insights.connect"]; wait(connect)
        shot("journal-insights-hub-route")
        connect.tap()
        wait(text(title))
        let names = app.buttons.matching(identifier: "insights.suggestion").allElementsBoundByIndex.map(\.label)
        shot("insights-" + scenario)
        // The reflection composer now lives on the Journal root, not in the pushed hub.
        app.navigationBars["Insights & Cooking History"].buttons["Journal"].tap()
        let prompt = app.buttons["insights.prompt"].firstMatch; scrollTo(prompt)
        XCTAssertTrue(prompt.exists, "\(scenario): no journal prompt")
        if save {
            let field = any("insights.journalText"); scrollTo(field); field.tap(); field.typeText("Note for \(scenario)")
            let b = app.buttons["insights.save"]; scrollTo(b); b.tap()
            XCTAssertFalse(any("insights.tile.journal").exists, "Insights must not duplicate the Journal list")
            wait(app.staticTexts["Note for \(scenario)"].firstMatch)
            XCTAssertFalse(any("insights.journalingPicker").exists, "Picker must be hidden without the paid entitlement")
            wait(app.navigationBars["Journal"])
            let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Note for \(scenario)")).firstMatch
            wait(saved)
            saved.tap()
            wait(any("journal.detail.text"))
            XCTAssertTrue(any("journal.detail.text").label.contains("Note for \(scenario)"))
        }
        app.terminate()
        return names
    }
    func testInsightsRefreshControlRecalculatesVisibleInsights() {
        openInsights("recovery")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(text("Recovery day"))
        let refresh = app.buttons["insights.refresh"]
        wait(refresh); refresh.tap()
        wait(text("Recovery day"))
        XCTAssertTrue(any("insights.progress.result").exists,
                      "Recipe insight should remain rendered after a combined refresh")
        XCTAssertFalse(app.buttons["insights.progress.refresh"].exists,
                       "Refresh belongs to the Insights header, not an individual card")
    }
    func testHealthScenarioRecovery() { runHealthScenario("recovery", title: "Recovery day", save: true) }
    func testHealthScenarioLowEnergy() { runHealthScenario("lowEnergy", title: "Low-energy day", save: true) }
    func testHealthScenarioPerformance() { runHealthScenario("performance", title: "Good-energy day", save: true) }
    func testHealthScenarioUnderactive() { runHealthScenario("underactive", title: "Quiet week") }
    func testHealthSuggestionsDifferByState() {
        let a = runHealthScenario("recovery", title: "Recovery day")
        let b = runHealthScenario("underactive", title: "Quiet week")
        XCTAssertFalse(a.isEmpty, "Recovery should suggest meals"); XCTAssertFalse(b.isEmpty, "Underactive should suggest meals")
        XCTAssertNotEqual(a, b, "Recovery and underactive should rank meals differently")
    }
    func testHealthScenarioEmpty() {
        openInsights("empty")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.noData"))
    }
    func testHealthInsightsDeniedAndUnavailable() {
        openInsights("denied")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.denied"))
        app.terminate()
        openInsights("unavailable")
        wait(any("insights.unavailable"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
        app.terminate()
        openInsights("noEntitlement")
        wait(any("insights.entitlementMissing"))
        XCTAssertFalse(app.buttons["insights.connect"].exists)
    }
    func testHealthOpenRecipeSheetAndClose() {
        openInsights("recovery")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(text("Recovery day"))
        let sug = app.buttons["insights.suggestion"].firstMatch; scrollTo(sug); sug.tap()
        let done = app.buttons["recipeSheet.done"]; wait(done)
        shot("insights-recipe-sheet")
        // (1) A sheet has only Done: no custom or system "Recipes" back.
        XCTAssertFalse(app.buttons["backBar"].exists, "custom back bar inside the sheet")
        XCTAssertFalse(app.navigationBars.buttons["Recipes"].exists, "back to Recipes inside the sheet")
        XCTAssertFalse(app.buttons["Recipes"].exists, "back to Recipes inside the sheet")
        // (2) Content scrolls clear of Cook mode: the last card ends above the button.
        let cook = app.buttons["Cook mode"]; wait(cook)
        let ask = app.textFields["askField"]
        for _ in 0..<8 where !(ask.exists && ask.isHittable) { app.swipeUp() }
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(ask.isHittable, "last card reachable")
        XCTAssertLessThanOrEqual(ask.frame.maxY, cook.frame.minY + 1, "Cook mode covers the bottom of the content")
        done.tap()
        wait(text("Recovery day"))
        scrollTo(sug); sug.tap(); wait(done)
        app.navigationBars.firstMatch.swipeDown(velocity: .fast)   // swipe-to-dismiss also returns to Insights
        wait(text("Recovery day"))
        XCTAssertFalse(done.exists)
    }

    /// Bottom area is one system: Cook mode sits above the (single) timer bar, the Ask Ate field scrolls clear of both,
    /// and the offline banner lives at the top.
    func testBottomBarsDoNotOverlapRecipeDetail() {
        launch(["-simulateOffline"])
        addPrompt("miso salmon")
        app.buttons["Cook mode"].tap()
        wait(text("Step 1 of"))
        app.buttons["Next step"].tap(); app.buttons["Next step"].tap()
        app.buttons["Start timer"].tap()
        wait(app.buttons["Pause timer"], 5)
        app.buttons["Exit"].tap()
        let cook = app.buttons["Cook mode"]; wait(cook)
        let bar = app.buttons["timerBarOpen"].firstMatch
        let banner = app.descendants(matching: .any)["offlineBanner"].firstMatch
        wait(bar, 5); wait(banner, 5)
        shot("detail-bottom-bars")
        XCTAssertLessThan(banner.frame.midY, app.frame.midY, "offline banner belongs at the top")
        // C-FIX-03: the strip sits below the nav bar, never on top of it or the title.
        let nav = app.navigationBars.firstMatch
        if nav.exists { XCTAssertGreaterThanOrEqual(banner.frame.minY + 1, nav.frame.maxY, "offline banner overlaps the nav bar") }
        XCTAssertLessThanOrEqual(cook.frame.maxY, bar.frame.minY + 1, "Cook mode overlaps the timer bar")
        XCTAssertEqual(app.buttons.matching(identifier: "timerBarOpen").count, 1, "timer bar shown once")
        let ask = app.textFields["askField"]
        scrollTo(ask)
        XCTAssertTrue(ask.isHittable)
        XCTAssertFalse(ask.frame.intersects(cook.frame), "Ask Ate field under Cook mode")
        XCTAssertFalse(ask.frame.intersects(bar.frame), "Ask Ate field under the timer bar")
    }

    /// Gap 1: system Back from a recipe and the Beta screen never strands navigation.
    func testSystemBackFromRecipeNeverDead() {
        launch()
        addPrompt("miso salmon")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        wait(back); back.tap()
        wait(app.buttons["Add recipe"])
        XCTAssertFalse(app.buttons["Cook mode"].exists)
        tab("Settings")
        let beta = app.buttons["settings.betaTesting"]
        // Beta & diagnostics is below everyday Settings. Lazy Form rows are not
        // necessarily materialized at initial load; reveal before resolving.
        scrollTo(beta, max: 6)
        wait(beta)
        XCTAssertTrue(beta.isHittable)
        beta.tap()
        let back2 = app.navigationBars.buttons.element(boundBy: 0)
        wait(back2); back2.tap()
        wait(app.buttons["settings.betaTesting"])
    }
    /// Regression guard (StepTrackerTCA lesson): Connect must still ask for Health when access is undecided.
    func testHealthPermissionPromptAppearsWhenUndecided() {
        launch(["-qaMockHealth", "recovery", "-qaHealthRecipes", "-qaHealthPrompt"])
        tab("Journal")
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch; wait(hub); hub.tap()
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        let alert = app.alerts.firstMatch; wait(alert, 5)
        XCTAssertTrue(alert.label.contains("Health"), alert.label)
        alert.buttons["Allow"].tap()
        wait(text("Recovery day"))
    }
    func testHealthEmptyStateSampleDataAction() {
        openInsights("empty")
        let connect = app.buttons["insights.connect"]; wait(connect); connect.tap()
        wait(any("insights.noData"))
        let sample = app.buttons["insights.sampleData"]; wait(sample, 5); sample.tap()
        wait(text("Recovery day"))
    }
    /// Journaling Suggestions picker is never presented under UI tests; check the context row instead.
    func testJournalMomentContextRow() {
        launch(["-qaMockHealth", "recovery", "-qaJournalMomentEntry"])
        tab("Journal")
        let entry = app.descendants(matching: .any)["journal.entry"].firstMatch; wait(entry); entry.tap()
        let ctx = any("journal.detail.momentContext"); scrollTo(ctx); wait(ctx)
        XCTAssertTrue(ctx.label.contains("Dinner at Mama"), ctx.label)
        XCTAssertFalse(any("insights.journalingPicker").exists)
    }
}


extension CoverageUITests {
    func testCookingTrackerMonthNavigationAndSelectedDay() {
        launch(["-qaMockHealth", "empty", "-qaHealthRecipes"])
        tab("Journal")
        // Journal is the tab root; Insights & Cooking History is its one named route.
        let hub = app.descendants(matching: .any)["journal.insightsHistory"].firstMatch
        wait(hub); hub.tap()

        let insightsTitle = app.navigationBars["Insights & Cooking History"]
        wait(insightsTitle)
        // The hub is pushed above Journal, so its native Back button replaces root logo chrome.
        let journalBack = insightsTitle.buttons["Journal"]
        wait(journalBack)
        XCTAssertTrue(journalBack.isHittable, "The pushed tracker must retain its route back to Journal")
        let month = any("tracker.displayedMonth")
        scrollTo(month)
        wait(month)
        let currentMonth = month.label
        XCTAssertGreaterThanOrEqual(month.frame.minY, insightsTitle.frame.minY,
                                    "Tracker content must begin below the shared navigation header")
        app.swipeUp()
        XCTAssertTrue(insightsTitle.exists, "Tracker navigation header must remain present while scrolling")
        let previous = any("tracker.previousMonth")
        scrollTo(previous)
        wait(previous); previous.tap()
        XCTAssertNotEqual(month.label, currentMonth, "Previous month should update the calendar title")

        let next = any("tracker.nextMonth")
        wait(next); next.tap()
        XCTAssertEqual(month.label, currentMonth, "Next month should return to the current month")
        XCTAssertFalse(next.isEnabled, "Future months must not be selectable")

        let day = any("tracker.day.1")
        scrollTo(day); wait(day); day.tap()
        wait(app.navigationBars["Cooked that day"])
        XCTAssertTrue(text("Nothing recorded for this day.").exists,
                      "An unrecorded day should show the explicit empty state")
    }
}

extension CoverageUITests {
    /// Issue #68: root navigation chrome remains visible and large titles do not cover first content.
    func testNavigationHeadersRemainStableOnShoppingAndSettings() {
        launch()
        tab("Shopping")
        let shoppingTitle = app.navigationBars["Shopping list"]
        wait(shoppingTitle)
        wait(app.images["shopping.logo"])
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to buy")).firstMatch
        wait(count)
        XCTAssertGreaterThanOrEqual(count.frame.minY, shoppingTitle.frame.minY,
                                    "Shopping content must begin below the navigation title")
        app.swipeUp()
        XCTAssertTrue(shoppingTitle.exists, "The navigation bar must remain present while Shopping scrolls")

        tab("Settings")
        let settingsTitle = app.navigationBars["Settings"]
        wait(settingsTitle)
        wait(app.images["settings.logo"])
        app.swipeUp()
        XCTAssertTrue(settingsTitle.exists, "The navigation bar must remain present while Settings scrolls")

        // The native tab bar minimizes on scroll-down. Apple documents two ways
        // to expand it: tap its selected tab or scroll all the way to the top.
        // One reverse swipe is not that contract: final #529 pixels still show
        // Account & sync below the header and only the Settings/Search capsules.
        // Expand through the visible selected Settings tab exactly once, then
        // perform the existing single Journal navigation tap below.
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.isSelected,
                      "Settings must remain selected after its scroll")
        shot("82-settings-after-scroll-before-tab-reveal")
        XCTAssertTrue(settingsTab.isHittable, "The selected minimized Settings tab must be reachable")
        settingsTab.tap()
        shot("82-settings-tab-chrome-revealed")
        // #82 uses the current Journal root, not the historical Tracker title or
        // pushed Cooking History route. Keep every strict tab/arrival/header
        // assertion; the reveal gesture is setup, never a substitute destination.
        tab("Journal")
        let journalTitle = app.navigationBars["Journal"]
        wait(journalTitle)
        wait(app.images["journal.logo"])
        XCTAssertEqual(app.navigationBars.count, 1, "Journal must have one navigation header")
        let timeline = any("journal.timelineLink")
        wait(timeline)
        XCTAssertGreaterThanOrEqual(timeline.frame.minY, journalTitle.frame.minY,
                                    "Journal root content must begin below its shared navigation title")
        let addEntry = app.buttons["journal.newEntry"]
        wait(addEntry)
        XCTAssertTrue(addEntry.isHittable, "Journal New entry must be reachable initially")
        shot("82-journal-root-header-initial")
        app.swipeUp()
        XCTAssertTrue(journalTitle.exists, "Journal navigation header must remain present after scrolling")
        XCTAssertTrue(app.images["journal.logo"].exists, "Journal keeps the shared root logo after scrolling")
        XCTAssertEqual(app.navigationBars.count, 1, "Scrolling Journal must not introduce a duplicate header")
        XCTAssertTrue(addEntry.isHittable, "Journal New entry must stay reachable after scrolling")
        shot("82-journal-root-header-after-scroll")
    }
}
