import XCTest
@testable import Ate

final class SyncPayloadSafetyTests: XCTestCase {
    private func row(_ json: String?, kind: String = "recipe", id: String = "r", deleted: Bool = false) -> SyncRecord {
        SyncRecord(user_id: "a", kind: kind, id: id, data: json.map { AnyJSON(Data($0.utf8)) }, updated_at: 100, deleted: deleted)
    }
    func testLegacyAndCurrentAdditiveRecipePayloadsAccepted() throws {
        try SyncPayloadSafety.validate([
            row(#"{"id":"r","title":"Old soup"}"#),
            row(#"{"id":"r","title":"Soup","servings":2,"ingredients":[],"steps":[],"futureOptional":"kept-compatible"}"#)
        ], owner: "a")
    }
    func testCurrentAndAdditiveShoppingAccepted() throws {
        try SyncPayloadSafety.validate([row(#"{"id":"r","name":"Beans","quantity":1,"unit":"bag","done":false,"futureOptional":true}"#, kind: "shopping")], owner: "a")
    }
    func testMalformedIdentityArraysNumbersAndFutureVersionFailClosed() {
        let invalid = [
            row(#"[]"#), row(nil), row(#"{"title":"No identity"}"#),
            row(#"{"id":"different","title":"Wrong identity"}"#),
            row(#"{"id":"r","title":42}"#),
            row(#"{"id":"r","title":"Soup","ingredients":"not an array"}"#),
            row(#"{"id":"r","title":"Soup","servings":1e30}"#),
            row(#"{"id":"r","title":"Future","schemaVersion":999}"#),
            row(#"{"id":"r","name":"Beans","quantity":"one","unit":"bag"}"#, kind: "shopping")
        ]
        XCTAssertThrowsError(try SyncPayloadSafety.validate(invalid, owner: "a")) {
            XCTAssertEqual($0 as? SyncPayloadSafety.Incompatible, .init(count: invalid.count))
        }
    }
    func testEachNumericOverflowRowFailsClosedWithoutTrapping() {
        for field in ["servings", "timeMinutes"] {
            for literal in ["1e30", "-1e30", "9.223372036854776e18", "-9.223372036854778e18", "1e309"] {
                let payload = "{\"id\":\"r\",\"title\":\"Soup\",\"\(field)\":\(literal)}"
                XCTAssertThrowsError(try SyncPayloadSafety.validate([row(payload)], owner: "a"), "\(field)=\(literal)") {
                    XCTAssertEqual($0 as? SyncPayloadSafety.Incompatible, .init(count: 1))
                }
            }
        }
    }
    func testOnlyEditableDraftsPermitZeroServingsAndNeverZeroTimeOrOverflow() throws {
        var draft = RecipeCard(id: "r", title: "Soup", servings: 0, source: .imported)
        draft.sourceDraft = .init(text: "Soup\nStir beans and serve.", warnings: [], unknownServings: true)
        let encoder = JSONEncoder()
        func validate(_ card: RecipeCard) throws {
            let data = try encoder.encode(card)
            try SyncPayloadSafety.validate([row(String(decoding: data, as: UTF8.self))], owner: "a")
        }
        try validate(draft)
        draft.timeMinutes = 0
        XCTAssertThrowsError(try validate(draft))
        draft.timeMinutes = nil; draft.sourceDraft = nil
        XCTAssertThrowsError(try validate(draft))
        draft.source = .appleIntelligence; draft.suggestionDraft = true
        try validate(draft)
        draft.suggestionDraft = false
        XCTAssertThrowsError(try validate(draft))
        let maliciousDraft = #"{"id":"r","title":"Soup","servings":1e30,"source":"appleIntelligence","suggestionDraft":true}"#
        XCTAssertThrowsError(try SyncPayloadSafety.validate([row(maliciousDraft)], owner: "a"))
    }
    func testRecipeDecoderRejectsOutOfRangeDoublesButKeepsLegacyNumbers() throws {
        let decoder = JSONDecoder()
        for field in ["servings", "timeMinutes"] {
            for literal in ["1e30", "-1e30", "9.223372036854776e18", "-9.223372036854778e18"] {
                let payload = "{\"id\":\"r\",\"title\":\"Soup\",\"\(field)\":\(literal)}"
                XCTAssertThrowsError(try decoder.decode(RecipeCard.self, from: Data(payload.utf8)), "\(field)=\(literal)")
            }
        }
        let fractional = try decoder.decode(RecipeCard.self, from: Data(#"{"servings":2.9,"timeMinutes":4.8}"#.utf8))
        XCTAssertEqual(fractional.servings, 2); XCTAssertEqual(fractional.timeMinutes, 4)
        let bounds = try decoder.decode(RecipeCard.self, from: Data("{\"servings\":\(Int.max),\"timeMinutes\":\(Int.min)}".utf8))
        XCTAssertEqual(bounds.servings, Int.max); XCTAssertEqual(bounds.timeMinutes, Int.min)
        let safeDouble = Double(Int.max).nextDown
        let nearLimit = try decoder.decode(RecipeCard.self, from: Data("{\"servings\":\(safeDouble)}".utf8))
        XCTAssertEqual(nearLimit.servings, Int(safeDouble))
        let missing = try decoder.decode(RecipeCard.self, from: Data("{}".utf8))
        XCTAssertEqual(missing.servings, 2); XCTAssertNil(missing.timeMinutes)
    }
    func testTombstonesNeedNoPayloadButStillRequireCorrectOwnerAndKind() throws {
        try SyncPayloadSafety.validate([row(nil, deleted: true)], owner: "a")
        XCTAssertThrowsError(try SyncPayloadSafety.validate([row(nil, deleted: true)], owner: "b"))
        XCTAssertThrowsError(try SyncPayloadSafety.validate([row(nil, kind: "unknown", deleted: true)], owner: "a"))
    }
    func testRawMergeDemonstratesMalformedRemoteWouldReplaceLocalBytes() {
        let local = Data(#"{"id":"r","title":"Keep me"}"#.utf8)
        let bad = row(#"[]"#)
        let result = SyncMerge.merge(local: .init(data: ["r": local], stamps: ["r": 1], tombstones: [:]), remote: [bad])
        XCTAssertEqual(result.data["r"], bad.data?.raw, "Baseline merge is opaque, preflight must run before it")
        XCTAssertThrowsError(try SyncPayloadSafety.validate([bad], owner: "a"))
    }
}
