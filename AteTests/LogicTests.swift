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
                           steps: [Step(order: 1, instruction: "toast it.", timeSeconds: nil)], sourceURL: "https://x.y")
        XCTAssertEqual(RecipeLogic.text(for: c, factor: 2),
                       "Toast\nCrunchy\n2 servings · 5 min\n\nIngredients\n• 4 slices bread\n\nSteps\n1. Toast it.\n\nSource: https://x.y")
        let shared = RecipeLogic.text(for: c, shareURL: "https://h/r/abc")
        XCTAssertTrue(shared.hasSuffix("\n\nView in ate: https://h/r/abc"))
        XCTAssertEqual(shared.components(separatedBy: "https://h/r/abc").count, 2, "link must appear exactly once")
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

    func testSyncRecordEncodesIntegerStampsAndNullData() throws {
        let recs = [
            SyncRecord(user_id: "u", kind: "recipe", id: "1", data: AnyJSON(Data(#"{"a":1}"#.utf8)), stampMs: 1760076000123.456, deleted: false),
            SyncRecord(user_id: "u", kind: "shopping", id: "2", data: nil, stampMs: 1760076000999.9, deleted: true),
        ]
        let json = String(decoding: try JSONEncoder().encode(recs), as: UTF8.self)
        XCTAssertTrue(json.contains(#""updated_at":1760076000123"#), json)
        XCTAssertTrue(json.contains(#""updated_at":1760076001000"#), json)
        XCTAssertFalse(json.contains("1760076000123."), "bigint column rejects fractions: \(json)")
        // Every object must carry the same keys (PostgREST PGRST102), so nil data is written as null.
        XCTAssertTrue(json.contains(#""data":null"#), json)
        let objs = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(Set(objs[0].keys), Set(objs[1].keys))
        XCTAssertEqual(Set(objs[0].keys), ["user_id", "kind", "id", "data", "updated_at", "deleted"])
        // Tolerant decoding: integers, fractional numbers and numeric strings.
        let back = try JSONDecoder().decode([SyncRecord].self, from: Data(#"[{"user_id":"u","kind":"recipe","id":"1","data":null,"updated_at":5.6,"deleted":false},{"user_id":"u","kind":"recipe","id":"2","updated_at":"7","deleted":true}]"#.utf8))
        XCTAssertEqual(back.map(\.updated_at), [6, 7])
        XCTAssertNil(back[1].data)
    }
}


@MainActor final class ShoppingRecoveryTests: XCTestCase {
    private func store() -> AppStore { AppStore(context: nil, backend: MockBackend()) }
    private func session(_ userID: String) -> AuthSession {
        AuthSession(accessToken: "t", refreshToken: "r", expiresAt: 0, userID: userID, email: "t@example.com")
    }

    func testEditPreservesIdentitySourcesUnitAndCompletion() throws {
        let store = store()
        let item = ShoppingItem(id: "item", name: "Milk", quantity: 1, unit: "l", done: true,
                                from: "Pancakes", sources: ["Pancakes"], notes: "full cream", aisle: .dairy)
        store.shopping = [item]
        XCTAssertTrue(store.editShoppingItem(item.id, name: "  Oat milk  ", quantity: 2.5))
        let edited = try XCTUnwrap(store.shopping.first)
        XCTAssertEqual(edited.id, item.id); XCTAssertEqual(edited.name, "Oat milk")
        XCTAssertEqual(edited.quantity, 2.5); XCTAssertEqual(edited.unit, item.unit)
        XCTAssertEqual(edited.done, item.done); XCTAssertEqual(edited.sources, item.sources)
        XCTAssertEqual(edited.from, item.from); XCTAssertEqual(edited.notes, item.notes)
        let restored = try JSONDecoder().decode(ShoppingItem.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(restored, edited)
    }

    func testEditRederivesAisleOnlyWhenNameChanges() throws {
        let store = store()
        store.shopping = [ShoppingItem(id: "item", name: "Milk", quantity: 1, unit: "l", aisle: .dairy)]
        XCTAssertTrue(store.editShoppingItem("item", name: "Milk", quantity: 2))
        XCTAssertEqual(store.shopping.first?.aisle, .dairy, "quantity-only edit keeps the aisle")
        XCTAssertTrue(store.editShoppingItem("item", name: "Chicken breast", quantity: 2))
        XCTAssertEqual(store.shopping.first?.aisle, .meatFish, "rename re-derives the aisle")
        XCTAssertTrue(store.editShoppingItem("item", name: "zz unmatched", quantity: 2))
        XCTAssertEqual(store.shopping.first?.aisle, .other)

        // An aisle no rule produced survives while the name is unchanged.
        store.shopping = [ShoppingItem(id: "m", name: "zz unmatched", quantity: 1, unit: "", aisle: .pantry)]
        XCTAssertTrue(store.editShoppingItem("m", name: "zz unmatched", quantity: 3))
        XCTAssertEqual(store.shopping.first?.aisle, .pantry)

        // A nil aisle stays nil until the name changes.
        store.shopping = [ShoppingItem(id: "n", name: "Milk", quantity: 1, unit: "l")]
        XCTAssertTrue(store.editShoppingItem("n", name: "Milk", quantity: 2))
        XCTAssertNil(store.shopping.first?.aisle)
    }

    func testInvalidOrMissingEditsDoNotMutate() {
        let store = store()
        let item = ShoppingItem(id: "item", name: "Milk", quantity: 1, unit: "l")
        store.shopping = [item]
        XCTAssertFalse(store.editShoppingItem(item.id, name: " \n", quantity: 1))
        XCTAssertFalse(store.editShoppingItem(item.id, name: "Milk", quantity: -1))
        XCTAssertFalse(store.editShoppingItem(item.id, name: "Milk", quantity: .infinity))
        XCTAssertFalse(store.editShoppingItem(item.id, name: "Milk", quantity: .nan))
        XCTAssertFalse(store.editShoppingItem("missing", name: "Milk", quantity: 1))
        XCTAssertEqual(store.shopping, [item])
        XCTAssertTrue(store.editShoppingItem(item.id, name: "Milk", quantity: 0))
        XCTAssertEqual(store.shopping.first?.unit, "", "clearing the amount clears the dangling unit")
    }

    func testQuantityParsingIsDeterministicAcrossLocales() {
        XCTAssertEqual(ShoppingEdit.parseQuantity(""), 0, "empty means no amount")
        XCTAssertEqual(ShoppingEdit.parseQuantity("  "), 0)
        XCTAssertEqual(ShoppingEdit.parseQuantity("0"), 0)
        // "." and "," both mean decimal, in every locale: de_DE must never read "2.5" as 25.
        XCTAssertEqual(ShoppingEdit.parseQuantity("2.5"), 2.5)
        XCTAssertEqual(ShoppingEdit.parseQuantity("2,5"), 2.5)
        XCTAssertEqual(ShoppingEdit.parseQuantity(" 3 "), 3)
        XCTAssertEqual(ShoppingEdit.parseQuantity("5."), 5)
        XCTAssertEqual(ShoppingEdit.parseQuantity(".5"), 0.5)
        XCTAssertEqual(ShoppingEdit.parseQuantity("1,000"), 1, "grouping is unsupported: a separator is always decimal")
        XCTAssertNil(ShoppingEdit.parseQuantity("-1"))
        XCTAssertNil(ShoppingEdit.parseQuantity("abc"))
        XCTAssertNil(ShoppingEdit.parseQuantity("2.5.3"))
        XCTAssertNil(ShoppingEdit.parseQuantity("1e3"))
    }

    func testQuantityTextRoundTripsExactly() {
        XCTAssertEqual(ShoppingEdit.quantityText(0), "", "no amount shows as an empty field")
        // Bounded, realistic quantities: plain decimal in, exact value back, every locale.
        for q in [2.0, 2.5, 2.505, 0.1, 1234567.89] {
            XCTAssertEqual(ShoppingEdit.parseQuantity(ShoppingEdit.quantityText(q)), q,
                           "editor initial text must parse back to the stored value: \(q)")
        }
        XCTAssertEqual(ShoppingEdit.quantityText(2.0), "2", "whole numbers seed without a trailing .0")
        let huge = ShoppingEdit.quantityText(1e16)
        XCTAssertFalse(huge.contains("e"), "extreme values seed as plain decimal, not \(huge)")
        XCTAssertEqual(ShoppingEdit.parseQuantity(huge), 1e16)
    }

    func testNameOnlyEditIsNeverTrappedBySeededQuantity() {
        // Untouched field stores the original, even if its text would not parse (legacy value).
        let seeded = "1e-12"
        XCTAssertEqual(ShoppingEdit.effectiveQuantity(original: 1e-12, originalText: seeded, editedText: seeded), 1e-12)
        XCTAssertNil(ShoppingEdit.parseQuantity(seeded), "seed text itself stays unaccepted once edited")
        // An untouched ordinary field keeps its exact value.
        let text = ShoppingEdit.quantityText(2.505)
        XCTAssertEqual(ShoppingEdit.effectiveQuantity(original: 2.505, originalText: text, editedText: text), 2.505)
        // Edits go through the parser.
        XCTAssertEqual(ShoppingEdit.effectiveQuantity(original: 2.505, originalText: text, editedText: "3"), 3)
        XCTAssertNil(ShoppingEdit.effectiveQuantity(original: 2.505, originalText: text, editedText: "abc"))
    }

    func testUndoRestoresRemovedItemWithoutOverwritingOtherEdits() throws {
        let store = store()
        let a = ShoppingItem(id: "a", name: "Milk", quantity: 1, unit: "l", done: true)
        let b = ShoppingItem(id: "b", name: "Eggs", quantity: 6, unit: "")
        store.shopping = [a, b]
        store.removeShoppingItemWithUndo(a.id)
        XCTAssertEqual(store.shopping.map(\.id), ["b"])
        XCTAssertEqual(store.toast?.message, "Removed “Milk”")
        XCTAssertEqual(store.toast?.actionTitle, "Undo")
        XCTAssertTrue(store.editShoppingItem(b.id, name: "Eggs", quantity: 12))
        store.runToastAction()
        XCTAssertEqual(store.shopping.map(\.id), ["a", "b"])
        XCTAssertEqual(store.shopping[0], a)
        XCTAssertEqual(store.shopping[1].quantity, 12)
        store.runToastAction()
        XCTAssertEqual(store.shopping.count, 2)
    }

    func testRapidConsecutiveRemovalsShareOneUndoBatch() {
        let store = store()
        let a = ShoppingItem(id: "a", name: "Milk", quantity: 1, unit: "l")
        let b = ShoppingItem(id: "b", name: "Eggs", quantity: 6, unit: "")
        let c = ShoppingItem(id: "c", name: "Bread", quantity: 1, unit: "")
        store.shopping = [a, b, c]
        store.removeShoppingItemWithUndo(a.id)
        store.removeShoppingItemWithUndo(b.id)
        XCTAssertEqual(store.shopping.map(\.id), ["c"])
        XCTAssertEqual(store.pendingShoppingUndoCount, 2, "the second removal joins the batch instead of discarding the first")
        XCTAssertEqual(store.toast?.message, "Removed 2 items")
        store.runToastAction()
        XCTAssertEqual(store.shopping, [a, b, c], "Undo restores the whole batch in original order")
        XCTAssertNil(store.toast)
    }

    func testUndoWindowExpiryFinalizesRemovals() {
        let store = store()
        let a = ShoppingItem(id: "a", name: "Milk", quantity: 1, unit: "l")
        store.shopping = [a]
        store.removeShoppingItemWithUndo(a.id)
        XCTAssertEqual(store.pendingShoppingUndoCount, 1)
        store.finalizeShoppingUndo()
        XCTAssertEqual(store.pendingShoppingUndoCount, 0, "expiry drops the batch")
        store.runToastAction()
        XCTAssertTrue(store.shopping.isEmpty, "a late Undo tap must not resurrect a finalized removal")
    }

    func testUndoDoesNotDuplicateAnItemRestoredBySync() {
        let store = store()
        let item = ShoppingItem(id: "a", name: "Milk", quantity: 1, unit: "l")
        store.shopping = [item]
        store.removeShoppingItemWithUndo(item.id)
        store.shopping = [item]
        store.runToastAction()
        XCTAssertEqual(store.shopping, [item])
    }

    func testUndoAfterAccountChangeIsBlockedWithTruthfulCopy() {
        let store = store()
        store.session = session("u1")
        // Guaranteed cleanup, even on a failed assertion: with no session the delayed syncNow
        // returns before any network work. Unit tests must not talk to Supabase.
        defer { store.session = nil }
        let a = ShoppingItem(id: "a", name: "Milk", quantity: 1, unit: "l")
        store.shopping = [a]
        store.removeShoppingItemWithUndo(a.id)
        store.session = session("u2")
        store.runToastAction()
        XCTAssertTrue(store.shopping.isEmpty, "items removed under another account are never restored")
        XCTAssertEqual(store.toast?.isError, true)
        XCTAssertEqual(store.toast?.message, "Couldn’t restore — your account changed since removal.")
    }
}
