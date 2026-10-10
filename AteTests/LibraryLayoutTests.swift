import XCTest
@testable import Ate

final class LibraryLayoutTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_760_086_800) // Fri 10 Oct 2026 09:00 UTC
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }
    func ms(daysAgo d: Double) -> Double { (now.timeIntervalSince1970 - d * 86_400) * 1000 }

    func card(_ t: String, mins: Int? = nil, ago: Double = 0, cooked: Double? = nil, fav: Bool = false, idx: Double? = nil,
              cuisine: String? = nil, ing: [String] = []) -> RecipeCard {
        var r = RecipeCard(id: t, title: t, timeMinutes: mins, ingredients: ing.map { Ingredient(name: $0, quantity: 1, unit: "", notes: nil) },
                           createdAt: ms(daysAgo: ago))
        r.lastCookedAt = cooked; r.favorite = fav; r.sortIndex = idx; r.cuisine = cuisine
        return r
    }

    lazy var rs: [RecipeCard] = [
        card("banana bread", mins: 70, ago: 0, cuisine: "American"),
        card("Apple pie", mins: 50, ago: 3, cooked: 10, fav: true, idx: 2, cuisine: "american"),
        card("Curry", mins: 25, ago: 20, cooked: 20, idx: 0, cuisine: "Indian", ing: ["chicken"]),
        card("Toast", mins: nil, ago: 1, idx: 1),
    ]

    func titles(_ l: LibraryLayout) -> [String] { l.sorted(rs).map(\.title) }

    func testSorts() {
        var l = LibraryLayout()
        l.sort = .newest; XCTAssertEqual(titles(l), ["banana bread", "Toast", "Apple pie", "Curry"])
        l.sort = .az; XCTAssertEqual(titles(l), ["Apple pie", "banana bread", "Curry", "Toast"], "case-insensitive")
        l.sort = .quickest; XCTAssertEqual(titles(l), ["Curry", "Apple pie", "banana bread", "Toast"], "no time last")
        l.sort = .recentlyCooked; XCTAssertEqual(titles(l), ["Curry", "Apple pie", "banana bread", "Toast"])
        l.sort = .favouritesFirst; XCTAssertEqual(titles(l).first, "Apple pie")
        l.sort = .myOrder; XCTAssertEqual(titles(l), ["banana bread", "Curry", "Toast", "Apple pie"], "unordered (new) first, then sortIndex")
    }

    func testGroupAddedBuckets() {
        var l = LibraryLayout(); l.group = .added; l.sort = .newest
        let s = l.sections(rs, now: now, calendar: cal)
        XCTAssertEqual(s.map(\.title), ["Today", "This week", "Earlier"])
        XCTAssertEqual(s[0].recipes.map(\.title), ["banana bread"])
        XCTAssertEqual(s[1].recipes.map(\.title), ["Toast", "Apple pie"])
    }

    func testGroupCuisineNormalisesCaseAndOtherLast() {
        var l = LibraryLayout(); l.group = .cuisine
        let s = l.sections(rs, now: now, calendar: cal)
        XCTAssertEqual(s.map(\.title), ["American", "Indian", "Other"])
        XCTAssertEqual(s[0].recipes.count, 2)
    }

    func testGroupCookTimeAndMainIngredient() {
        var l = LibraryLayout(); l.group = .cookTime
        XCTAssertEqual(l.sections(rs, now: now, calendar: cal).map(\.title), ["Under 30 min", "Under an hour", "Over an hour", "No time given"])
        l.group = .mainIngredient
        XCTAssertEqual(l.sections(rs, now: now, calendar: cal).map(\.title), ["Chicken", "Other"])
        l.group = .none
        XCTAssertEqual(l.sections(rs).count, 1)
    }

    func testReorderOnlyFlatMyOrder() {
        var l = LibraryLayout(); l.sort = .myOrder
        XCTAssertTrue(l.canReorder)
        l.group = .cuisine; XCTAssertFalse(l.canReorder)
    }

    @MainActor func testStoreMoveAssignsSortIndexAndUndoDelete() {
        let store = AppStore(context: nil, backend: MockBackend())
        store.recipes = [card("A"), card("B"), card("C")]
        store.move("C", before: "A", in: store.recipes)
        XCTAssertEqual(store.layout.sort, .myOrder)
        XCTAssertEqual(store.layout.sorted(store.recipes).map(\.title), ["C", "A", "B"])
        store.deleteWithUndo("A")
        XCTAssertNil(store.recipe("A"))
        store.runToastAction()
        XCTAssertNotNil(store.recipe("A"))
    }

    func testPersistenceAndCuisineDecoding() throws {
        let d = UserDefaults(suiteName: "layout-\(UUID())")!
        var l = LibraryLayout(); l.group = .cookTime; l.sort = .az; l.save(d)
        XCTAssertEqual(LibraryLayout.load(d), l)
        let r = try JSONDecoder().decode(RecipeCard.self, from: Data(#"{"id":"x","title":"t","cuisine":"","sortIndex":3}"#.utf8))
        XCTAssertNil(r.cuisine, "empty cuisine treated as none"); XCTAssertEqual(r.sortIndex, 3)
    }
}
