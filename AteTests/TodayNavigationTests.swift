import XCTest
@testable import Ate

/// Navigation ownership for the #642 Today tab: the collection has one canonical
/// root, the store-wide add/import sheets have exactly one owner across push, pop,
/// dismissal and tab switches, and the Add/timer chrome follows only the two roots.
@MainActor
final class TodayNavigationTests: XCTestCase {
    private func makeStore() -> AppStore {
        AppStore(context: nil, backend: MockBackend())
    }

    func testExplicitCollectionSelectionResolvesOneCanonicalRoot() {
        let store = makeStore()
        store.openCollection()
        XCTAssertEqual(store.path, [.library])
        store.path.append(.recipe("A"))
        store.select(.library)
        XCTAssertEqual(store.path, [.library], "re-selection from a detail must not stack a second collection")
        store.path.append(.recipe("A"))
        store.select(.collection(.favourites))
        XCTAssertEqual(store.path, [.library])
        store.openCollection()
        store.openCollection()
        XCTAssertEqual(store.path, [.library], "selection is idempotent")
    }

    func testSheetOwnerTransfersExactlyOnceAcrossPushPopAndTabSwitch() {
        let store = makeStore()
        XCTAssertEqual(store.homeSheetOwner, .today, "the home tab starts at the Today root")
        store.openCollection()
        XCTAssertEqual(store.homeSheetOwner, .collection)
        store.path.append(.recipe("A"))
        XCTAssertEqual(store.homeSheetOwner, .none, "a pushed detail owns no store-wide sheet")
        store.path = []
        XCTAssertEqual(store.homeSheetOwner, .today, "dismissal back to the root returns ownership once")
        store.select(.settings)
        XCTAssertEqual(store.homeSheetOwner, .none, "a tab switch away suspends ownership")
        store.select(.library)
        XCTAssertEqual(store.homeSheetOwner, .collection, "returning selects the canonical collection")
        store.path = []
        XCTAssertEqual(store.homeSheetOwner, .today)
    }

    /// The owner enum is only the gate: drive the real request, dismissal and save
    /// effects through the store, so a regression that double-presents, strands a
    /// request or saves twice fails here even while the enum stays correct.
    func testQuickAddRequestDismissAndSaveEffectsHappenExactlyOnce() {
        let store = makeStore()
        XCTAssertEqual(store.homeSheetOwner, .today)

        // A pending request has exactly one owner at every step of the push: the
        // collection sheet adopts the SAME request, never a second copy.
        store.quickAdd = QuickAddRequest(mode: .link)
        let pending = store.quickAdd
        store.openCollection()
        XCTAssertEqual(store.homeSheetOwner, .collection)
        XCTAssertEqual(store.quickAdd, pending, "the push transfers the same request to the one owner")
        // Dismiss: the request clears and nothing saves.
        store.quickAdd = nil
        XCTAssertNil(store.quickAdd)
        XCTAssertTrue(store.recipes.isEmpty, "a dismissed request saves nothing")

        // Save at the collection root: exactly one recipe, request consumed.
        store.quickAdd = QuickAddRequest(mode: .link)
        var first = RecipeCard()
        first.id = "collection-save"
        first.title = "Collection save"
        store.add(first)
        store.quickAdd = nil
        XCTAssertEqual(store.recipes.map(\.id), ["collection-save"], "one request, exactly one saved recipe")
        XCTAssertNil(store.quickAdd, "the save consumes the request")

        // Dismissal back to the Today root returns ownership once; a fresh request
        // there saves exactly once more and routes to the new detail, which owns
        // no store-wide sheet.
        store.path = []
        XCTAssertEqual(store.homeSheetOwner, .today)
        store.quickAdd = QuickAddRequest(mode: .link)
        var second = RecipeCard()
        second.id = "today-save"
        second.title = "Today save"
        store.add(second)
        store.quickAdd = nil
        store.path.append(.recipe(second.id))
        XCTAssertEqual(store.recipes.map(\.id), ["today-save", "collection-save"])
        XCTAssertEqual(store.homeSheetOwner, .none, "the pushed detail owns no store-wide sheet")
    }

    func testSystemSearchKeepsTheCollectionOnTheHomeStack() {
        let store = makeStore()
        store.path.append(.recipe("A"))
        store.search("tripe")
        XCTAssertEqual(store.tab, .library)
        XCTAssertEqual(store.path, [.library], "search resolves the collection instead of clearing the stack")
        XCTAssertEqual(store.pendingSearch, "tripe")
        store.search("  ")
        XCTAssertEqual(store.pendingSearch, "")
    }

    func testAddAndTimerChromeFollowTabRootAndCanonicalCollectionRootOnly() {
        let store = makeStore()
        XCTAssertTrue(store.isAtTabRoot)
        XCTAssertFalse(store.isAtCollectionRoot)
        XCTAssertEqual(store.rootAddContext, .recipe)
        store.openCollection()
        XCTAssertFalse(store.isAtTabRoot)
        XCTAssertTrue(store.isAtCollectionRoot, "the pushed collection keeps Add/timer chrome")
        store.path.append(.recipe("A"))
        XCTAssertFalse(store.isAtCollectionRoot, "a detail above the collection keeps neither")
        store.select(.settings)
        XCTAssertFalse(store.isAtCollectionRoot)
        XCTAssertNil(store.rootAddContext)
    }
}
