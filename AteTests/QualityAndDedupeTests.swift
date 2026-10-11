import XCTest
@testable import Ate

/// C-AI-01..03, C-FIX-04/05/07, P0 duplicate saves (build 81 feedback).
final class QualityAndDedupeTests: XCTestCase {
    private func ribs(conf: Double = 0.9) -> RecipeCard {
        var c = RecipeCard(title: "Ribs and lemon pepper wings", servings: 4,
                           ingredients: [.init(name: "pork ribs", quantity: 1, unit: "kg"), .init(name: "chicken wings", quantity: 800, unit: "g"),
                                         .init(name: "lemon pepper", quantity: 2, unit: "tbsp")],
                           steps: [.init(order: 1, instruction: "Cook ribs", timeSeconds: nil),
                                   .init(order: 2, instruction: "Bake the wings until golden", timeSeconds: 1800)],
                           source: .appleIntelligence)
        c.aiConfidence = conf; c.aiAlternatives = ["Sticky ribs", "Lemon pepper wings"]
        return c
    }

    // C-AI-01: 80% threshold
    func testThresholdAsksBelow80AndSkipsAbove() {
        XCTAssertTrue(RecipeQuality.shouldAskDish(ribs(conf: 0.79), alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.shouldAskDish(ribs(conf: 0.8), alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.shouldAskDish(ribs(conf: 0.5), alreadyConfirmed: true), "asked once; then draft state")
        XCTAssertEqual(RecipeQuality.guesses(ribs(conf: 0.5)).first, "Ribs and lemon pepper wings", "pre-filled with inferred name")
        XCTAssertEqual(RecipeQuality.guesses(ribs(conf: 0.5)).count, 3)
        var manual = ribs(conf: 0.1); manual.source = .manual
        XCTAssertFalse(RecipeQuality.shouldAskDish(manual, alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.needsInput(manual))
    }
    // C-AI-02: output quality
    func testQualityIssuesForThinCard() {
        let i = RecipeQuality.issues(ribs())
        XCTAssertTrue(i.contains { $0.contains("4 ingredients") })
        XCTAssertTrue(i.contains { $0.contains("temperature") })
        XCTAssertTrue(i.contains { $0.contains("too vague") })
        XCTAssertTrue(RecipeQuality.needsInput(ribs()), "thin card is a draft even at 90%")
        var good = ribs()
        good.ingredients.append(.init(name: "garlic", quantity: 3, unit: "cloves"))
        good.steps = [.init(order: 1, instruction: "Rub the ribs with garlic and lemon pepper, cover and bake at 160°C for 2 hours", timeSeconds: nil),
                      .init(order: 2, instruction: "Roast the wings at 220 °C until golden and crisp, 30 minutes", timeSeconds: nil)]
        XCTAssertEqual(RecipeQuality.issues(good), [])
        XCTAssertFalse(RecipeQuality.needsInput(good))
    }
    // Cover tile icons by dish type
    func testTileIconsByDishType() {
        XCTAssertEqual(CoverLogic.tile(title: "Sticky ribs", cuisine: nil, ingredients: ["1 teaspoon paprika"]).symbol, "flame", "ribs is not a teacup")
        XCTAssertEqual(CoverLogic.tile(title: "Chicken sandwich", cuisine: nil, ingredients: []).symbol, "takeoutbag.and.cup.and.straw")
        XCTAssertEqual(CoverLogic.tile(title: "Rooibos iced tea", cuisine: nil, ingredients: []).symbol, "cup.and.saucer")
        XCTAssertNotEqual(CoverLogic.tile(title: "Steak", cuisine: nil, ingredients: []).symbol, "cup.and.saucer")
    }
    // P0 duplicate saves
    func testDedupeMergesExactDuplicatesWithinMinutes() {
        let t = 1_760_000_000_000.0
        var a = ribs(); a.id = "a"; a.createdAt = t
        var b = ribs(); b.id = "b"; b.createdAt = t + 60_000; b.favorite = true
        var c = ribs(); c.id = "c"; c.createdAt = t + 120_000
        var d = ribs(); d.id = "a"; d.createdAt = t            // same id twice
        var later = ribs(); later.id = "z"; later.createdAt = t + 3 * 86_400_000   // a deliberate re-save days later is kept
        var other = ribs(); other.id = "o"; other.title = "Other"
        let r = RecipeLogic.dedupe([a, b, c, d, later, other])
        XCTAssertEqual(r.cards.map(\.id), ["a", "z", "o"])
        XCTAssertEqual(Set(r.removedIDs), ["b", "c"])
        XCTAssertTrue(r.cards[0].favorite, "merged copy keeps the favourite flag")
    }
    @MainActor func testAddIsIdempotentForTheSameDraftID() {
        let s = AppStore(context: nil, backend: MockBackend())
        let before = s.recipes.count
        var r = ribs(); r.id = "draft-1"
        s.add(r); s.add(r); s.add(r)
        XCTAssertEqual(s.recipes.count, before + 1)
    }
    // C-FIX-05
    func testSpotlightSuggestionsCappedAtThreeFavourites() {
        var cards = (0..<10).map { RecipeCard(id: "r\($0)", title: "Recipe \($0)") }
        cards[4].favorite = true; cards[7].favorite = true
        let s = RecipeEntityQuery.suggestions(cards)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(Set(s.prefix(2).map(\.id)), ["r4", "r7"])
    }
    // C-FIX-07
    func testShoppingListReturnsTextValues() {
        let items = [ShoppingItem(name: "milk", quantity: 2, unit: "l"), ShoppingItem(name: "eggs", quantity: 0, unit: "")]
        XCTAssertEqual(SiriAnswers.listValues(items), ["milk (2 l)", "eggs"])
    }
}
