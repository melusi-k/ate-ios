import XCTest
@testable import Ate

@MainActor
final class HardeningTests: XCTestCase {
    func rec(_ id: String, _ stamp: Double, del: Bool = false, data: Data? = Data("{\"a\":1}".utf8)) -> SyncRecord {
        SyncRecord(user_id: "u", kind: "recipe", id: id, data: del ? nil : data.map { AnyJSON($0) }, stampMs: stamp, deleted: del)
    }

    /// Checklist 4.8 — repeat syncs are idempotent: after one round-trip nothing is pushed again.
    func testRepeatSyncIsIdempotent() {
        let d = Data("{\"a\":1}".utf8)
        let local = SyncMerge.Local(data: ["r1": d, "r2": d], stamps: ["r1": 1760000000123.6, "r2": 1760000000456.2], tombstones: ["r3": 1760000000999.5])
        let first = SyncMerge.merge(local: local, remote: [])
        XCTAssertEqual(first.push, ["r1", "r2"]); XCTAssertEqual(first.pushDeletes, ["r3"])
        // the server now holds exactly what we pushed (bigint-rounded)
        let server = first.push.map { rec($0, first.stamps[$0]!) } + first.pushDeletes.map { rec($0, first.tombstones[$0]!, del: true) }
        var state = SyncMerge.Local(data: first.data, stamps: first.stamps, tombstones: first.tombstones)
        for _ in 0..<3 {
            let again = SyncMerge.merge(local: state, remote: server)
            XCTAssertEqual(again.push, [], "fractional stamps must not cause endless re-pushes")
            XCTAssertEqual(again.pushDeletes, [])
            XCTAssertEqual(Set(again.data.keys), ["r1", "r2"])
            state = .init(data: again.data, stamps: again.stamps, tombstones: again.tombstones)
        }
    }

    /// Checklist 4.4 — last write wins, tombstones beat older edits and lose to newer ones.
    func testLWWAndTombstones() {
        let d = Data("{}".utf8)
        let local = SyncMerge.Local(data: ["a": d], stamps: ["a": 100], tombstones: ["b": 300])
        let r = SyncMerge.merge(local: local, remote: [rec("a", 50, del: true), rec("b", 200), rec("c", 10)])
        XCTAssertNotNil(r.data["a"], "older remote delete must not remove a newer local edit")
        XCTAssertNil(r.data["b"], "older remote edit must not resurrect a newer local delete")
        XCTAssertNotNil(r.data["c"])
        let r2 = SyncMerge.merge(local: local, remote: [rec("a", 500, del: true)])
        XCTAssertNil(r2.data["a"]); XCTAssertEqual(r2.tombstones["a"], 500)
    }

    /// Checklist 4.7 — account switching.
    func testAccountSwitchDetection() {
        XCTAssertFalse(SyncMerge.isAccountSwitch(lastSyncedUser: nil, newUser: "a"))
        XCTAssertFalse(SyncMerge.isAccountSwitch(lastSyncedUser: "a", newUser: "a"))
        XCTAssertTrue(SyncMerge.isAccountSwitch(lastSyncedUser: "a", newUser: "b"))
    }

    /// Checklist 6.6/6.7 — 500-recipe library: filtering, sorting and grouping stay fast.
    func testLargeLibraryPerformance() {
        let names = ["chicken", "beef", "pasta", "tofu", "salmon", "rice", "lentils", "pork"]
        let cuisines = ["Italian", "Thai", "South African", "Mexican", nil]
        let now = Date().timeIntervalSince1970 * 1000
        let lib: [RecipeCard] = (0..<500).map { i in
            var r = RecipeCard(title: "Recipe \(i) \(names[i % 8])", description: "d", servings: 1 + i % 6, timeMinutes: 5 + (i * 7) % 120,
                               ingredients: [Ingredient(name: names[i % 8], quantity: 1, unit: "pcs", notes: nil),
                                             Ingredient(name: "onion", quantity: 1, unit: "pcs", notes: nil)],
                               steps: [Step(order: 1, instruction: "Cook.", timeSeconds: nil)])
            r.createdAt = now - Double(i) * 3_600_000; r.favorite = i % 9 == 0; r.cuisine = cuisines[i % 5]; r.sortIndex = Double(i)
            return r
        }
        var f = RecipeFilter(); f.maxMinutes = 30; f.tags = ["chicken"]
        let start = Date()
        var count = 0
        for g in LibraryLayout.GroupBy.allCases {
            for s in LibraryLayout.SortBy.allCases {
                var layout = LibraryLayout(); layout.group = g; layout.sort = s
                count += layout.sections(f.apply(lib, query: "")).count
                count += layout.sections(RecipeFilter().apply(lib, query: "recipe 4")).count
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(elapsed, 3.0, "all group×sort×filter combinations over 500 recipes took \(elapsed)s")
        measure { _ = LibraryLayout().sections(RecipeFilter().apply(lib, query: "chicken")) }
    }

    func testSessionExpiryMessageIsFriendly() {
        XCTAssertTrue(AppStore.sessionExpiredMessage.contains("sign in again"))
        XCTAssertTrue(AppStore.sessionExpiredMessage.contains("safe on this iPhone"))
    }

    func testQAFixturesParseWithRealParsers() throws {
        let c = try XCTUnwrap(JSONLD.recipe(fromHTML: QAFixtures.jsonLDHTML, sourceURL: QAFixtures.jsonLDURL))
        XCTAssertEqual(c.title, "Weekend shakshuka"); XCTAssertEqual(c.ingredients.count, 6); XCTAssertEqual(c.steps.count, 4)
        let cap = SocialLinks.caption(platform: .instagram, oEmbed: nil, meta: SocialLinks.meta(QAFixtures.instagramHTML))
        XCTAssertTrue(SocialLinks.isUseful(cap))
        let card = QAFixtures.cardFromCaption(cap, sourceURL: "x")
        XCTAssertTrue(card.title.contains("Creamy chakalaka pasta"), card.title)
        XCTAssertGreaterThanOrEqual(card.ingredients.count, 5)
    }
}
