import XCTest
@testable import Ate

/// Dedicated coverage for the Insights presentation work: quiet optional Health, unmistakable
/// sample data, and cooking-history insights that link back to the recipes behind them.
final class InsightsPresentationTests: XCTestCase {

    // MARK: Quiet Health presentation (audit: unavailable Health is a quiet optional setup)

    func testNotDeterminedOffersSingleQuietConnect() {
        let p = InsightsHealthPresentation.make(access: .notDetermined)
        XCTAssertEqual(p.prominence, .quietConnect)
        XCTAssertTrue(p.showsConnect)
        XCTAssertFalse(p.showsSettings)
        XCTAssertFalse(p.showsRetry)
    }

    func testDeniedIsQuietNoticeWithoutConnect() {
        let p = InsightsHealthPresentation.make(access: .denied)
        XCTAssertEqual(p.prominence, .quietNotice)
        XCTAssertFalse(p.showsConnect, "Connect belongs to the undecided state only; denied routes to Settings")
        XCTAssertTrue(p.showsSettings)
        XCTAssertTrue(p.showsRetry)
    }

    func testUnavailableAndMissingEntitlementNeverOfferConnect() {
        for access in [HealthAccess.unavailable, .entitlementMissing] {
            let p = InsightsHealthPresentation.make(access: access)
            XCTAssertEqual(p.prominence, .quietNotice, "\(access)")
            XCTAssertFalse(p.showsConnect, "\(access)")
            XCTAssertFalse(p.showsSettings, "\(access)")
            XCTAssertFalse(p.showsRetry, "\(access)")
        }
    }

    func testRequestedIsTheOnlyConnectedPresentation() {
        let p = InsightsHealthPresentation.make(access: .requested)
        XCTAssertEqual(p.prominence, .connected)
        XCTAssertFalse(p.showsConnect)
    }

    // MARK: Sample marking (audit: sample data can never be confused with personal data)

    func testEveryHealthDerivedTileRequiresSampleBadgeWhenSampling() {
        for tile in ["bodyToday", "suggestedMeals", "dailyReflection"] {
            XCTAssertTrue(InsightsSampleMarking.requiresSampleBadge(tileID: tile, isSample: true), tile)
        }
    }

    func testNoSampleBadgeWithoutSampleData() {
        for tile in InsightsSampleMarking.healthDerivedTileIDs {
            XCTAssertFalse(InsightsSampleMarking.requiresSampleBadge(tileID: tile, isSample: false), tile)
        }
    }

    func testNonHealthTilesNeverCarrySampleBadge() {
        for tile in ["tracker", "recipeProgress", "journal"] {
            XCTAssertFalse(InsightsSampleMarking.requiresSampleBadge(tileID: tile, isSample: true), tile)
        }
    }

    func testLibraryTodayCardIsMarkedWhenSampling() {
        XCTAssertTrue(InsightsSampleMarking.requiresSampleBadge(tileID: InsightsSampleMarking.libraryTodayCardID, isSample: true),
                      "Sample truth covers every surface that renders Health-derived content, including the Library Today card")
        XCTAssertFalse(InsightsSampleMarking.requiresSampleBadge(tileID: InsightsSampleMarking.libraryTodayCardID, isSample: false))
    }

    // MARK: Cooking history relates back to its recipes

    private func weekInput() -> RecipeProgressInsightInput {
        RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Lentil soup", "Greek salad"],
            recordedMealsThisWeek: 2,
            firstTimeRecipesThisWeek: 1,
            weekRecipeRefs: [RecipeReference(id: "r1", title: "Lentil soup"), RecipeReference(id: "r2", title: "Greek salad")],
            firstTimeRecipeRefs: [RecipeReference(id: "r2", title: "Greek salad")],
            mostCookedRecipeID: "r1"
        )
    }

    func testWeeklyCookingCandidateLinksItsRecipes() {
        let candidates = RecipeProgressInsightService.candidates(for: weekInput())
        let weekly = candidates.first { $0.id == "weekly-cooking" }
        XCTAssertEqual(weekly?.relatedRecipes,
                       [RecipeReference(id: "r1", title: "Lentil soup"), RecipeReference(id: "r2", title: "Greek salad")])
    }

    func testFirstTimeCandidateLinksNewRecipes() {
        let candidates = RecipeProgressInsightService.candidates(for: weekInput())
        let discovery = candidates.first { $0.id == "recipe-discovery" }
        XCTAssertEqual(discovery?.relatedRecipes, [RecipeReference(id: "r2", title: "Greek salad")])
    }

    func testCookingRhythmFallbackLinksMostCookedRecipe() {
        // No evidence-backed candidates: cooked history exists but no weekly/first-time/streak/shopping evidence.
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 2, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Lentil soup"],
            mostCookedRecipeID: "r1"
        )
        let candidates = RecipeProgressInsightService.candidates(for: input)
        let rhythm = candidates.first { $0.id == "cooking-rhythm" }
        XCTAssertEqual(rhythm?.relatedRecipes, [RecipeReference(id: "r1", title: "Lentil soup")])
    }

    func testRelatedRecipesNeverChangeEvidenceFingerprints() {
        let withRefs = weekInput()
        var withoutRefs = weekInput()
        withoutRefs.weekRecipeRefs = []
        withoutRefs.firstTimeRecipeRefs = []
        withoutRefs.mostCookedRecipeID = nil
        let a = RecipeProgressInsightService.candidates(for: withRefs)
        let b = RecipeProgressInsightService.candidates(for: withoutRefs)
        XCTAssertEqual(a.map(\.id), b.map(\.id), "Linking recipes must not add, remove or reorder insights")
        for (lhs, rhs) in zip(a, b) {
            XCTAssertEqual(lhs.evidenceFingerprint, rhs.evidenceFingerprint,
                           "\(lhs.id): linking recipes must not reset lifecycle state")
        }
    }

    // MARK: Input capture from cooking history

    func testMakeCapturesWeekAndFirstTimeReferences() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))! // Thursday
        func card(_ id: String, _ title: String) -> RecipeCard {
            var c = RecipeCard(); c.id = id; c.title = title; return c
        }
        let recipes = [card("r1", "Lentil soup"), card("r2", "Greek salad"), card("r3", "Beef potjie")]
        let history = CookingHistory(calendar: calendar,
                                     defaults: UserDefaults(suiteName: "InsightsPresentationTests.\(UUID().uuidString)")!)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let inWeek = calendar.date(byAdding: .day, value: 1, to: week.start)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: week.start)!
        // r1 cooked this week and last week; r2 cooked for the first time this week.
        let events: [String: Set<String>] = [
            history.key(for: inWeek): ["r1", "r2"],
            history.key(for: lastWeek): ["r1"]
        ]
        let input = RecipeProgressInsightInput.make(recipes: recipes, historyEvents: events,
                                                    calendar: calendar, now: now, history: history)
        XCTAssertEqual(input.mostCookedRecipeID, "r1")
        XCTAssertEqual(input.weekRecipeRefs, [RecipeReference(id: "r1", title: "Lentil soup"),
                                              RecipeReference(id: "r2", title: "Greek salad")])
        XCTAssertEqual(input.firstTimeRecipeRefs, [RecipeReference(id: "r2", title: "Greek salad")])
        XCTAssertEqual(input.recordedMealsThisWeek, 2)
        XCTAssertEqual(input.firstTimeRecipesThisWeek, 1)
    }

    func testRecipeReferencesSortMostCookedFirstThenTitle() {
        let refs = RecipeProgressInsightInput.recipeReferences(
            for: ["b", "a", "c"],
            counts: ["a": 3, "b": 1, "c": 3],
            titleByID: ["a": "Zulu bread", "b": "Mageu", "c": "Amasi cake"],
            limit: 3
        )
        XCTAssertEqual(refs, [RecipeReference(id: "c", title: "Amasi cake"),
                              RecipeReference(id: "a", title: "Zulu bread"),
                              RecipeReference(id: "b", title: "Mageu")])
    }

    func testRecipeReferencesTieBreakIdenticalTitlesOnID() {
        // Duplicate recipe titles are a real collection state; ordering must still be deterministic.
        let refs = RecipeProgressInsightInput.recipeReferences(
            for: ["b", "a"],
            counts: ["a": 2, "b": 2],
            titleByID: ["a": "Same title", "b": "Same title"],
            limit: 2
        )
        XCTAssertEqual(refs, [RecipeReference(id: "a", title: "Same title"),
                              RecipeReference(id: "b", title: "Same title")])
    }

    func testRecipeReferencesNegativeLimitReturnsEmpty() {
        let refs = RecipeProgressInsightInput.recipeReferences(
            for: ["r1"], counts: ["r1": 1], titleByID: ["r1": "One"], limit: -1
        )
        XCTAssertEqual(refs, [])
    }

    func testRecipeReferencesDropUnknownIDsAndRespectLimit() {
        let refs = RecipeProgressInsightInput.recipeReferences(
            for: ["gone", "r1", "r2", "r3", "r4"],
            counts: ["r1": 1, "r2": 1, "r3": 1, "r4": 1],
            titleByID: ["r1": "One", "r2": "Two", "r3": "Three", "r4": "Four"],
            limit: 2
        )
        XCTAssertEqual(refs, [RecipeReference(id: "r4", title: "Four"), RecipeReference(id: "r1", title: "One")])
    }
}
