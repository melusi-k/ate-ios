import XCTest
import SwiftData
@testable import Ate

/// #245 step 4: the timeline screen's content decisions, row text and day headers.
@MainActor
final class JournalTimelineViewTests: XCTestCase {
    private func item(_ id: String, _ kind: JournalEntryKind, day: String, meal: NutritionMeal? = nil, summary: String = "") -> JournalTimelineItem {
        JournalTimelineItem(id: id, kind: kind, createdAt: Date(timeIntervalSince1970: 1_700_000_000), dayKey: day,
                            meal: meal, hasRecipeLink: false, searchText: summary, summary: summary)
    }

    func testEntryNavigationPreservesReflectionIdentityAndStoredMealDay() {
        let reflection = item("reflection-id", .reflection, day: "2026-11-02")
        XCTAssertEqual(JournalTimelineView.destination(for: reflection, canonicalAvailable: true), .reflection("reflection-id"))
        XCTAssertEqual(JournalTimelineView.destination(for: reflection, canonicalAvailable: false), .reflection("reflection-id"))
        let meal = item("meal-id", .meal, day: "2026-11-01", meal: .dinner)
        XCTAssertEqual(JournalTimelineView.destination(for: meal, canonicalAvailable: true), .mealDay("2026-11-01"))
        XCTAssertEqual(JournalTimelineView.destination(for: meal, canonicalAvailable: false), .unavailable)
        let missing = item("orphan", .meal, day: "2026-11-01")
        XCTAssertEqual(JournalTimelineView.destination(for: missing, canonicalAvailable: true), .unavailable)
    }

    func testLoadingShowsLoading() {
        XCTAssertEqual(JournalTimelineContent.make(state: .loading, filter: .all, query: ""), .loading)
    }

    func testReadFailureIsAnErrorNotAnEmptyJournal() {
        XCTAssertEqual(JournalTimelineContent.make(state: .failed(.readFailed), filter: .all, query: ""), .readError(.readFailed))
        XCTAssertEqual(JournalTimelineContent.make(state: .failed(.storeUnavailable), filter: .all, query: ""), .readError(.storeUnavailable))
    }

    func testEmptyStoreIsEmptyJournalNotNoMatches() {
        XCTAssertEqual(JournalTimelineContent.make(state: .loaded([]), filter: .all, query: "x"), .emptyJournal)
    }

    func testFilterOrQueryWithNoHitsIsNoMatches() {
        let items = [item("a", .reflection, day: "2026-11-02", summary: "soup")]
        XCTAssertEqual(JournalTimelineContent.make(state: .loaded(items), filter: .all, query: "pizza"), .noMatches)
        XCTAssertEqual(JournalTimelineContent.make(state: .loaded(items), filter: .meals(nil), query: ""), .noMatches)
    }

    func testMealTypeFilterKeepsOrphanMealOnlyUnderAllMeals() {
        let items = [item("m", .meal, day: "2026-11-02", meal: .lunch, summary: "Rice"),
                     item("o", .meal, day: "2026-11-02", meal: nil, summary: "Meal details unavailable")]
        guard case .sections(let all) = JournalTimelineContent.make(state: .loaded(items), filter: .meals(nil), query: ""),
              case .sections(let lunch) = JournalTimelineContent.make(state: .loaded(items), filter: .meals(.lunch), query: "") else {
            return XCTFail("expected sections")
        }
        XCTAssertEqual(all.flatMap(\.items).count, 2)
        XCTAssertEqual(lunch.flatMap(\.items).map(\.id), ["m"])
    }

    func testOrphanMealAndLegacyReflectionStayVisible() {
        let items = [item("m", .meal, day: "2026-11-02", meal: nil, summary: "Meal details unavailable"),
                     item("r", .reflection, day: "2026-11-01", summary: "old note")]
        guard case .sections(let s) = JournalTimelineContent.make(state: .loaded(items), filter: .all, query: "") else {
            return XCTFail("expected sections")
        }
        XCTAssertEqual(s.map(\.dayKey), ["2026-11-02", "2026-11-01"])
        XCTAssertEqual(s.flatMap(\.items).count, 2)
    }

    /// The summary the row shows comes from the real stored entries, through the real store snapshot.
    func testStoredEntriesProduceNonBlankSummaries() throws {
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = FoodJournalStore(container: container)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let id = UUID()
        try store.saveMeal(NutritionDiaryEntry(id: id, foodName: "Pap and wors", date: day, meal: .dinner, quantity: 100,
                                               quantityUnit: "g", servings: 1, source: .userProvided, sourceName: "Label",
                                               sourceIdentifier: "", verificationNote: "",
                                               nutrientsPerServing: NutritionSnapshot(energyKcal: 200, proteinGrams: nil, carbohydratesGrams: nil,
                                                                                     fatGrams: nil, fibreGrams: nil),
                                               dayKey: "2026-09-22"))
        container.mainContext.insert(Ate.JournalEntry(id: "r1", createdAt: day, prompt: "How was it?", text: "Felt full", state: .balanced))
        let orphan = Ate.JournalEntry(id: "o1", createdAt: day, prompt: "", text: "", state: .balanced)
        orphan.kindRaw = JournalEntryKind.meal.rawValue
        orphan.dayKey = "2026-09-22"
        container.mainContext.insert(orphan)
        try container.mainContext.save()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let byID = Dictionary(uniqueKeysWithValues: try store.timelineItems(calendar: cal).map { ($0.id, $0.summary) })
        XCTAssertEqual(byID[id.uuidString], "Pap and wors")
        XCTAssertEqual(byID["r1"], "Felt full")
        XCTAssertEqual(byID["o1"], "Meal details unavailable")
    }

    /// 2 November 2026 is a Monday. The header names the stored day in the calendar's zone, whatever zone the phone is in.
    func testDayTitleNamesTheStoredDayInTheCalendarZone() {
        let us = Locale(identifier: "en_US")
        for zone in ["UTC", "Pacific/Kiritimati", "America/Los_Angeles", "Africa/Johannesburg"] {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(JournalTimelineView.dayTitle("2026-11-02", calendar: cal, locale: us), "Monday, November 2, 2026", zone)
        }
    }

    func testDayTitleFallsBackToKeyWhenUnparseable() {
        XCTAssertEqual(JournalTimelineView.dayTitle("not-a-day"), "not-a-day")
    }
}
