import XCTest
@testable import Ate

final class SiriSnippetTests: XCTestCase {
    func testQuickRecipesUnder30() {
        let r = [RecipeCard(id: "a", title: "Mogodu", timeMinutes: 180), RecipeCard(id: "b", title: "Omelette", timeMinutes: 10),
                 RecipeCard(id: "c", title: "Toast", timeMinutes: 5), RecipeCard(id: "d", title: "Salad", timeMinutes: 15),
                 RecipeCard(id: "e", title: "Stir fry", timeMinutes: 25), RecipeCard(id: "f", title: "Unknown")]
        let q = SiriAnswers.quick(r)
        XCTAssertEqual(q.map(\.id), ["c", "b", "d"])
    }
    func testListLine() {
        let items = ["Carrots", "Rice", "Bananas", "Milk"].map { ShoppingItem(name: $0, quantity: 0, unit: "") }
        XCTAssertTrue(SiriAnswers.listLine(items).hasSuffix("and 1 more."))
        XCTAssertEqual(SiriAnswers.listLine([]), "Your ate shopping list is empty.")
    }
    func testRemaining() {
        let now = Date()
        let t = TimerSnapshot(recipeID: "r", recipeTitle: "Mogodu", stepIndex: 0, stepCount: 3, stepText: "", total: 600,
                              endDate: now.addingTimeInterval(125), pausedRemaining: 0)
        XCTAssertEqual(SiriAnswers.remaining(t, now: now), 125)
    }
}
