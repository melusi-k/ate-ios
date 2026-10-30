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
}
