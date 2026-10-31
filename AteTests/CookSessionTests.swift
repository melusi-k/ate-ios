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

    // MARK: Ingredient edits invalidate positional gathered checks

    private func makeStore() -> AppStore {
        UserDefaults.standard.removeObject(forKey: "ate.cookSession.v1")
        return AppStore(context: nil, backend: MockBackend())
    }

    private func card(_ id: String, _ ings: [String]) -> RecipeCard {
        var r = RecipeCard()
        r.id = id; r.title = id; r.servings = 2
        r.ingredients = ings.map { Ingredient(name: $0, quantity: 100, unit: "g", notes: nil) }
        r.steps = [Step(order: 1, instruction: "Cook it.", timeSeconds: nil)]
        return r
    }

    func testEditingIngredientsClearsGatheredChecks() {
        let store = makeStore()
        store.recipes = [card("r1", ["rice", "miso"])]
        store.beginCookSession(recipeID: "r1", factor: 1)
        store.toggleCookIngredientChecked(0)
        XCTAssertEqual(store.cookSession?.checked, [0])
        store.update(card("r1", ["rice", "miso", "honey"]))
        XCTAssertEqual(store.cookSession?.checked, [])
    }

    func testNonIngredientEditKeepsGatheredChecks() {
        let store = makeStore()
        store.recipes = [card("r1", ["rice", "miso"])]
        store.beginCookSession(recipeID: "r1", factor: 1)
        store.toggleCookIngredientChecked(1)
        var edited = card("r1", ["rice", "miso"])
        edited.title = "Renamed"
        store.update(edited)
        XCTAssertEqual(store.cookSession?.checked, [1])
    }

    /// A session whose signature no longer matches (legacy data, or a recipe changed elsewhere,
    /// e.g. sync) resets on the next toggle instead of checking the wrong row.
    func testToggleAfterExternalChangeResetsThenApplies() {
        let store = makeStore()
        store.recipes = [card("r1", ["rice", "miso"])]
        store.beginCookSession(recipeID: "r1", factor: 1)
        store.toggleCookIngredientChecked(0)
        store.cookSession?.ingredientSignature = "stale"
        store.toggleCookIngredientChecked(4)
        XCTAssertEqual(store.cookSession?.checked, [4])
    }

    /// beginCookSession on the same recipe keeps checks only while the ingredient list is unchanged.
    func testBeginCookSessionResetsChecksWhenIngredientsChanged() {
        let store = makeStore()
        store.recipes = [card("r1", ["rice", "miso"])]
        store.beginCookSession(recipeID: "r1", factor: 1)
        store.toggleCookIngredientChecked(0)
        store.recipes = [card("r1", ["miso", "rice"])] // reordered outside update()
        store.beginCookSession(recipeID: "r1", factor: 2)
        XCTAssertEqual(store.cookSession?.checked, [])
        XCTAssertEqual(store.cookSession?.factor, 2)
    }

    /// Sync-merge / add-replace-by-id style wholesale replacement of the recipes array also
    /// invalidates checks for the session recipe, while factor and step are preserved.
    func testWholesaleRecipeReplacementClearsChecksPreservesFactorAndStep() {
        let store = makeStore()
        store.recipes = [card("r1", ["rice", "miso"])]
        store.beginCookSession(recipeID: "r1", factor: 2)
        store.updateCookSession(recipeID: "r1", stepIndex: 1)
        store.toggleCookIngredientChecked(0)
        store.recipes = [card("r1", ["rice", "miso", "honey"])]
        XCTAssertEqual(store.cookSession?.checked, [])
        XCTAssertEqual(store.cookSession?.factor, 2)
        XCTAssertEqual(store.cookSession?.stepIndex, 1)
    }

    /// Separator characters in user or imported ingredient text must not let two different
    /// ingredient lists produce the same signature (would keep checks pointing at wrong rows).
    func testIngredientSignatureResistsSeparatorCollisions() {
        var a = RecipeCard()
        a.ingredients = [Ingredient(name: "salt|100.0|", quantity: 0, unit: "g", notes: nil)]
        var b = RecipeCard()
        b.ingredients = [Ingredient(name: "salt", quantity: 100, unit: "|0.0|g", notes: nil)]
        // In the naive "name|qty|unit" join both lists yield "salt|100.0||0.0|g".
        XCTAssertNotEqual(RecipeLogic.ingredientSignature(a), RecipeLogic.ingredientSignature(b))
        XCTAssertEqual(RecipeLogic.ingredientSignature(a), RecipeLogic.ingredientSignature(a))
    }
}
