import XCTest
@testable import Ate

final class HealthInsightTests: XCTestCase {
    func r(_ title: String, _ ings: [String], tags: [String] = [], mins: Int? = 40, servings: Int = 2) -> RecipeCard {
        var c = RecipeCard(); c.title = title; c.ingredients = ings.map { Ingredient(name: $0, quantity: 1, unit: "") }
        c.tags = tags; c.timeMinutes = mins; c.servings = servings; return c
    }
    var library: [RecipeCard] {
        [r("Grilled chicken bowl", ["chicken", "rice", "spinach"]),
         r("Lentil soup", ["lentils", "tomato", "onion"], mins: 25),
         r("Vetkoek", ["flour", "sugar", "oil"], tags: ["fried"]),
         r("Greek salad", ["cucumber", "tomato", "feta"], mins: 10),
         r("Overnight oats", ["oats", "banana", "yogurt"], servings: 4)]
    }

    func testEmptySummaryHasNoInsight() { XCTAssertNil(HealthInsightEngine.insight(for: HealthSummary(days: []))) }
    func testRecoveryAfterHardWorkout() {
        XCTAssertEqual(HealthInsightEngine.insight(for: MockHealthKitService.fixture("recovery"))?.state, .recovery)
    }
    func testLowEnergyAfterShortSleep() {
        XCTAssertEqual(HealthInsightEngine.insight(for: MockHealthKitService.fixture("lowEnergy"))?.state, .lowEnergy)
    }
    func testUnderactiveWeek() {
        XCTAssertEqual(HealthInsightEngine.insight(for: MockHealthKitService.fixture("underactive"))?.state, .underactive)
    }
    func testPerformanceWhenRestedAndActive() {
        XCTAssertEqual(HealthInsightEngine.insight(for: MockHealthKitService.fixture("performance"))?.state, .performance)
    }
    func testHeadlineMentionsSleepAndWorkout() {
        let h = HealthInsightEngine.insight(for: MockHealthKitService.fixture("recovery"))!.headline
        XCTAssertTrue(h.contains("6 hours")); XCTAssertTrue(h.hasPrefix("You slept 6 hours and ran for 55 minutes."), h)
    }
    func testRecoveryPrefersProtein() {
        let s = RecipeHealthMatcher.suggestions(for: .recovery, recipes: library)
        XCTAssertTrue(s.contains { $0.title == "Grilled chicken bowl" }); XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.first?.why, "Protein for recovery")
        XCTAssertFalse(s.contains { $0.title == "Vetkoek" })
    }
    func testUnderactiveAvoidsFried() {
        let s = RecipeHealthMatcher.suggestions(for: .underactive, recipes: library)
        XCTAssertFalse(s.contains { $0.title == "Vetkoek" }); XCTAssertTrue(s.contains { $0.title == "Greek salad" })
    }
    func testMatcherHandlesEmptyLibrary() { XCTAssertTrue(RecipeHealthMatcher.suggestions(for: .balanced, recipes: []).isEmpty) }
    func testTemplatePromptsPerState() {
        for st in HealthState.allCases {
            let p = JournalSuggestionService.templates(for: HealthInsight(state: st, reasons: [], headline: ""))
            XCTAssertTrue((1...2).contains(p.count)); XCTAssertTrue(p.allSatisfy { $0.text.hasSuffix("?") })
        }
    }
    @MainActor func testJournalStoreSavesLocally() {
        let j = JournalStore(inMemory: true)
        XCTAssertFalse(j.save(prompt: "p", text: "   ", state: .balanced, recipeIDs: []))
        XCTAssertTrue(j.save(prompt: "p", text: "Felt good", state: .recovery, recipeIDs: ["a"]))
        XCTAssertEqual(j.entries().first?.state, .recovery)
    }
    func testMockDeniedReturnsNoData() async {
        let m = MockHealthKitService(scenario: "denied")
        let a = await m.requestAccess(); XCTAssertEqual(a, .denied)
        let s = await m.summary(days: 7); XCTAssertFalse(s.hasAnyData)
    }
    func testJournalingPickerHiddenWithoutEntitlement() { XCTAssertFalse(JournalingSuggestionsGate.isAvailable) }
    func testBetaVisibilityHidesPassesAndResurfacesFailures() {
        var pass = BetaQA.Result(); pass.status = .pass
        var fail = BetaQA.Result(); fail.status = .fail
        let none = BetaQA.Result()
        XCTAssertTrue(BetaVisibility.isPassed(device: pass, ci: nil, build: "59"))
        XCTAssertFalse(BetaVisibility.isPassed(device: fail, ci: nil, build: "59"))
        XCTAssertFalse(BetaVisibility.isPassed(device: none, ci: nil, build: "59"))
        XCTAssertTrue(BetaVisibility.isPassed(device: none, ci: CIResult(status: .pass, note: "", build: "59", ts: ""), build: "59"))
        XCTAssertFalse(BetaVisibility.isPassed(device: none, ci: CIResult(status: .pass, note: "", build: "58", ts: ""), build: "59"), "CI pass must be for this build")
        XCTAssertFalse(BetaVisibility.isPassed(device: pass, ci: CIResult(status: .fail, note: "", build: "59", ts: ""), build: "59"), "A CI failure resurfaces the check")
    }
    func testChecklistIncludesHealthChecksFromSource() {
        let ids = BetaChecklist.tierA.map(\.id)
        XCTAssertTrue(ids.contains("A-HEALTH-01")); XCTAssertTrue(ids.contains("A-HEALTH-08"))
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate checklist IDs")
        XCTAssertTrue(BetaChecklist.tierA.contains { $0.category == "Apple Health insights" })
    }
    func testTierCChecklistHasPolishChecks() {
        let ids = BetaChecklist.tierC.map(\.id)
        for id in ["C-POL-01", "C-DES-07", "C-AX-04", "C-NAT-01", "C-NAT-13", "C-WID-01", "C-SIRI-04", "C-COV-03"] { XCTAssertTrue(ids.contains(id), id) }
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate Tier C IDs")
        XCTAssertTrue(Set(ids).isDisjoint(with: BetaChecklist.tierA.map(\.id)))
        XCTAssertTrue(BetaChecklist.tierC.allSatisfy { !$0.how.isEmpty }, "Every Tier C check needs an acceptance criterion")
    }

    // MARK: Recipe/progress insights (pure and deterministic; generated wording is never asserted)
    func testRecipeProgressInsightRequiresEnoughSavedOrCookingData() {
        let empty = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: [])
        let oneRecipe = RecipeProgressInsightInput(savedRecipeCount: 1, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: ["Soup"])
        XCTAssertFalse(empty.hasEnoughData)
        XCTAssertFalse(oneRecipe.hasEnoughData)
        XCTAssertNil(RecipeProgressInsightService.fallback(for: empty))
        XCTAssertNil(RecipeProgressInsightService.fallback(for: oneRecipe))
    }

    func testRecipeProgressInsightCollectionFallback() {
        let input = RecipeProgressInsightInput(savedRecipeCount: 3, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: ["Soup", "Salad", "Oats"])
        let result = RecipeProgressInsightService.fallback(for: input)
        XCTAssertEqual(result?.title, "Your recipe collection is taking shape")
        XCTAssertEqual(result?.generated, false)
        XCTAssertTrue(result?.evidence.contains("saved recipe collection") == true)
    }

    func testRecipeProgressInsightUsesRecordedCookingHistory() {
        let input = RecipeProgressInsightInput(savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 3, mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"])
        let result = RecipeProgressInsightService.fallback(for: input)
        XCTAssertEqual(result?.title, "Your cooking rhythm")
        XCTAssertEqual(result?.generated, false)
        XCTAssertTrue(result?.detail.contains("2 distinct saved recipes") == true)
        XCTAssertTrue(result?.detail.contains("Lentil soup") == true)
    }

    func testRecipeProgressInputUsesProvidedHistoryForStreak() throws {
        var soup = r("Lentil soup", ["lentils"])
        soup.id = "soup"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let suite = "progress-insight-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CookingHistory(calendar: calendar, defaults: defaults)
        let historyEvents = [
            history.key(for: yesterday): Set(["soup"]),
            history.key(for: now): Set(["soup"])
        ]

        let input = RecipeProgressInsightInput.make(
            recipes: [soup], historyEvents: historyEvents, calendar: calendar, now: now, history: history
        )
        XCTAssertEqual(input.currentStreak, 2)
        XCTAssertEqual(input.recordedMealsThisWeek, 2)
        XCTAssertEqual(input.firstTimeRecipesThisWeek, 1)
        XCTAssertTrue(RecipeProgressInsightService.candidates(for: input).contains { $0.id == "weekly-cooking" })
    }

    func testRecipeProgressInputIgnoresHistoryForRecipesOutsideLibrary() {
        var soup = r("Lentil soup", ["lentils"])
        soup.id = "soup"
        let input = RecipeProgressInsightInput.make(recipes: [soup], historyEvents: ["2026-10-20": ["unknown"]])
        XCTAssertEqual(input.cookedRecipeCount, 0)
        XCTAssertEqual(input.cookingDayCount, 0)
        XCTAssertNil(RecipeProgressInsightService.fallback(for: input))
    }

    func testRecipeProgressServiceFallsBackWhenModelIsDisabled() async {
        let input = RecipeProgressInsightInput(savedRecipeCount: 3, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: ["Soup", "Salad", "Oats"])
        let result = await RecipeProgressInsightService.insight(for: input, useModel: false)
        XCTAssertEqual(result?.generated, false)
        XCTAssertEqual(result?.title, "Your recipe collection is taking shape")
    }

    func testInsightsTileOrderPreservesKnownOrderAndAddsNewTiles() {
        XCTAssertEqual(InsightsTileOrder.resolve("journal,bodyToday,journal,unknown"),
                       ["journal", "bodyToday", "tracker", "recipeProgress", "suggestedMeals", "dailyReflection"])
    }

    func testInsightsTileOrderMovesTilesAndKeepsAllTiles() {
        let initial = InsightsTileOrder.defaults
        let moved = InsightsTileOrder.moving(initial, id: "journal", before: "tracker")
        XCTAssertEqual(moved.first, "journal")
        XCTAssertEqual(Set(moved), Set(initial))
        XCTAssertEqual(InsightsTileOrder.moving(initial, id: "journal", offset: -1), initial)
    }

    func testRecipeProgressInputFindsDuplicateTitlesConservatively() {
        var first = r("Lentil Soup", ["lentils"]); first.id = "one"
        var second = r(" lentil soup ", ["lentils", "tomato"]); second.id = "two"
        var third = r("Soup with lentils", ["lentils"]); third.id = "three"
        let input = RecipeProgressInsightInput.make(recipes: [first, second, third], historyEvents: [:])
        XCTAssertEqual(input.duplicateTitleGroups.count, 1)
        XCTAssertEqual(input.duplicateTitleGroups.first?.count, 2)
        XCTAssertEqual(RecipeProgressInsightService.fallback(for: input)?.title, "Possible overlapping recipe entries")
        XCTAssertTrue(RecipeProgressInsightService.fallback(for: input)?.detail.contains("review them") == true)
    }

    // MARK: JournalingMomentMapper (pure)
    func testMapperWorkoutBecomesRecoveryEntry() {
        let d = DateInterval(start: Date(timeIntervalSince1970: 1_791_000_000), duration: 1800)
        guard case let .journalEntry(p, t, date, st) = JournalingMomentMapper.map(title: "Morning Run", date: d, hasPhotos: false, isWorkout: true) else { return XCTFail() }
        XCTAssertEqual(t, "Morning Run"); XCTAssertEqual(date, d.start); XCTAssertEqual(st, .recovery); XCTAssertTrue(p.contains("Morning Run"))
    }
    func testMapperFoodPhotoBecomesRecipeDraft() {
        XCTAssertEqual(JournalingMomentMapper.map(title: "Sunday braai with family", date: nil, hasPhotos: true, isWorkout: false),
                       .recipeDraft(title: "Sunday braai with family", date: nil))
        let c = JournalingMomentMapper.draft(title: "Sunday braai", date: nil)
        XCTAssertEqual(c.source, .journalMoment); XCTAssertEqual(c.source.badge, "From a Journal moment")
    }
    func testMapperNonFoodOrNoPhotoBecomesEntry() {
        if case .recipeDraft = JournalingMomentMapper.map(title: "Dinner", date: nil, hasPhotos: false, isWorkout: false) { XCTFail("needs a photo") }
        if case .recipeDraft = JournalingMomentMapper.map(title: "Beach walk", date: nil, hasPhotos: true, isWorkout: false) { XCTFail("not food") }
        guard case let .journalEntry(_, t, _, _) = JournalingMomentMapper.map(title: "   ", date: nil, hasPhotos: false, isWorkout: false) else { return XCTFail() }
        XCTAssertEqual(t, "A moment")
    }
    func testMapperContextLine() {
        XCTAssertNil(JournalingMomentMapper.contextLine(title: nil, date: nil))
        XCTAssertEqual(JournalingMomentMapper.contextLine(title: "Dinner", date: nil), "From a Journal moment: Dinner")
    }
    func testJournalMomentSourceDecodesAndUnknownStaysSafe() throws {
        let d = try JSONDecoder().decode([RecipeSource].self, from: Data(#"["journalMoment","futureThing"]"#.utf8))
        XCTAssertEqual(d, [.journalMoment, .unknown])
    }
    @MainActor func testJournalStoreKeepsMomentProvenance() {
        let j = JournalStore(inMemory: true)
        XCTAssertTrue(j.save(prompt: "p", text: "t", state: .balanced, recipeIDs: [], momentTitle: "Dinner", momentDate: nil))
        XCTAssertEqual(j.entries().first?.source, .journalMoment); XCTAssertEqual(j.entries().first?.journalingSuggestionTitle, "Dinner")
    }
    @MainActor func testInsightsModelInjectsServiceAndLoadsOnce() async {
        let m = InsightsModel(health: MockHealthKitService(scenario: "recovery"))
        await m.connect(recipes: [])
        XCTAssertEqual(m.context?.insight.state, .recovery)
        await m.loadIfNeeded(recipes: []); XCTAssertTrue(m.loadedOnce)
    }
}
