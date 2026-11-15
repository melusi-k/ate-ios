import XCTest
@testable import Ate

@MainActor
final class InsightDestinationRoutingTests: XCTestCase {
    func testDiaryUsesOneTypedRouteWithoutSettingsObserverAndReplacesStalePath() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.settingsPath = [.nutritionGoals]
        store.showNutritionDiary = true
        store.openInsightFoodDiary()
        XCTAssertEqual(store.tab, .settings)
        XCTAssertEqual(store.settingsPath, [.nutritionDiary])
        XCTAssertFalse(store.showNutritionDiary)
        store.openInsightFoodDiary()
        XCTAssertEqual(store.settingsPath, [.nutritionDiary], "Repeated opens must not stack duplicate diary routes")
    }
    func testShoppingOpensRootAndDoesNotChangeDiaryOrJournalPaths() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.shoppingPath = [.nutritionGoals]
        store.settingsPath = [.nutritionDiary]
        store.trackerPath = [.insights]
        store.openInsightShoppingList()
        XCTAssertEqual(store.tab, .shopping)
        XCTAssertTrue(store.shoppingPath.isEmpty)
        XCTAssertEqual(store.settingsPath, [.nutritionDiary])
        XCTAssertEqual(store.trackerPath, [.insights])
    }
}
