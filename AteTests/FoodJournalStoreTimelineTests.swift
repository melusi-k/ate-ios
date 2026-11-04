import XCTest
import SwiftData
@testable import Ate

/// #245 step 4 prep: the store's read-only timeline snapshot keeps every stored entry and writes nothing.
@MainActor
final class FoodJournalStoreTimelineTests: XCTestCase {
    private var container: ModelContainer!
    private var store: FoodJournalStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = FoodJournalStore(container: container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
    }

    override func tearDown() {
        container = nil
        store = nil
        calendar = nil
        super.tearDown()
    }

    private func meal(id: UUID = UUID(), name: String, date: Date, dayKey: String, type: NutritionMeal = .dinner) -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: name, date: date, meal: type, quantity: 100, quantityUnit: "g",
                            servings: 1, source: .userProvided, sourceName: "Label", sourceIdentifier: "",
                            verificationNote: "", nutrientsPerServing: NutritionSnapshot(energyKcal: 200, proteinGrams: nil,
                                                                                        carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
                            dayKey: dayKey)
    }

    func testEmptyStoreGivesNoItems() throws {
        XCTAssertTrue(try store.timelineItems(calendar: calendar).isEmpty)
    }

    func testUnavailableStoreThrowsInsteadOfLookingEmpty() {
        let unavailable = FoodJournalStore(container: nil)
        XCTAssertThrowsError(try unavailable.timelineItems(calendar: calendar)) { error in
            XCTAssertEqual(error as? JournalTimelineReadError, .storeUnavailable)
        }
    }

    func testMealsAndReflectionsAppearExactlyOnce() throws {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let mealID = UUID()
        try store.saveMeal(meal(id: mealID, name: "Pap and wors", date: day, dayKey: "2026-09-22"))
        let reflection = Ate.JournalEntry(id: "reflection-1", createdAt: day.addingTimeInterval(60), prompt: "How was it?",
                                          text: "Felt full", state: .balanced)
        container.mainContext.insert(reflection)
        try container.mainContext.save()

        let items = try store.timelineItems(calendar: calendar)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map { $0.id }), [mealID.uuidString, "reflection-1"])
        let mealItem = try XCTUnwrap(items.first { $0.id == mealID.uuidString })
        XCTAssertEqual(mealItem.kind, .meal)
        XCTAssertEqual(mealItem.meal, .dinner)
        XCTAssertEqual(mealItem.dayKey, "2026-09-22", "A stored meal day key wins")
        let reflectionItem = try XCTUnwrap(items.first { $0.id == "reflection-1" })
        XCTAssertEqual(reflectionItem.kind, .reflection)
        XCTAssertEqual(reflectionItem.dayKey, NutritionDiaryDayKey.make(reflection.createdAt, calendar: calendar),
                       "A legacy reflection with no day key falls back to its created day")
    }

    func testMealWithMissingPayloadStaysVisible() throws {
        let orphan = Ate.JournalEntry(id: "orphan-meal", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                                      prompt: "", text: "", state: .balanced)
        orphan.kindRaw = JournalEntryKind.meal.rawValue
        orphan.dayKey = "2026-09-22"
        container.mainContext.insert(orphan)
        try container.mainContext.save()

        let items = try store.timelineItems(calendar: calendar)
        XCTAssertEqual(items.map { $0.id }, ["orphan-meal"])
        XCTAssertNil(items.first?.meal)
        XCTAssertEqual(items.first?.kind, .meal)
    }

    func testReadingDoesNotChangeTheStore() throws {
        try store.saveMeal(meal(name: "Oats", date: Date(timeIntervalSince1970: 1_790_000_000), dayKey: "2026-09-22", type: .breakfast))
        let ctx = container.mainContext
        let entriesBefore = try ctx.fetchCount(FetchDescriptor<Ate.JournalEntry>())
        let payloadsBefore = try ctx.fetchCount(FetchDescriptor<JournalMealPayload>())

        _ = try store.timelineItems(calendar: calendar)
        _ = try store.timelineItems(calendar: calendar)

        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Ate.JournalEntry>()), entriesBefore)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<JournalMealPayload>()), payloadsBefore)
    }

    func testSectionsFilterAndSearchOverStoredEntries() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        try store.saveMeal(meal(name: "Pap and wors", date: t, dayKey: "2026-09-22", type: .dinner))
        try store.saveMeal(meal(name: "Oats", date: t.addingTimeInterval(-86_400), dayKey: "2026-09-21", type: .breakfast))
        let note = Ate.JournalEntry(id: "r1", createdAt: t.addingTimeInterval(10), prompt: "", text: "Loved the wors", state: .balanced)
        container.mainContext.insert(note)
        try container.mainContext.save()

        let items = try store.timelineItems(calendar: calendar)
        XCTAssertEqual(JournalTimeline.sections(items: items).map { $0.dayKey }, ["2026-09-22", "2026-09-21"])
        XCTAssertEqual(JournalTimeline.sections(items: items, filter: .meals(.breakfast)).flatMap { $0.items }.count, 1)
        XCTAssertEqual(JournalTimeline.sections(items: items, filter: .reflections).flatMap { $0.items }.map { $0.id }, ["r1"])
        XCTAssertEqual(JournalTimeline.sections(items: items, query: "WORS").flatMap { $0.items }.count, 2)
    }
}
