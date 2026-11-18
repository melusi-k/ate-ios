import XCTest
@testable import Ate

final class NutritionLogAgainTests: XCTestCase {
    @MainActor
    func testRepeatCreatesNewDayAndIdentityWithoutChangingPriorSnapshot() throws {
        let original = NutritionDiaryEntry(foodName: "Oats", date: Date(timeIntervalSince1970: 1_790_000_000),
            meal: .breakfast, quantity: 40, quantityUnit: "g", servings: 1.5,
            source: .externalFoodRecord, sourceName: "Package label", sourceIdentifier: "label-42",
            verificationNote: "Old package", nutrientsPerServing: NutritionSnapshot(
                energyKcal: 154.25, proteinGrams: nil, carbohydratesGrams: 26, fatGrams: 0, fibreGrams: nil),
            dayKey: "2026-11-01")
        let foods = NutritionFrequentFoods.topFoods(in: [original])
        let food = try XCTUnwrap(foods.first)
        var draft = NutritionFrequentFoods.draft(from: food, dayKey: "2026-11-16")
        draft.meal = .dinner
        let repeated = try draft.parsedEntry().get()
        XCTAssertNotEqual(repeated.id, original.id)
        XCTAssertEqual(repeated.dayKey, "2026-11-16")
        XCTAssertEqual(repeated.meal, .dinner)
        XCTAssertEqual(repeated.quantity, 40)
        XCTAssertEqual(repeated.quantityUnit, "g")
        XCTAssertEqual(repeated.servings, 1.5)
        XCTAssertEqual(repeated.nutrientsPerServing, original.nutrientsPerServing)
        XCTAssertNil(repeated.nutrientsPerServing.proteinGrams)
        XCTAssertEqual(repeated.nutrientsPerServing.fatGrams, 0)
        XCTAssertEqual(repeated.source, .userProvided)
        XCTAssertEqual(repeated.sourceName, NutritionEntrySource.userProvided.suggestedSourceName)
        XCTAssertEqual(repeated.sourceIdentifier, "")
        XCTAssertEqual(repeated.verificationNote, "")
        XCTAssertEqual(original.dayKey, "2026-11-01")
        XCTAssertEqual(original.sourceIdentifier, "label-42")
        XCTAssertEqual(original.verificationNote, "Old package")
    }

    func testSuggestionsUseWholeLocalHistoryAndExcludeDeletedRows() {
        func entry(_ name: String, day: String, energy: Double) -> NutritionDiaryEntry {
            NutritionDiaryEntry(foodName: name, date: .now, meal: .lunch, quantity: 1,
                quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
                nutrientsPerServing: NutritionSnapshot(energyKcal: energy), dayKey: day)
        }
        let older = entry("Beans", day: "2026-11-01", energy: 100)
        let recent = entry(" beans ", day: "2026-11-02", energy: 200)
        let deleted = entry("Removed", day: "2026-11-16", energy: 300)
        let retained = [older, recent, deleted].filter { $0.id != deleted.id }
        let foods = NutritionFrequentFoods.topFoods(in: retained)
        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods[0].foodName, "beans")
        XCTAssertEqual(foods[0].timesLogged, 2)
        XCTAssertEqual(foods[0].nutrientsPerServing.energyKcal, 200)
        XCTAssertTrue(NutritionFrequentFoods.topFoods(in: []).isEmpty)
    }
}
