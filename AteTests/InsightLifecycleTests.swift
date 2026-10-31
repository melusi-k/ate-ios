import XCTest
@testable import Ate

final class InsightLifecycleTests: XCTestCase {
    private func makeStore() -> (InsightLifecycleStore, UserDefaults, String) {
        let suite = "insight-lifecycle-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (InsightLifecycleStore(defaults: defaults), defaults, suite)
    }

    func testNewEvidenceIsEligibleAndUnchangedEvidenceIsNotReactivatedAfterSeen() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc"))
        store.markSeen("recipe-progress")
        XCTAssertFalse(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc"))
        XCTAssertEqual(store.record(for: "recipe-progress")?.status, .seen)
    }

    func testMeaningfulEvidenceChangeCreatesANewActiveVersion() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc"))
        store.dismiss("recipe-progress")
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "def"))
        XCTAssertEqual(store.record(for: "recipe-progress")?.status, .active)
        XCTAssertEqual(store.record(for: "recipe-progress")?.evidenceFingerprint, "def")
    }

    func testSnoozedInsightReturnsAfterItsDeadline() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc", now: now))
        store.snooze("recipe-progress", until: now.addingTimeInterval(3600), now: now)
        XCTAssertFalse(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc", now: now.addingTimeInterval(1800)))
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc", now: now.addingTimeInterval(3601)))
        XCTAssertEqual(store.record(for: "recipe-progress")?.status, .active)
    }

    func testDismissedResolvedAndExpiredInsightsStaySuppressedUntilEvidenceChanges() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        for (id, transition) in [
            ("dismissed", { store.dismiss("dismissed") }),
            ("resolved", { store.resolve("resolved") }),
            ("expired", { store.expire("expired") })
        ] as [(String, () -> Void)] {
            XCTAssertTrue(store.shouldPresent(id: id, evidenceFingerprint: "same"))
            transition()
            XCTAssertFalse(store.shouldPresent(id: id, evidenceFingerprint: "same"))
        }
    }

    func testRecipeFingerprintIgnoresTitleOrderingAndCaseButChangesWithEvidence() {
        let first = RecipeProgressInsightInput(
            savedRecipeCount: 3, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil Soup", recipeTitles: ["Soup", "Salad"]
        )
        let reordered = RecipeProgressInsightInput(
            savedRecipeCount: 3, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "lentil soup", recipeTitles: ["salad", "soup"]
        )
        var changed = first
        changed.recordedMealsThisWeek = 1

        XCTAssertEqual(RecipeProgressInsightFingerprint.make(first), RecipeProgressInsightFingerprint.make(reordered))
        XCTAssertNotEqual(RecipeProgressInsightFingerprint.make(first), RecipeProgressInsightFingerprint.make(changed))
    }

    func testInvalidCandidateCannotBePresented() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(store.shouldPresent(id: "", evidenceFingerprint: "abc"))
        XCTAssertFalse(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: ""))
    }

    func testLifecyclePersistsAcrossStoreInstances() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc"))
        store.dismiss("recipe-progress")

        let reloaded = InsightLifecycleStore(defaults: defaults)
        XCTAssertFalse(reloaded.shouldPresent(id: "recipe-progress", evidenceFingerprint: "abc"))
        XCTAssertEqual(reloaded.record(for: "recipe-progress")?.status, .dismissed)
    }

    func testLifecycleIsIsolatedByAccount() {
        let suite = "insight-account-scope-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = InsightLifecycleStore(defaults: defaults, accountID: "account-a")
        let accountB = InsightLifecycleStore(defaults: defaults, accountID: "account-b")

        XCTAssertTrue(accountA.shouldPresent(id: "recipe-progress", evidenceFingerprint: "same"))
        XCTAssertTrue(accountA.markSeen(id: "recipe-progress", evidenceFingerprint: "same"))
        XCTAssertFalse(accountA.shouldPresent(id: "recipe-progress", evidenceFingerprint: "same"))
        XCTAssertTrue(accountB.shouldPresent(id: "recipe-progress", evidenceFingerprint: "same"))
    }

    func testStaleActionCannotMarkNewEvidenceVersionAsSeen() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "current"))
        XCTAssertFalse(store.markSeen(id: "recipe-progress", evidenceFingerprint: "stale"))
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "current"))
    }

    func testClearAllRemovesAccountScopedLifecycleMetadata() {
        let suite = "insight-clear-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InsightLifecycleStore(defaults: defaults, accountID: "account-a")
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: "same"))
        InsightLifecycleStore.clearAll(defaults: defaults)
        let reloaded = InsightLifecycleStore(defaults: defaults, accountID: "account-a")
        XCTAssertTrue(reloaded.shouldPresent(id: "recipe-progress", evidenceFingerprint: "same"))
    }

    func testRecipeProgressServiceSuppressesAnInsightAfterItHasBeenActedOn() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 3, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Lentil soup", "Salad", "Oats"]
        )

        let fingerprint = RecipeProgressInsightFingerprint.make(input)
        let first = await RecipeProgressInsightService.insight(for: input, useModel: false)
        XCTAssertNotNil(first)
        XCTAssertTrue(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: fingerprint))
        XCTAssertTrue(store.markSeen(id: "recipe-progress", evidenceFingerprint: fingerprint))
        XCTAssertFalse(store.shouldPresent(id: "recipe-progress", evidenceFingerprint: fingerprint))
    }

    func testCandidateEngineRanksDuplicateDataAheadOfBehaviouralInsights() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 6, cookedRecipeCount: 3, cookingDayCount: 3,
            mostCookedRecipe: "Lentil soup",
            recipeTitles: ["Soup", "Salad"],
            duplicateTitleGroups: [["Soup", "soup"]],
            recordedMealsThisWeek: 3,
            firstTimeRecipesThisWeek: 1,
            currentStreak: 3
        )

        let candidates = InsightCandidateEngine.candidates(for: input)
        XCTAssertEqual(candidates.first?.id, "recipe-duplicates")
        XCTAssertEqual(candidates.count, InsightCandidateEngine.maximumCandidates)
        XCTAssertEqual(candidates.map(\.priority), candidates.map(\.priority).sorted(by: >))
    }

    func testCandidateEngineProducesStableCandidateFingerprints() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup",
            recipeTitles: ["Soup", "Salad"],
            recordedMealsThisWeek: 2,
            firstTimeRecipesThisWeek: 1
        )

        let first = InsightCandidateEngine.candidates(for: input)
        let second = InsightCandidateEngine.candidates(for: input)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertTrue(first.allSatisfy { !$0.evidenceFingerprint.isEmpty })
    }

    func testCandidateEngineReturnsNoInsightWithoutSufficientEvidence() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 2, cookedRecipeCount: 0, cookingDayCount: 0,
            mostCookedRecipe: nil, recipeTitles: []
        )

        XCTAssertTrue(InsightCandidateEngine.candidates(for: input).isEmpty)
    }

    func testCandidateFingerprintChangesWhenItsEvidenceChanges() {
        var input = RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup",
            recipeTitles: ["Soup", "Salad"],
            recordedMealsThisWeek: 2
        )
        let before = InsightCandidateEngine.candidates(for: input).first?.evidenceFingerprint
        input.recordedMealsThisWeek = 3
        let after = InsightCandidateEngine.candidates(for: input).first?.evidenceFingerprint
        XCTAssertNotEqual(before, after)
    }


    func testCandidateFingerprintIgnoresUnrelatedEvidenceChanges() {
        let original = RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"],
            recordedMealsThisWeek: 2
        )
        var changed = original
        changed.savedRecipeCount = 5
        changed.mostCookedRecipe = "Salad"

        let originalCandidate = InsightCandidateEngine.candidates(for: original).first { $0.id == "weekly-cooking" }
        let changedCandidate = InsightCandidateEngine.candidates(for: changed).first { $0.id == "weekly-cooking" }
        XCTAssertEqual(originalCandidate?.evidenceFingerprint, changedCandidate?.evidenceFingerprint)
    }

    func testResolveRequiresMatchingEvidenceFingerprint() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.shouldPresent(id: "weekly-cooking", evidenceFingerprint: "current"))
        XCTAssertFalse(store.resolve(id: "weekly-cooking", evidenceFingerprint: "stale"))
        XCTAssertEqual(store.record(for: "weekly-cooking")?.status, .active)
        XCTAssertTrue(store.resolve(id: "weekly-cooking", evidenceFingerprint: "current"))
        XCTAssertEqual(store.record(for: "weekly-cooking")?.status, .resolved)
        XCTAssertFalse(store.shouldPresent(id: "weekly-cooking", evidenceFingerprint: "current"))
    }

    func testStaleDismissAndSnoozeCannotChangeNewEvidenceVersion() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.shouldPresent(id: "weekly-cooking", evidenceFingerprint: "new"))
        XCTAssertFalse(store.dismiss(id: "weekly-cooking", evidenceFingerprint: "old"))
        XCTAssertFalse(store.snooze(id: "weekly-cooking", evidenceFingerprint: "old", until: Date().addingTimeInterval(3600)))
        XCTAssertEqual(store.record(for: "weekly-cooking")?.status, .active)
        XCTAssertEqual(store.record(for: "weekly-cooking")?.evidenceFingerprint, "new")
    }


    func testShoppingInsightRequiresMultipleRecipeSourcesAndPendingItems() {
        let input = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: [])
        let shopping = [
            ShoppingItem(name: "Tomatoes", quantity: 2, unit: "pcs", sources: ["Lentil soup"]),
            ShoppingItem(name: "Onions", quantity: 1, unit: "pcs", sources: ["Lentil soup", "Vegetable curry"]),
            ShoppingItem(name: "Rice", quantity: 1, unit: "kg", sources: ["Vegetable curry"]),
            ShoppingItem(name: "Bread", quantity: 1, unit: "loaf", done: true, sources: ["Bread"])
        ]
        let candidate = InsightCandidateEngine.candidates(for: input, shoppingItems: shopping).first
        XCTAssertEqual(candidate?.id, "shopping-multi-recipe")
        XCTAssertEqual(candidate?.action, .shoppingList)
        XCTAssertTrue(candidate?.insight.detail.contains("3 items") == true)
        XCTAssertTrue(candidate?.insight.detail.contains("2 saved recipes") == true)
    }

    func testShoppingInsightDoesNotAppearForOneRecipeOrOnlyCompletedItems() {
        let input = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: [])
        let oneSource = [
            ShoppingItem(name: "Tomatoes", quantity: 2, unit: "pcs", sources: ["Lentil soup"]),
            ShoppingItem(name: "Onions", quantity: 1, unit: "pcs", sources: ["Lentil soup"]),
            ShoppingItem(name: "Rice", quantity: 1, unit: "kg", sources: ["Lentil soup"])
        ]
        let completed = oneSource.map { item -> ShoppingItem in var value = item; value.done = true; return value }
        XCTAssertFalse(InsightCandidateEngine.candidates(for: input, shoppingItems: oneSource).contains { $0.id == "shopping-multi-recipe" })
        XCTAssertFalse(InsightCandidateEngine.candidates(for: input, shoppingItems: completed).contains { $0.id == "shopping-multi-recipe" })
    }


    func testNutritionDiaryInsightUsesOnlyLocalCoverageCounts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
        let entries = (0..<3).map { offset -> NutritionDiaryEntry in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            let snapshot = offset == 0
                ? NutritionSnapshot(energyKcal: 450, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
                : NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
            return NutritionDiaryEntry(
                foodName: "Meal \(offset)", date: date, meal: .lunch, quantity: 1,
                quantityUnit: "serving", servings: 1, source: .userProvided,
                sourceName: "You", nutrientsPerServing: snapshot,
                dayKey: NutritionDiaryDayKey.make(date, calendar: calendar)
            )
        }
        let input = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: [])
        let candidate = InsightCandidateEngine.candidates(for: input, nutritionEntries: entries, now: now, calendar: calendar)
            .first { $0.id == "nutrition-diary-coverage" }
        XCTAssertEqual(candidate?.action, .foodDiary)
        XCTAssertTrue(candidate?.insight.detail.contains("1 of 3 foods") == true)
        XCTAssertFalse(candidate?.insight.detail.contains("450") == true)
    }

    func testNutritionDiaryInsightRequiresThreeRecentEntriesAndOnlyAppearsForPartialCoverage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
        let input = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0, mostCookedRecipe: nil, recipeTitles: [])
        let completeEntries = (0..<3).map { offset -> NutritionDiaryEntry in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return NutritionDiaryEntry(
                foodName: "Meal \(offset)", date: date, meal: .lunch, quantity: 1,
                quantityUnit: "serving", servings: 1, source: .userProvided, sourceName: "You",
                nutrientsPerServing: NutritionSnapshot(energyKcal: 400, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
                dayKey: NutritionDiaryDayKey.make(date, calendar: calendar)
            )
        }
        XCTAssertFalse(InsightCandidateEngine.candidates(for: input, nutritionEntries: Array(completeEntries.prefix(2)), now: now, calendar: calendar).contains { $0.id == "nutrition-diary-coverage" })
        XCTAssertFalse(InsightCandidateEngine.candidates(for: input, nutritionEntries: completeEntries, now: now, calendar: calendar).contains { $0.id == "nutrition-diary-coverage" })
    }


    func testCandidatesExposeExplicitSourcePeriodAndCalibratedConfidenceMetadata() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0,
            mostCookedRecipe: nil, recipeTitles: [], recordedMealsThisWeek: 2
        )
        let candidate = InsightCandidateEngine.candidates(for: input).first
        XCTAssertEqual(candidate?.id, "weekly-cooking")
        XCTAssertEqual(candidate?.evidenceMetadata.source, "Cooking history")
        XCTAssertEqual(candidate?.evidenceMetadata.period, "This week")
        XCTAssertEqual(candidate?.evidenceMetadata.confidence, .high)
    }

    func testPossibleDuplicateTitlesUseModerateConfidenceRatherThanClaimingDuplicates() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 2, cookedRecipeCount: 0, cookingDayCount: 0,
            mostCookedRecipe: nil, recipeTitles: ["Soup", "Soup"],
            duplicateTitleGroups: [["Soup", "Soup"]]
        )
        let candidate = InsightCandidateEngine.candidates(for: input).first
        XCTAssertEqual(candidate?.evidenceMetadata.source, "Saved recipe titles")
        XCTAssertEqual(candidate?.evidenceMetadata.period, "Current collection")
        XCTAssertEqual(candidate?.evidenceMetadata.confidence, .moderate)
    }

    func testWeeklyCandidateFingerprintsChangeWhenTheWeekChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"],
            recordedMealsThisWeek: 2, firstTimeRecipesThisWeek: 1
        )
        let thisWeek = InsightCandidateEngine.candidates(for: input, now: now, calendar: calendar)
        let laterWeek = InsightCandidateEngine.candidates(for: input, now: nextWeek, calendar: calendar)
        for id in ["weekly-cooking", "recipe-discovery"] {
            let before = thisWeek.first { $0.id == id }?.evidenceFingerprint
            let after = laterWeek.first { $0.id == id }?.evidenceFingerprint
            XCTAssertNotNil(before)
            XCTAssertNotNil(after)
            XCTAssertNotEqual(before, after, "\(id) must not reuse a previous week's fingerprint")
        }
        let sameWeek = InsightCandidateEngine.candidates(for: input, now: now.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(thisWeek.first { $0.id == "weekly-cooking" }?.evidenceFingerprint,
                       sameWeek.first { $0.id == "weekly-cooking" }?.evidenceFingerprint)
    }

    func testDismissedWeeklyInsightReturnsWithNewWeekEvidence() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 4, cookedRecipeCount: 2, cookingDayCount: 2,
            mostCookedRecipe: nil, recipeTitles: ["Soup"], recordedMealsThisWeek: 2
        )
        let first = InsightCandidateEngine.candidates(for: input, now: now, calendar: calendar).first { $0.id == "weekly-cooking" }!
        XCTAssertTrue(store.shouldPresent(id: first.id, evidenceFingerprint: first.evidenceFingerprint))
        XCTAssertTrue(store.dismiss(id: first.id, evidenceFingerprint: first.evidenceFingerprint))
        XCTAssertFalse(store.shouldPresent(id: first.id, evidenceFingerprint: first.evidenceFingerprint))
        let later = InsightCandidateEngine.candidates(for: input, now: nextWeek, calendar: calendar).first { $0.id == "weekly-cooking" }!
        XCTAssertTrue(store.shouldPresent(id: later.id, evidenceFingerprint: later.evidenceFingerprint))
    }

    func testSuppressedHighRankCandidatesDoNotCrowdOutEligibleLowerRankCandidates() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 6, cookedRecipeCount: 3, cookingDayCount: 3,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"],
            duplicateTitleGroups: [["Soup", "soup"]],
            recordedMealsThisWeek: 3, firstTimeRecipesThisWeek: 1, currentStreak: 3
        )
        let unfiltered = InsightCandidateEngine.candidates(for: input)
        XCTAssertEqual(unfiltered.map(\.id), ["recipe-duplicates", "weekly-cooking", "recipe-discovery"])

        let suppressed: Set<String> = ["recipe-duplicates", "weekly-cooking"]
        let filtered = InsightCandidateEngine.candidates(for: input) { !suppressed.contains($0.id) }
        XCTAssertEqual(filtered.map(\.id), ["recipe-discovery", "cooking-streak"])
        XCTAssertLessThanOrEqual(filtered.count, InsightCandidateEngine.maximumCandidates)
    }

    func testLifecycleFilterAppliedBeforeCapSurfacesNextEligibleCandidate() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 6, cookedRecipeCount: 3, cookingDayCount: 3,
            mostCookedRecipe: nil, recipeTitles: ["Soup", "Salad"],
            duplicateTitleGroups: [["Soup", "soup"]],
            recordedMealsThisWeek: 3, firstTimeRecipesThisWeek: 1, currentStreak: 3
        )
        for candidate in InsightCandidateEngine.candidates(for: input) where candidate.id != "recipe-discovery" {
            XCTAssertTrue(store.shouldPresent(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint))
            XCTAssertTrue(store.dismiss(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint))
        }
        let presented = RecipeProgressInsightService.candidates(for: input) {
            store.shouldPresent(id: $0.id, evidenceFingerprint: $0.evidenceFingerprint)
        }
        XCTAssertTrue(presented.contains { $0.id == "recipe-discovery" })
        XCTAssertTrue(presented.contains { $0.id == "cooking-streak" })
        XCTAssertFalse(presented.contains { $0.id == "recipe-duplicates" || $0.id == "weekly-cooking" })
    }
    func testEligibleFallbackCandidatesAppearWhenAllPrimaryCandidatesAreSuppressed() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 6, cookedRecipeCount: 3, cookingDayCount: 3,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"],
            duplicateTitleGroups: [["Soup", "soup"]],
            recordedMealsThisWeek: 3, firstTimeRecipesThisWeek: 1, currentStreak: 3
        )
        let primaryIDs: Set<String> = [
            "recipe-duplicates", "weekly-cooking", "recipe-discovery", "cooking-streak"
        ]

        let presented = InsightCandidateEngine.candidates(for: input) { candidate in
            !primaryIDs.contains(candidate.id)
        }

        XCTAssertEqual(presented.map(\.id), ["cooking-rhythm", "recipe-collection"])
        XCTAssertTrue(presented.allSatisfy { !primaryIDs.contains($0.id) })
        XCTAssertLessThanOrEqual(presented.count, InsightCandidateEngine.maximumCandidates)
    }

    func testFallbackCandidatesAreNotAddedWhenAnyPrimaryCandidateIsEligible() {
        let input = RecipeProgressInsightInput(
            savedRecipeCount: 6, cookedRecipeCount: 3, cookingDayCount: 3,
            mostCookedRecipe: "Lentil soup", recipeTitles: ["Soup", "Salad"],
            duplicateTitleGroups: [["Soup", "soup"]],
            recordedMealsThisWeek: 3, firstTimeRecipesThisWeek: 1, currentStreak: 3
        )

        let presented = InsightCandidateEngine.candidates(for: input) {
            $0.id == "cooking-streak"
        }

        XCTAssertEqual(presented.map(\.id), ["cooking-streak"])
        XCTAssertFalse(presented.contains { $0.id == "cooking-rhythm" || $0.id == "recipe-collection" })
    }


    func testUnavailableDiarySkipsNutritionCoverageCandidateRatherThanFabricatingAbsence() {
        // nil (diary unreadable) must not produce diary-derived candidates; it is not an empty diary.
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = Calendar.autoupdatingCurrent
        let input = RecipeProgressInsightInput.make(recipes: [], historyEvents: [:])
        let candidates = InsightCandidateEngine.candidates(for: input, nutritionEntries: nil, now: now, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.id == "nutrition-diary-coverage" })
    }
}
