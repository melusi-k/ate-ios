import XCTest
import SwiftData
@testable import Ate

@MainActor
final class JournalReflectionConsumerTests: XCTestCase {
    func testReflectionsExcludeMealsAndUnknownKindsWithoutChangingUnifiedTimeline() throws {
        let journal = JournalStore(inMemory: true)
        let id = try journal.saveManual(text: "Dinner went well")
        let meals = FoodJournalStore(container: journal.container)
        let meal = NutritionDiaryEntry(foodName: "Pap", date: .now, meal: .dinner, quantity: 1,
            quantityUnit: "portion", servings: 1, source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: nil, proteinGrams: nil,
                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        try meals.saveMeal(meal)
        let context = try XCTUnwrap(journal.container).mainContext
        let unknown = Ate.JournalEntry(prompt: "", text: "Future record", state: nil)
        unknown.kindRaw = "future-kind"
        context.insert(unknown)
        try context.save()
        XCTAssertEqual(try journal.readReflections().map(\.id), [id])
        XCTAssertEqual(try meals.timelineItems().count, 3, "The unified timeline must not drop non-reflection records")
        XCTAssertEqual(try meals.readMeals(), [meal])
    }

    func testUnavailableReflectionsThrowInsteadOfLookingEmpty() {
        let journal = JournalStore(container: nil, openState: .unavailable(error: "fixture"))
        XCTAssertThrowsError(try journal.readReflections()) { error in
            XCTAssertEqual(error as? JournalTimelineReadError, .storeUnavailable)
        }
    }

    func testReflectionDetailEditAndDeleteCannotMutateMealOrUnknownKind() throws {
        let journal = JournalStore(inMemory: true)
        let meals = FoodJournalStore(container: journal.container)
        let meal = NutritionDiaryEntry(foodName: "Sample lunch", date: .now, meal: .lunch,
            quantity: 1, quantityUnit: "portion", servings: 1, source: .userProvided,
            sourceName: "You", nutrientsPerServing: NutritionSnapshot(energyKcal: 715,
                proteinGrams: 55, carbohydratesGrams: nil, fatGrams: 55, fibreGrams: nil))
        try meals.saveMeal(meal)
        let context = try XCTUnwrap(journal.container).mainContext
        let row = try XCTUnwrap(try context.fetch(FetchDescriptor<Ate.JournalEntry>())
            .first { $0.id == meal.id.uuidString })
        XCTAssertNil(journal.entry(row.id), "Reflection detail must not resolve a meal")
        journal.update(row, text: "Must not become reflection text")
        journal.delete(row)
        XCTAssertEqual(try meals.readMeals(), [meal])
        XCTAssertEqual(row.text, "")
        let future = Ate.JournalEntry(prompt: "", text: "Future original", state: nil)
        future.kindRaw = "future-kind"
        context.insert(future)
        try context.save()
        journal.update(future, text: "Must not rewrite future kind")
        journal.delete(future)
        XCTAssertNil(journal.entry(future.id))
        XCTAssertEqual(future.text, "Future original")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Ate.JournalEntry>()).contains { $0.id == future.id })
        XCTAssertTrue(try journal.readReflections().isEmpty)
    }

    func testCommittedDeletionDisappearsFromPreviouslyLoadedReflectionHistory() throws {
        let journal = JournalStore(inMemory: true)
        let id = try journal.saveManual(text: "Delete only this reflection")
        let loaded = try journal.readReflections()
        let row = try XCTUnwrap(loaded.first { $0.id == id })
        XCTAssertTrue(journal.delete(row))
        XCTAssertFalse(try journal.readReflections().contains { $0.id == id })
        XCTAssertNil(journal.entry(id))
    }

    func testFailedDeletionReportsFailureAndKeepsReflection() throws {
        let original = JournalStore(inMemory: true)
        let id = try original.saveManual(text: "Keep after failed save")
        let row = try XCTUnwrap(try original.readReflections().first { $0.id == id })
        enum Injected: Error { case save }
        let failing = JournalStore(container: original.container, openState: .ok,
            writeReflectionContext: { _ in throw Injected.save })
        XCTAssertFalse(failing.delete(row))
        XCTAssertEqual(try original.readReflections().first { $0.id == id }?.text,
                       "Keep after failed save")
    }

}
