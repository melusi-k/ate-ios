import XCTest
@testable import Ate

/// Pure stage fixtures. Native UNRUN; do not certify ordinary launch/persistence.
final class RecipeShoppingSyncStageTests: XCTestCase {
    func testPreparingMergeLeavesPendingEditsAndTombstonesInOriginalValue() throws {
        let card = RecipeCard(id: "pending", title: "Local")
        let item = ShoppingItem(id: "pending", name: "Local", quantity: 1, unit: "g")
        var metadata = RecipeShoppingSyncStage.Metadata()
        metadata.userID = "owner"
        metadata.recipeStamps = ["pending": 5]; metadata.shopStamps = ["pending": 6]
        metadata.recipeTombs = ["deleted": 7]; metadata.shopTombs = ["deleted": 8]
        let before = metadata
        let stage = try RecipeShoppingSyncStage.prepare(recipes: [card], shopping: [item],
            metadata: metadata, remote: [], ownerID: "owner")
        XCTAssertEqual(metadata, before, "proposal cannot consume pending metadata")
        XCTAssertEqual(stage.upload.map(\.kind), ["recipe", "recipe", "shopping", "shopping"])
        XCTAssertEqual(stage.upload.map(\.deleted), [false, true, false, true])
        XCTAssertEqual(stage.upload.map(\.updated_at), [5, 7, 6, 8])
        XCTAssertEqual(stage.upload.map(\.user_id), Array(repeating: "owner", count: 4))
        XCTAssertEqual(stage.recipes, [card]); XCTAssertEqual(stage.shopping, [item])
    }
    func testForeignOwnerNeverBuildsAccountSwitchOrDeletesOriginalLibrary() throws {
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = "old-owner"
        let original = RecipeCard(id: "keep", title: "Keep")
        XCTAssertThrowsError(try RecipeShoppingSyncStage.prepare(recipes: [original], shopping: [],
            metadata: metadata, remote: [], ownerID: "new-owner"))
        XCTAssertEqual(metadata.userID, "old-owner"); XCTAssertEqual(original.id, "keep")
    }
    func testEqualStampServerMergeIsStagedWithoutNewClockStampOrNormalization() throws {
        let local = RecipeCard(id: "same", title: "Local"), server = RecipeCard(id: "same", title: "Server")
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = "owner"
        metadata.recipeStamps = ["same": 5]
        let row = SyncRecord(user_id: "owner", kind: "recipe", id: "same",
            data: AnyJSON(try JSONEncoder().encode(server)), updated_at: 5, deleted: false)
        let stage = try RecipeShoppingSyncStage.prepare(recipes: [local], shopping: [], metadata: metadata,
            remote: [row], ownerID: "owner")
        XCTAssertEqual(stage.recipes, [server]); XCTAssertTrue(stage.upload.isEmpty)
        XCTAssertEqual(local.title, "Local"); XCTAssertEqual(stage.metadata.recipeStamps["same"], 5)
    }
    func testShoppingOrderRetainsExistingAndAppendsNewRemoteIDsDeterministically() throws {
        let local = ShoppingItem(id: "z", name: "Last", quantity: 1, unit: "g")
        let remote = ["b", "a"].map { ShoppingItem(id: $0, name: $0, quantity: 1, unit: "g") }
        let rows = try remote.map { SyncRecord(user_id: "owner", kind: "shopping", id: $0.id,
            data: AnyJSON(try JSONEncoder().encode($0)), updated_at: 1, deleted: false) }
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.shopStamps = ["z": 1]
        let stage = try RecipeShoppingSyncStage.prepare(recipes: [], shopping: [local], metadata: metadata,
            remote: rows, ownerID: "owner")
        XCTAssertEqual(stage.shopping.map(\.id), ["z", "a", "b"])
    }
    func testMissingOrInvalidPendingStampIsRefusedNotInventedFromNow() throws {
        let card = RecipeCard(id: "pending", title: "Keep")
        for stamp in [Double?.none, .some(-1), .some(.infinity), .some(Double(Int64.max))] {
            var metadata = RecipeShoppingSyncStage.Metadata(); metadata.recipeStamps[card.id] = stamp
            XCTAssertThrowsError(try RecipeShoppingSyncStage.prepare(recipes: [card], shopping: [],
                metadata: metadata, remote: [], ownerID: "owner"))
        }
    }
    func testMalformedRemoteIdentityStampPayloadAndDuplicatesRefuseBeforeProposal() throws {
        let valid = SyncRecord(user_id: "owner", kind: "recipe", id: "one",
            data: AnyJSON(try JSONEncoder().encode(RecipeCard(id: "one", title: "One"))), updated_at: 1, deleted: false)
        let badRows: [[SyncRecord]] = [[valid, valid],
            [.init(user_id: "owner", kind: "recipe", id: "one", data: nil, updated_at: 1, deleted: false)],
            [.init(user_id: "owner", kind: "recipe", id: "one", data: valid.data, updated_at: -1, deleted: false)],
            [.init(user_id: "owner", kind: "recipe", id: "different", data: valid.data, updated_at: 1, deleted: false)]]
        for rows in badRows {
            XCTAssertThrowsError(try RecipeShoppingSyncStage.prepare(recipes: [], shopping: [],
                metadata: .init(), remote: rows, ownerID: "owner"))
        }
    }

}
