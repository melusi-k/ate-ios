import XCTest
@testable import Ate

/// Pure decisions behind the Today tab (#642): greeting boundaries and the saved
/// recipe preview order. No clocks, stores or backends; every case is deterministic.
final class TodayHomeTests: XCTestCase {
    private func card(_ id: String, favorite: Bool = false, createdAt: Double) -> RecipeCard {
        var c = RecipeCard()
        c.id = id
        c.favorite = favorite
        c.createdAt = createdAt
        return c
    }

    /// Every bucket edge is asserted on both sides through the injected hour:
    /// 4/5, 11/12, 16/17 and 21/22, plus the midnight wrap. Late-night hours stay
    /// neutral instead of saying "Good evening" after midnight (#645).
    func testGreetingBoundaries() {
        XCTAssertEqual(TodayHome.greeting(hour: 0), "Hello")
        XCTAssertEqual(TodayHome.greeting(hour: 4), "Hello")
        XCTAssertEqual(TodayHome.greeting(hour: 5), "Good morning")
        XCTAssertEqual(TodayHome.greeting(hour: 11), "Good morning")
        XCTAssertEqual(TodayHome.greeting(hour: 12), "Good afternoon")
        XCTAssertEqual(TodayHome.greeting(hour: 16), "Good afternoon")
        XCTAssertEqual(TodayHome.greeting(hour: 17), "Good evening")
        XCTAssertEqual(TodayHome.greeting(hour: 21), "Good evening")
        XCTAssertEqual(TodayHome.greeting(hour: 22), "Hello")
        XCTAssertEqual(TodayHome.greeting(hour: 23), "Hello")
    }

    func testPreviewFavouritesFirstThenNewestWithStableTies() {
        let recipes = [
            card("old", createdAt: 100),
            card("new", createdAt: 300),
            card("fav-old", favorite: true, createdAt: 50),
            card("mid", createdAt: 200),
            card("fav-new", favorite: true, createdAt: 400),
        ]
        XCTAssertEqual(TodayHome.preview(recipes).map(\.id), ["fav-new", "fav-old", "new"])
        XCTAssertEqual(TodayHome.preview(recipes, limit: 5).map(\.id), ["fav-new", "fav-old", "new", "mid", "old"])
        // Equal favourite state and creation time break on identity, never on input order.
        let tie = [card("b", createdAt: 100), card("a", createdAt: 100)]
        XCTAssertEqual(TodayHome.preview(tie, limit: 2).map(\.id), ["a", "b"])
        XCTAssertEqual(TodayHome.preview(tie.reversed(), limit: 2).map(\.id), ["a", "b"])
    }

    func testPreviewEmptyAndNonPositiveLimitsStayEmpty() {
        XCTAssertTrue(TodayHome.preview([]).isEmpty)
        let recipes = [card("one", createdAt: 1)]
        XCTAssertEqual(TodayHome.preview(recipes, limit: 1).map(\.id), ["one"])
        XCTAssertTrue(TodayHome.preview(recipes, limit: 0).isEmpty)
        XCTAssertTrue(TodayHome.preview(recipes, limit: -1).isEmpty)
    }
}
