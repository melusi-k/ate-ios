import XCTest
@testable import Ate

/// Cook Mode ingredient sheet state: the cook session carries the servings factor and the
/// gathered-ingredient checks, and sessions persisted by older builds still decode.
final class CookSessionTests: XCTestCase {

    func testLegacySessionWithoutFactorDecodesWithDefaults() throws {
        let json = #"{"recipeID":"r1","stepIndex":2}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(CookSession.self, from: json)
        XCTAssertEqual(s.recipeID, "r1")
        XCTAssertEqual(s.stepIndex, 2)
        XCTAssertEqual(s.factor, 1)
        XCTAssertEqual(s.checked, [])
    }

    func testSessionRoundTripsFactorAndChecked() throws {
        let s = CookSession(recipeID: "r1", stepIndex: 1, factor: 2, checked: [0, 3])
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(CookSession.self, from: data), s)
    }

    func testToggleCheckedAddsAndRemoves() {
        var s = CookSession(recipeID: "r1", stepIndex: 0)
        s.toggleChecked(2)
        s.toggleChecked(0)
        XCTAssertEqual(Set(s.checked), [0, 2])
        s.toggleChecked(2)
        XCTAssertEqual(s.checked, [0])
    }

    /// The sheet renders RecipeLogic.scaled + Units exactly like the recipe detail, so amounts
    /// must follow the session factor (rice 150 g at 3x reads "450 g" under metric).
    func testScaledIngredientAmountsFollowSessionFactor() {
        var r = RecipeCard()
        r.servings = 2
        r.ingredients = [Ingredient(name: "rice", quantity: 150, unit: "g", notes: nil)]
        let scaled = RecipeLogic.scaled(r, factor: 3)
        XCTAssertEqual(scaled.ingredients.first?.quantity, 450)
        let (q, u) = Units.convert(quantity: scaled.ingredients[0].quantity, unit: scaled.ingredients[0].unit, to: .metric)
        XCTAssertEqual(Units.formatAmount(q, u), "450 g")
    }

    /// The sheet picker offers 1x/2x/3x, but amounts must render correctly for any factor a
    /// session could carry (e.g. a factor set by a future entry point): scaling never assumes
    /// the picker set.
    func testScaledAmountsRenderForArbitraryFactor() {
        var r = RecipeCard()
        r.servings = 2
        r.ingredients = [Ingredient(name: "rice", quantity: 150, unit: "g", notes: nil)]
        let scaled = RecipeLogic.scaled(r, factor: 1.5)
        let (q, u) = Units.convert(quantity: scaled.ingredients[0].quantity, unit: scaled.ingredients[0].unit, to: .metric)
        XCTAssertEqual(Units.formatAmount(q, u), "225 g")
        XCTAssertEqual(scaled.servings, 3)
    }
}
