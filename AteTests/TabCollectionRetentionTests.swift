import XCTest
@testable import Ate

@MainActor
final class TabCollectionRetentionTests: XCTestCase {
    func testSearchToLibraryTabKeepsSelectedCollection() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.filter.collection = .favourites
        store.selectTab(.search)
        XCTAssertEqual(store.tab, .search)
        XCTAssertEqual(store.filter.collection, .favourites)
        store.selectTab(.library)
        XCTAssertEqual(store.tab, .library)
        XCTAssertEqual(store.filter.collection, .favourites)
        store.selectTab(.library)
        XCTAssertEqual(store.filter.collection, .favourites, "Reselecting Library must not clear a collection")
    }

    func testExplicitAllLibraryDestinationStillClearsSelectedCollection() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.filter.collection = .favourites
        store.select(.library)
        XCTAssertEqual(store.tab, .library)
        XCTAssertNil(store.filter.collection)
    }
}
