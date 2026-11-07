import XCTest
import SwiftData
@testable import Ate

/// #245 timeline logic: grouping, ordering, filters, search and building rows from stored entries. Pure values plus an
/// in-memory store; no UI. The app type is written `Ate.JournalEntry` because the legacy fixture in
/// LegacyJournalStoreUpgradeTests.swift shadows `JournalEntry` target-wide.
@MainActor
final class JournalTimelineTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = day; c.hour = hour; c.minute = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private func item(_ id: String, _ kind: JournalEntryKind, day: Int, hour: Int, key: String? = nil,
                      meal: NutritionMeal? = nil, recipe: Bool = false, text: String = "") -> JournalTimelineItem {
        JournalTimelineItem(id: id, kind: kind, createdAt: date(day, hour),
                            dayKey: key ?? String(format: "2026-11-%02d", day),
                            meal: meal, hasRecipeLink: recipe, searchText: text)
    }

    private var sample: [JournalTimelineItem] {
        [item("a", .meal, day: 1, hour: 8, meal: .breakfast, text: "Oats Breakfast"),
         item("b", .reflection, day: 1, hour: 20, recipe: true, text: "Mogodu Sunday"),
         item("c", .meal, day: 2, hour: 13, meal: .lunch, text: "Lentil soup Lunch"),
         item("d", .meal, day: 1, hour: 19, meal: .dinner, recipe: true, text: "Pap Dinner")]
    }

    func testGroupsNewestDayFirstAndNewestTimeFirstWithinDay() {
        let s = JournalTimeline.sections(items: sample)
        XCTAssertEqual(s.map { $0.dayKey }, ["2026-11-02", "2026-11-01"])
        XCTAssertEqual(s[0].items.map { $0.id }, ["c"])
        XCTAssertEqual(s[1].items.map { $0.id }, ["b", "d", "a"])
    }

    func testEqualTimestampsOrderByIdSoTheResultIsStable() {
        let same = [item("z", .reflection, day: 1, hour: 9), item("m", .reflection, day: 1, hour: 9)]
        XCTAssertEqual(JournalTimeline.sections(items: same)[0].items.map { $0.id }, ["m", "z"])
        XCTAssertEqual(JournalTimeline.sections(items: same.reversed())[0].items.map { $0.id }, ["m", "z"])
    }

    func testStoredDayKeyWinsOverTheTimestampDay() {
        let late = [item("x", .meal, day: 2, hour: 1, key: "2026-11-01", meal: .dinner)]
        XCTAssertEqual(JournalTimeline.sections(items: late).map { $0.dayKey }, ["2026-11-01"])
    }

    func testFilters() {
        func ids(_ f: JournalTimelineFilter) -> [String] {
            JournalTimeline.sections(items: sample, filter: f).flatMap { $0.items.map { $0.id } }
        }
        XCTAssertEqual(ids(.all).count, 4)
        XCTAssertEqual(Set(ids(.meals(nil))), ["a", "c", "d"])
        XCTAssertEqual(ids(.meals(.lunch)), ["c"])
        XCTAssertEqual(ids(.reflections), ["b"])
        XCTAssertEqual(Set(ids(.recipeLinked)), ["b", "d"])
        XCTAssertEqual(ids(.meals(.snack)), [])
    }

    func testSearchIsCaseAndDiacriticInsensitiveAndBlankMatchesAll() {
        let items = [item("a", .reflection, day: 1, hour: 9, text: "Crème brûlée")]
        XCTAssertEqual(JournalTimeline.sections(items: items, query: "creme BRULEE").count, 1)
        XCTAssertEqual(JournalTimeline.sections(items: items, query: "   ").count, 1)
        XCTAssertEqual(JournalTimeline.sections(items: items, query: "pizza").count, 0)
    }

    func testFilterAndSearchCombine() {
        let s = JournalTimeline.sections(items: sample, filter: .recipeLinked, query: "pap")
        XCTAssertEqual(s.flatMap { $0.items.map { $0.id } }, ["d"])
    }

    func testEmptyInputGivesNoSections() {
        XCTAssertTrue(JournalTimeline.sections(items: []).isEmpty)
    }

    // MARK: building rows from stored entries

    func testRowsFromStoredEntriesKeepEveryEntryIncludingAMealWithoutPayload() throws {
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!

        let reflection = Ate.JournalEntry(id: "r1", createdAt: date(3, 23), prompt: "p", text: "Cooked mogodu", state: .balanced,
                                          recipeIDs: ["rec1"])
        try reflection.setRecipeSnapshots([JournalRecipeSnapshot(recipeID: "rec1", title: "Mogodu", cookedDayKey: "2026-11-03")])

        let meal = Ate.JournalEntry(id: "m1", createdAt: date(3, 7), prompt: "", text: "", state: .balanced)
        meal.kindRaw = JournalEntryKind.meal.rawValue
        meal.dayKey = "2026-11-03"
        let payload = JournalMealPayload(entryID: "m1", meal: .breakfast, foodName: "Oats", quantity: 1, quantityUnit: "bowl",
                                         servings: 1, source: .userProvided, sourceName: "You",
                                         nutrients: NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil,
                                                                      fatGrams: nil, fibreGrams: nil))

        let orphan = Ate.JournalEntry(id: "m2", createdAt: date(3, 12), prompt: "", text: "", state: .balanced)
        orphan.kindRaw = JournalEntryKind.meal.rawValue
        orphan.dayKey = "2026-11-03"

        let damaged = Ate.JournalEntry(id: "r2", createdAt: date(4, 9), prompt: "", text: "old", state: .balanced)
        damaged.recipeSnapshotsRaw = "not json {"

        for e in [reflection, meal, orphan, damaged] { container.mainContext.insert(e) }
        container.mainContext.insert(payload)

        let rows = [reflection, meal, orphan, damaged].map {
            JournalTimeline.item(from: $0, payload: $0.id == "m1" ? payload : nil, calendar: utc)
        }
        XCTAssertEqual(rows.count, 4)

        XCTAssertEqual(rows[0].dayKey, "2026-11-03", "no stored day key falls back to the local day of createdAt")
        XCTAssertTrue(rows[0].hasRecipeLink)
        XCTAssertTrue(rows[0].searchText.contains("Mogodu"))

        XCTAssertEqual(rows[1].meal, .breakfast)
        XCTAssertTrue(rows[1].searchText.contains("Oats"))
        XCTAssertFalse(rows[1].hasRecipeLink)

        XCTAssertEqual(rows[2].kind, .meal)
        XCTAssertNil(rows[2].meal, "a meal without a payload stays visible with no meal type")

        XCTAssertFalse(rows[3].hasRecipeLink, "unreadable bytes without recipe IDs cannot prove a link")
        XCTAssertFalse(JournalTimeline.matches(rows[3], filter: .recipeLinked))
        XCTAssertEqual(damaged.recipeSnapshotsRaw, "not json {", "building a row never rewrites storage")

        let all = JournalTimeline.sections(items: rows)
        XCTAssertEqual(all.flatMap { $0.items }.count, 4)
    }
    func testUnknownMealTypeKeepsRowWithoutInventingSnackOrChangingRawBytes() {
        let entry = Ate.JournalEntry(id: "future-meal", createdAt: date(3, 7), prompt: "", text: "", state: .balanced)
        entry.kindRaw = JournalEntryKind.meal.rawValue
        entry.dayKey = "2026-11-03"
        let payload = JournalMealPayload(entryID: entry.id, meal: .breakfast, foodName: "Known food", quantity: 1,
                                         quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
                                         nutrients: NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil,
                                                                      fatGrams: nil, fibreGrams: nil))
        payload.mealRaw = "future-meal-type"
        let row = JournalTimeline.item(from: entry, payload: payload)
        XCTAssertEqual(row.kind, .meal)
        XCTAssertNil(row.meal)
        XCTAssertEqual(row.summary, "Known food")
        XCTAssertTrue(JournalTimeline.matches(row, filter: .meals(nil)))
        XCTAssertFalse(JournalTimeline.matches(row, filter: .meals(.snack)))
        XCTAssertFalse(row.searchText.contains(NutritionMeal.snack.title))
        XCTAssertEqual(payload.mealRaw, "future-meal-type")
    }

}
