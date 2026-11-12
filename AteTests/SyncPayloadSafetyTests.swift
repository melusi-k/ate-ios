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
