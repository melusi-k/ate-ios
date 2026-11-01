import XCTest

/// HIG accessibility pass: XCUITest performAccessibilityAudit() on the main screens.
/// Hard-fails on missing labels, small hit regions, traits, Dynamic Type and clipped text at the default size;
/// contrast issues (pixel-sampled, noisy over photos/gradients) and the AX5 sweep are attached for review.
final class AccessibilityAuditUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() { continueAfterFailure = true; XCUIDevice.shared.orientation = .portrait }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch()
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }

    func audit(_ screen: String, strict: Bool = true) throws {
        var log: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let who = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' [\($0.identifier)]" } ?? "system element"
            log.append("\(issue.auditType.rawValue) · \(issue.compactDescription) · \(who)")
            if issue.element == nil { return true }                   // system chrome (status bar, keyboard) is not ours
            if issue.auditType == .contrast { return true }           // recorded below; brand pairs are unit-tested (AccessibilityTests)
            if issue.element?.identifier == "qa.probe" { return true } // invisible test probe
            return !strict
        }
        let a = XCTAttachment(string: log.isEmpty ? "no issues" : log.joined(separator: "\n"))
        a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways; add(a)
    }

    func addRecipe() {
        app.buttons["Add recipe"].tap()
        app.buttons["Prompt"].tap()
        let e = app.textViews["promptEditor"]; e.tap(); e.typeText("miso salmon")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 15))
        app.buttons["saveRecipe"].tap()
        XCTAssertTrue(app.buttons["Cook mode"].waitForExistence(timeout: 10))
    }

    func testAuditMainScreens() throws {
        launch()
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        try audit("library-empty")
        addRecipe()
        try audit("recipe-detail")
        app.buttons["Cook mode"].tap()
        XCTAssertTrue(text("Step 1 of").waitForExistence(timeout: 5))
        try audit("cook-mode")
        app.buttons["Exit"].tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try audit("library")
        for tab in ["Shopping", "More", "Settings"] {
            app.tabBars.buttons[tab].tap(); sleep(1)
            try audit(tab.lowercased())
        }
    }

    func testAuditOnboarding() throws {
        launch(["-showOnboarding"])
        let dots = app.descendants(matching: .any)["onboardingDots"]
        if dots.waitForExistence(timeout: 5) {
            XCTAssertTrue((dots.value as? String)?.contains("of") == true, "page dots announce 'x of y'")
            try audit("onboarding")
        }
    }

    /// Reveal a Settings form entry before tapping it. The previous up-only loop could push
    /// the Nutrition section above the fold; SwiftUI then dematerialises its cells and the
    /// entry vanishes from the hierarchy (CI failure on #241). Reset to the top first, then
    /// scroll against the measured frame until the entry's centre is inside the visible band.
    /// Returns true only when the measured centre sits inside the band and the entry is
    /// hittable - callers assert before tapping, so exhaustion fails loudly instead of
    /// tapping stale coordinates.
    @discardableResult
    private func revealSettingsEntry(_ entry: XCUIElement) -> Bool {
        // Measured from the on-screen navigation bar when present; 120pt fallback matches
        // the pinned CI simulator (402x874).
        let navBar = app.navigationBars.firstMatch
        let topBound: CGFloat = (navBar.exists && !navBar.frame.isEmpty) ? navBar.frame.maxY + 4 : 120
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        var attempts = 0
        while attempts < 12 {
            attempts += 1
            guard entry.exists, !entry.frame.isEmpty else {
                app.swipeUp(velocity: .slow)
                continue
            }
            let frame = entry.frame
            let bottomBound = bottomClearBound(app)
            if frame.midY >= topBound && frame.midY <= bottomBound {
                if entry.isHittable { return true }
                app.swipeDown(velocity: .slow)
            } else if frame.midY > bottomBound {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
        guard entry.exists, !entry.frame.isEmpty, entry.isHittable else { return false }
        let finalFrame = entry.frame
        let bottomBound = bottomClearBound(app)
        return finalFrame.midY >= topBound && finalFrame.midY <= bottomBound
    }

    /// Bottom edge of the reveal band, measured from the chrome actually on screen
    /// (floating tab bar, and the Add accessory at tab roots) rather than a fixed offset.
    private func bottomClearBound(_ app: XCUIApplication) -> CGFloat {
        var bound = app.windows.firstMatch.frame.maxY - 4
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && !tabBar.frame.isEmpty && tabBar.isHittable { bound = min(bound, tabBar.frame.minY - 4) }
        let accessory = app.buttons["accessoryAdd"]
        if accessory.exists && !accessory.frame.isEmpty && accessory.isHittable { bound = min(bound, accessory.frame.minY - 4) }
        // Pushed-screen bottom chrome (cook mini-player / timer bar) is a safe-area inset
        // the List/Form measurably ignores, so it overlays rows: the clear band must end
        // above the measured chrome frame, not above an estimated padding (#179).
        let miniPlayer = app.buttons["cookSessionMiniPlayer"]
        if miniPlayer.exists && !miniPlayer.frame.isEmpty { bound = min(bound, miniPlayer.frame.minY - 4) }
        let timerBar = app.descendants(matching: .any)["timerBar"]
        if timerBar.exists && !timerBar.frame.isEmpty { bound = min(bound, timerBar.frame.minY - 4) }
        return bound
    }

    /// #179: the nutrition diary and goals screens must actually be reached and audited -
    /// absent navigation fails the test instead of silently skipping the audit.
    /// Targeted same-element cross-size captures for the three elements the strict audit
    /// flags as "Dynamic Type partially unsupported" (#179): the diary configure-goals row,
    /// the goals clear-all hint and the goals Cancel button. performAccessibilityAudit
    /// reports the failing category, not the failing size step, so measure each element's
    /// rendered pixels at five fixed steps between XS and AX5 before changing app code.
    /// Diagnostic only: verdicts stay with the strict audit; this test adds pixel evidence.
    func testNutritionFontScalingCaptures() throws {
        let sizes: [(String, String)] = [
            ("XS", "UICTContentSizeCategoryXS"),
            ("XXXL", "UICTContentSizeCategoryXXXL"),
            ("AX1", "UICTContentSizeCategoryAccessibilityM"),
            ("AX3", "UICTContentSizeCategoryAccessibilityL"),
            ("AX5", "UICTContentSizeCategoryAccessibilityXXXL"),
        ]
        for (label, category) in sizes {
            launch(["-UIPreferredContentSizeCategoryName", category, "-resetNutritionDiary", "-resetNutritionGoals"])
            XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
            app.tabBars.buttons["Settings"].tap()
            let diaryEntry = app.buttons["settings.nutritionDiary"]
            XCTAssertTrue(revealSettingsEntry(diaryEntry), "Settings should reveal Food diary at \(label)")
            diaryEntry.tap()
            XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10))
            captureElementAX5(text("Set optional daily goals"), "scale-\(label)-goals-row")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let goalsEntry = app.buttons["settings.nutritionGoals"]
            XCTAssertTrue(revealSettingsEntry(goalsEntry), "Settings should reveal Nutrition goals at \(label)")
            goalsEntry.tap()
            XCTAssertTrue(app.navigationBars["Nutrition goals"].waitForExistence(timeout: 10))
            captureElementAX5(app.buttons["nutritionGoals.cancel"], "scale-\(label)-goals-cancel")
            captureElementAX5(app.staticTexts["nutritionGoals.clearAllHint"], "scale-\(label)-clear-all-hint")
            app.terminate()
        }
    }

    func testAuditNutritionScreens() throws {
        launch(["-resetNutritionDiary", "-resetNutritionGoals"])
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()

        // Reveal-driven existence: the nutrition rows sit below the fold and SwiftUI
        // dematerialises their cells, so a hard existence wait before revealing can never
        // pass on that state (CI: goals row absent at 46% scroll after Back, #179).
        // revealSettingsEntry scrolls while the row is absent; reaching it proves presence.
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        XCTAssertTrue(revealSettingsEntry(diaryEntry), "Settings must expose the Food diary entry inside the visible band")
        diaryEntry.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10), "Food diary screen must open before auditing")
        try audit("nutrition-diary")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let goalsEntry = app.buttons["settings.nutritionGoals"]
        XCTAssertTrue(revealSettingsEntry(goalsEntry), "Settings must expose the Nutrition goals entry inside the visible band")
        goalsEntry.tap()
        XCTAssertTrue(app.navigationBars["Nutrition goals"].waitForExistence(timeout: 10), "Nutrition goals screen must open before auditing")
        try audit("nutrition-goals")
    }

    /// Bounded scrolling captures of an element taller than the clear band. Every capture
    /// is labeled partial: no single one proves full containment, readability or
    /// reachability. Stops when the element's frame stops moving (bottom reached) or after
    /// 4 segments.
    private func partialCapture(_ el: XCUIElement, _ name: String) {
        var lastFrame = el.frame
        for segment in 1...4 {
            guard el.exists, !el.frame.isEmpty else { break }
            let shot = XCTAttachment(screenshot: el.screenshot())
            shot.name = "\(name)-partial-\(segment)"
            shot.lifetime = .keepAlways
            add(shot)
            app.swipeUp(velocity: .slow)
            let f = el.frame
            if f.isEmpty || f == lastFrame { break }
            lastFrame = f
        }
    }

    /// Same-element AX5 captures for cross-size measurement: the strict audit already
    /// attaches element screenshots at the default size; these pair with them so a DT
    /// verdict can be measured as rendered pixels at multiple sizes (main review, #179).
    /// The element is scrolled into the clear band first; a miss is attached as text,
    /// never silently skipped.
    private func captureElementAX5(_ query: XCUIElement, _ name: String, isChrome: Bool = false) {
        let el = query.firstMatch
        var ok = false
        var attempts = 0
        while attempts < 12 {
            if !el.exists { app.swipeUp(velocity: .slow); attempts += 1; continue }
            let f = el.frame
            if isChrome {
                // Chrome elements (the mini-player capsule itself) live at the screen edge;
                // the clear band deliberately ends above them, so only existence + a real
                // frame apply (main review, #179). This capture shows the chrome's own
                // rendering; it does NOT prove unobstructed content beneath it - that is
                // what the chrome-aware clear band checks for content captures.
                ok = !f.isEmpty; break
            }
            let navBar = app.navigationBars.firstMatch
            let top: CGFloat = (navBar.exists && !navBar.frame.isEmpty) ? navBar.frame.maxY : 120
            let bottom = bottomClearBound(app)
            if f.isEmpty { app.swipeUp(velocity: .slow); attempts += 1; continue }
            if f.height >= bottom - top {
                // Taller than the clear band: spanning the band proves only PARTIAL
                // visibility, never full containment/readability/reachability. Label the
                // capture partial and verify the remaining content with bounded scrolling
                // captures below (large empty-state at AX5, main review #179).
                if f.minY <= top + 8 && f.maxY >= bottom - 8 { partialCapture(el, name); return }
                app.swipeUp(velocity: .slow); attempts += 1; continue
            }
            // Validate the ENTIRE frame, not midY: a centred check passed while the capsule
            // covered the lower half of the goals Cancel row (v5 capture, #179).
            if f.minY > top && f.maxY < bottom { ok = true; break }
            // Scroll TOWARD the element: the previous capture may have scrolled the list
            // past it, and repeating one direction then guarantees a miss (CI: goals-row
            // sat above the band while the loop kept swiping up, #179).
            if f.midY <= top { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            attempts += 1
        }
        if ok && el.exists {
            let s = XCTAttachment(screenshot: el.screenshot()); s.name = name; s.lifetime = .keepAlways; add(s)
        } else {
            let t = XCTAttachment(string: name + ": element not reachable in the clear band at AX5")
            t.name = name + "-MISS"; t.lifetime = .keepAlways; add(t)
            // Required reach/capture: without a hard failure a green sweep could once
            // again mean missing evidence (main review, #179).
            XCTFail("Required AX5 cross-size capture missed: \(name)")
        }
    }

    /// AX5 sweep: largest accessibility text size. Recorded (not gating yet) so clipping can be tracked per build.
    func testAuditLargestDynamicType() throws {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-resetNutritionDiary", "-resetNutritionGoals"])
        XCTAssertTrue(text("Your Kitchen").waitForExistence(timeout: 10))
        try audit("ax5-library", strict: false)
        addRecipe()
        try audit("ax5-recipe-detail", strict: false)
        let s = XCTAttachment(screenshot: app.screenshot()); s.name = "ax5-recipe-detail"; s.lifetime = .keepAlways; add(s)
        app.buttons["Cook mode"].tap()
        try audit("ax5-cook-mode", strict: false)
        let c = XCTAttachment(screenshot: app.screenshot()); c.name = "ax5-cook"; c.lifetime = .keepAlways; add(c)

        // Evidence-only sweep of the nutrition screens at AX5 (non-gating): captures whether
        // the flagged diary/goals texts clip or stop scaling at the largest size (#179).
        let exitCook = app.buttons["Exit"]
        if exitCook.waitForExistence(timeout: 5) { exitCook.tap() }
        let settingsTab = app.tabBars.buttons["Settings"]
        if !settingsTab.waitForExistence(timeout: 2) {
            // Recipe detail hides the tab bar (.toolbar(.hidden, for: .tabBar)); step back
            // to the tab root before looking for the Settings tab (CI: sweep silently
            // skipped when the tab bar never existed after exiting Cook mode, #179).
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        // The sweep must actually reach and capture both screens: a silent skip here
        // reads as a green pass while collecting nothing (CI: the sweep passed for the
        // whole v2 run while never leaving recipe detail, #179).
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should be reachable for the AX5 nutrition sweep")
        settingsTab.tap()
        let diaryEntry = app.buttons["settings.nutritionDiary"]
        XCTAssertTrue(revealSettingsEntry(diaryEntry), "Settings should reveal Food diary for the AX5 sweep")
        diaryEntry.tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 10), "Food diary should open for the AX5 sweep")
        try audit("ax5-nutrition-diary", strict: false)
        let d = XCTAttachment(screenshot: app.screenshot()); d.name = "ax5-nutrition-diary"; d.lifetime = .keepAlways; add(d)
        captureElementAX5(app.descendants(matching: .any)["nutritionDiary.empty"], "ax5-elem-diary-empty")
        captureElementAX5(text("Set optional daily goals"), "ax5-elem-goals-row")
        captureElementAX5(app.buttons["cookSessionMiniPlayer"], "ax5-elem-mini-player", isChrome: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let goalsEntry = app.buttons["settings.nutritionGoals"]
        XCTAssertTrue(revealSettingsEntry(goalsEntry), "Settings should reveal Nutrition goals for the AX5 sweep")
        goalsEntry.tap()
        XCTAssertTrue(app.navigationBars["Nutrition goals"].waitForExistence(timeout: 10), "Nutrition goals should open for the AX5 sweep")
        try audit("ax5-nutrition-goals", strict: false)
        let g = XCTAttachment(screenshot: app.screenshot()); g.name = "ax5-nutrition-goals"; g.lifetime = .keepAlways; add(g)
        captureElementAX5(app.buttons["nutritionGoals.cancel"], "ax5-elem-goals-cancel")
        captureElementAX5(app.staticTexts["nutritionGoals.clearAllHint"], "ax5-elem-clear-all-hint")
    }
}
