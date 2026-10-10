import XCTest
@testable import Ate

final class LogicTests: XCTestCase {
    func testScaling() {
        let c = RecipeCard(servings: 2, ingredients: [Ingredient(name: "flour", quantity: 1.333, unit: "g", notes: nil)])
        let s = RecipeLogic.scaled(c, factor: 3)
        XCTAssertEqual(s.servings, 6)
        XCTAssertEqual(s.ingredients[0].quantity, 4.0, accuracy: 0.001)
    }

    func testNiceRound() {
        XCTAssertEqual(Units.niceRound(123), 125)
        XCTAssertEqual(Units.niceRound(12.4), 12)
        XCTAssertEqual(Units.niceRound(1.3), 1.25)
        XCTAssertEqual(Units.niceRound(0.333), 0.33)
    }

    func testUnitConversion() {
        let (q, u) = Units.convert(quantity: 1, unit: "cup", to: .metric)
        XCTAssertEqual(q, 240); XCTAssertEqual(u, "ml")
        let (q2, u2) = Units.convert(quantity: 500, unit: "g", to: .imperial)
        XCTAssertEqual(u2, "lb"); XCTAssertEqual(q2, 1, accuracy: 0.01)
        XCTAssertEqual(Units.convertTemperatures(in: "Bake at 200°C", to: .imperial), "Bake at 390°F")
    }

    func testFormatUnit() {
        XCTAssertEqual(Units.formatAmount(2, "clove"), "2 cloves")
        XCTAssertEqual(Units.formatAmount(3, "pcs"), "3")
        XCTAssertEqual(Units.formatAmount(2, "leaf"), "2 leaves")
        XCTAssertEqual(Units.formatAmount(1.5, "tbsp"), "1.5 tbsp")
    }

    func testDurations() {
        XCTAssertEqual(Units.findDurations(in: "Simmer 8-10 mins"), [600])
        XCTAssertEqual(Units.findDurations(in: "Roast 1 hr 15 min"), [4500])
    }

    func testShoppingMerge() {
        var list = ShoppingLogic.merge([Ingredient(name: "flour", quantity: 800, unit: "g", notes: nil)], source: "Bread", into: [])
        list = ShoppingLogic.merge([Ingredient(name: "Flour", quantity: 0.5, unit: "kg", notes: nil)], source: "Cake", into: list)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].unit, "kg")
        XCTAssertEqual(list[0].quantity, 1.3, accuracy: 0.001)
        XCTAssertEqual(list[0].sources ?? [], ["Bread", "Cake"])
        list = ShoppingLogic.merge([Ingredient(name: "eggs", quantity: 2, unit: "", notes: nil)], source: nil, into: list)
        list = ShoppingLogic.merge([Ingredient(name: "egg", quantity: 1, unit: "pcs", notes: nil)], source: nil, into: list)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[1].quantity, 3)
        XCTAssertEqual(list[1].aisle, .dairy)
    }

    func testExports() {
        let items = [ShoppingItem(name: "flour", quantity: 300, unit: "g", notes: "sifted")]
        XCTAssertEqual(ShoppingLogic.exportText(items), "ate — shopping list\n\n[ ] 300 g flour (sifted)")
        XCTAssertTrue(ShoppingLogic.exportCSV(items).hasPrefix("item,quantity,unit,notes,aisle,recipe,done\n\"flour\",300,\"g\""))
    }

    func testShareText() {
        let c = RecipeCard(title: "Toast", description: "Crunchy", servings: 1, timeMinutes: 5,
                           ingredients: [Ingredient(name: "bread", quantity: 2, unit: "slice", notes: nil)],
                           steps: [Step(order: 1, instruction: "Toast it.", timeSeconds: nil)], sourceURL: "https://x.y")
        XCTAssertEqual(RecipeLogic.text(for: c, factor: 2),
                       "Toast\nCrunchy\n2 servings · 5 min\n\nIngredients\n- 4 slices bread\n\nSteps\n1. Toast it.\n\nSource: https://x.y")
    }

    func testSyncMergeLastWriteWins() {
        let a = Data(#"{"v":"local"}"#.utf8), b = Data(#"{"v":"remote"}"#.utf8)
        let local = SyncMerge.Local(data: ["1": a, "2": a, "3": a], stamps: ["1": 100, "2": 300, "3": 50], tombstones: ["4": 500])
        let remote = [
            SyncRecord(user_id: "u", kind: "recipe", id: "1", data: AnyJSON(b), updated_at: 200, deleted: false),  // remote newer
            SyncRecord(user_id: "u", kind: "recipe", id: "2", data: AnyJSON(b), updated_at: 200, deleted: false),  // local newer
            SyncRecord(user_id: "u", kind: "recipe", id: "3", data: nil, updated_at: 60, deleted: true),           // remote delete
            SyncRecord(user_id: "u", kind: "recipe", id: "5", data: AnyJSON(b), updated_at: 10, deleted: false),   // new remote
        ]
        let r = SyncMerge.merge(local: local, remote: remote)
        XCTAssertEqual(r.data["1"].flatMap { String(data: $0, encoding: .utf8) }?.contains("remote"), true)
        XCTAssertEqual(r.data["2"], a)
        XCTAssertNil(r.data["3"])
        XCTAssertNotNil(r.data["5"])
        XCTAssertEqual(r.push, ["2"])
        XCTAssertEqual(r.pushDeletes, ["4"])
    }

    func testImportAndDecode() throws {
        let json = #"[{"id":"a","title":"A","servings":2,"tags":[],"ingredients":[{"name":"x","quantity":1,"unit":"g"}],"steps":[],"createdAt":1},{"id":"b","title":"Empty","ingredients":[],"steps":[]}]"#
        let cards = try JSONDecoder().decode([RecipeCard].self, from: Data(json.utf8))
        let res = RecipeLogic.importCards(cards, into: [])
        XCTAssertEqual(res.added, 1)
        XCTAssertEqual(res.result.first?.id, "a")
    }
}
