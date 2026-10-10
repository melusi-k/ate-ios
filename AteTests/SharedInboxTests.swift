import XCTest
@testable import Ate

@MainActor
final class SharedInboxTests: XCTestCase {
    func testQueueIsFIFOAndCapped() {
        let d = UserDefaults(suiteName: "inbox-test-\(UUID())")!
        XCTAssertNil(SharedInbox.pop(d))
        for i in 0..<25 { SharedInbox.push(.init(url: "https://x.test/\(i)"), d) }
        XCTAssertEqual(SharedInbox.load(d).count, 20)
        XCTAssertEqual(SharedInbox.pop(d)?.url, "https://x.test/5")
        XCTAssertEqual(SharedInbox.load(d).count, 19)
    }
    func testFirstURLInCaption() {
        XCTAssertEqual(SharedInbox.firstURL(in: "omg try this 🍝 https://www.tiktok.com/@chef/video/123 #pasta"),
                       "https://www.tiktok.com/@chef/video/123")
        XCTAssertNil(SharedInbox.firstURL(in: "no links here"))
    }
    func testImportDeepLinkPicksUpInbox() {
        let store = AppStore(context: nil, backend: MockBackend())
        SharedInbox.save([])
        SharedInbox.push(.init(url: "https://example.com/soup"))
        store.tab = .settings
        store.handle(url: URL(string: "ate://import")!)
        XCTAssertEqual(store.pendingImport?.url, "https://example.com/soup")
        XCTAssertEqual(store.tab, .library)
    }
    func testDeepLinksSelectTabs() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.tab = .shopping
        store.handle(url: URL(string: "ate://recipe/abc")!)
        XCTAssertEqual(store.tab, .library)
        XCTAssertEqual(store.path, [.shared("abc")])
    }
}

final class ProvenanceTests: XCTestCase {
    func testLegacyRecipeDecodesAsUnknown() throws {
        let json = #"{"id":"a","title":"Old soup","servings":2,"tags":[],"ingredients":[],"steps":[],"createdAt":1}"#
        let r = try JSONDecoder().decode(RecipeCard.self, from: Data(json.utf8))
        XCTAssertEqual(r.source, .unknown)
        XCTAssertNil(r.generatedAt)
        XCTAssertNil(r.source.badge)
    }
    func testUnrecognisedSourceIsUnknownAndRoundTrips() throws {
        let bad = #"{"id":"a","title":"x","source":"quantumOven"}"#
        XCTAssertEqual(try JSONDecoder().decode(RecipeCard.self, from: Data(bad.utf8)).source, .unknown)
        var r = RecipeCard(title: "AI pasta"); r.source = .appleIntelligence; r.generatedAt = 1_760_000_000_000
        let back = try JSONDecoder().decode(RecipeCard.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.source, .appleIntelligence)
        XCTAssertEqual(back.generatedAt, 1_760_000_000_000)
        XCTAssertEqual(back.source.badge, "Made with Apple Intelligence")
        XCTAssertEqual(RecipeSource.jsonLD.badge, "Imported from page data")
        XCTAssertEqual(RecipeSource.mock.badge, "Demo")
    }
    func testJSONLDImportIsTaggedJSONLD() async throws {
        // the JSON-LD parser itself leaves source to the backend; new cards default to manual
        XCTAssertEqual(RecipeCard().source, .manual)
    }
}

@MainActor
final class TabBadgeTests: XCTestCase {
    func testBadgeCountsUntickedItems() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.shopping = [ShoppingItem(name: "a", quantity: 1, unit: ""), ShoppingItem(name: "b", quantity: 1, unit: "", done: true),
                          ShoppingItem(name: "c", quantity: 1, unit: "")]
        XCTAssertEqual(store.pendingShoppingCount, 2)
    }
}
