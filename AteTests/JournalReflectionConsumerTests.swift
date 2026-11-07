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
}
