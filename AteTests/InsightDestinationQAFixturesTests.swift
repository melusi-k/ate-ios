#if DEBUG
import XCTest
@testable import Ate

final class InsightDestinationQAFixturesTests: XCTestCase {
    func testSyntheticRecordsProduceRealShoppingAndDiaryCandidatesWithoutNutrientClaims() throws {
        let now = Date()
        let items = InsightDestinationQAFixtures.shopping()
        let entries = InsightDestinationQAFixtures.entries(now: now)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { !$0.done && $0.name.hasPrefix("QA insight") })
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.foodName.hasPrefix("QA insight") && $0.sourceName == "Synthetic UI fixture" })
        XCTAssertTrue(entries.allSatisfy { entry in NutritionGoalField.allCases.allSatisfy { entry.nutrientsPerServing[$0] == nil } })
        let input = RecipeProgressInsightInput(savedRecipeCount: 0, cookedRecipeCount: 0, cookingDayCount: 0,
                                               mostCookedRecipe: nil, recipeTitles: [])
        let candidates = InsightCandidateEngine.candidates(for: input, shoppingItems: items, nutritionEntries: entries, now: now)
        let shopping = try XCTUnwrap(candidates.first { $0.id == "shopping-multi-recipe" })
        let diary = try XCTUnwrap(candidates.first { $0.id == "nutrition-diary-coverage" })
        XCTAssertEqual(shopping.action, .shoppingList)
        XCTAssertEqual(diary.action, .foodDiary)
        XCTAssertTrue(diary.insight.detail.contains("0 of 3 foods"))
        XCTAssertEqual(Set(candidates.map(\.id)), ["shopping-multi-recipe", "nutrition-diary-coverage"])
    }
}
#endif
