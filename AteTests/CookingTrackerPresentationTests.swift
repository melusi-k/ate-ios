import XCTest
@testable import Ate

final class CookingTrackerPresentationTests: XCTestCase {
    func testDeletedRecipeUsesClearFallbackLabel() {
        XCTAssertEqual(
            CookingTrackerPresentation.recipeTitle(for: "deleted-recipe-id", recipes: []),
            "Recipe no longer in your library"
        )
    }
}

@MainActor
final class JournalPrimaryNavigationTests: XCTestCase {
    func testDeepLinkHasOneHistoryRootAndOneDetail() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.openJournalEntry("generic-entry-id")
        XCTAssertEqual(store.tab, .tracker)
        XCTAssertEqual(store.trackerPath, [.journalEntry("generic-entry-id")])
        store.trackerPath = []
        XCTAssertTrue(store.isAtTabRoot)
        XCTAssertEqual(store.activeBottomAddContext, .journal)
    }

    func testRootActionDoesNotInheritPriorDestination() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.bottomAddContext = .food
        let cases: [(AppTab, BottomAddContext)] = [(.library, .recipe), (.shopping, .shopping),
                                                          (.tracker, .journal), (.settings, .none), (.search, .recipe)]
        for (tab, context) in cases {
            store.select(tab)
            XCTAssertEqual(store.activeBottomAddContext, context)
        }
        store.select(.settings)
        store.settingsPath = [.insights]
        XCTAssertEqual(store.activeBottomAddContext, .food, "Pushed destination retains its own context")
    }
}
