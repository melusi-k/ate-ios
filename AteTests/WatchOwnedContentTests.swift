import XCTest
@testable import Ate

final class WatchOwnedContentTests: XCTestCase {
    private func session(_ owner: String, token: String = "token") -> WatchBridgePayload.Session {
        .init(accessToken: token, refreshToken: "refresh", expiresAt: 4_102_444_800, userID: owner, email: "fixture@example.invalid")
    }
    private func snapshot(_ owner: String, generation: Int64 = 4) throws -> WatchAccountSnapshot {
        let json = """
        {"generation":\(generation),"rows":[
          {"user_id":"\(owner)","kind":"recipe","id":"recipe","data":{"id":"recipe","title":"Saved recipe"},"updated_at":12,"deleted":false},
          {"user_id":"\(owner)","kind":"shopping","id":"item","data":{"id":"item","name":"Eggs","done":false},"updated_at":12,"deleted":false}
        ]}
        """
        return try WatchAccountSnapshot.decode(Data(json.utf8), ownerID: owner)
    }
    private func fixture(_ run: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try run(root.appendingPathComponent("watch-cache.json"))
    }
    func testOwnerSwitchClearsMemoryAndDiskBeforeFailedRefreshAndRestart() throws {
        try fixture { url in
            let a = session("A"), b = session("B")
            var content = WatchOwnedContent(session: a, cacheURL: url)
            try content.publish(snapshot("A"), session: a, cacheURL: url)
            XCTAssertFalse(content.shopping.isEmpty)
            XCTAssertFalse(content.recipes.isEmpty)
            let bytesA = try Data(contentsOf: url)
            // B receiving A's file can never display it, even before transition.
            XCTAssertTrue(WatchOwnedContent(session: b, cacheURL: url).shopping.isEmpty)
            try content.transition(to: b, cacheURL: url)
            // No successful B snapshot follows: this is the offline/failure path.
            XCTAssertTrue(content.recipes.isEmpty)
            XCTAssertTrue(content.shopping.isEmpty)
            XCTAssertNil(content.generation)
            let restartB = WatchOwnedContent(session: b, cacheURL: url)
            XCTAssertTrue(restartB.recipes.isEmpty)
            XCTAssertTrue(restartB.shopping.isEmpty)
            XCTAssertNotEqual(try Data(contentsOf: url), bytesA)
            XCTAssertTrue(WatchOwnedContent(session: a, cacheURL: url).shopping.isEmpty)
            // A's late network completion cannot fill B's memory or cache.
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try content.publish(snapshot("A"), session: a, cacheURL: url))
            XCTAssertThrowsError(try content.publish(snapshot("A"), session: b, cacheURL: url))
            XCTAssertEqual(try Data(contentsOf: url), before)
            try content.transition(to: nil, cacheURL: url)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    func testOwnerlessCacheIsNeverDisplayedAndOwnedOfflineRowsCannotAuthorizeToggle() throws {
        try fixture { url in
            try Data(#"{"recipes":[],"shopping":[{"id":"item","name":"Eggs","done":false}]}"#.utf8).write(to: url)
            let a = session("A")
            var content = WatchOwnedContent(session: a, cacheURL: url)
            XCTAssertTrue(content.shopping.isEmpty)
            try content.publish(snapshot("A"), session: a, cacheURL: url)
            var restored = WatchOwnedContent(session: a, cacheURL: url)
            let item = try XCTUnwrap(restored.shopping.first)
            XCTAssertNil(item.snapshotID)
            XCTAssertNil(restored.generation)
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try restored.prepareToggle(item, session: a, nowMs: 100, cacheURL: url))
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }
    func testRetainedItemCannotUseReplacementOwnerOrIdenticalNewSnapshotGeneration() throws {
        try fixture { url in
            let a = session("A"), b = session("B")
            var content = WatchOwnedContent(session: a, cacheURL: url)
            try content.publish(snapshot("A"), session: a, cacheURL: url)
            let retainedA = try XCTUnwrap(content.shopping.first)
            try content.transition(to: b, cacheURL: url)
            try content.publish(snapshot("B"), session: b, cacheURL: url)
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try content.prepareToggle(retainedA, session: b, nowMs: 100, cacheURL: url))
            XCTAssertEqual(try Data(contentsOf: url), before)
            let retainedB = try XCTUnwrap(content.shopping.first)
            // Identical IDs, values and same server generation are insufficient.
            try content.publish(snapshot("B"), session: b, cacheURL: url)
            XCTAssertThrowsError(try content.prepareToggle(retainedB, session: b, nowMs: 100, cacheURL: url))
            let current = try XCTUnwrap(content.shopping.first)
            let capture = try content.prepareToggle(current, session: b, nowMs: 100, cacheURL: url)
            XCTAssertEqual(capture.session, b)
            XCTAssertEqual(capture.generation, 4)
            XCTAssertEqual(capture.row.id, current.id)
            try content.validate(capture, session: b)
            XCTAssertThrowsError(try content.prepareToggle(current, session: b, nowMs: 101, cacheURL: url))
            let rotated = session("B", token: "replacement")
            try content.transition(to: rotated, cacheURL: url)
            XCTAssertThrowsError(try content.validate(capture, session: rotated))
            XCTAssertTrue(content.shopping.isEmpty)
            XCTAssertNil(content.generation)
        }
    }
    func testFailedCacheReplacementStillRevokesOldRowsAndEveryRetainedCapture() throws {
        try fixture { url in
            let a = session("A"), b = session("B")
            var content = WatchOwnedContent(session: a, cacheURL: url)
            try content.publish(snapshot("A"), session: a, cacheURL: url)
            let item = try XCTUnwrap(content.shopping.first)
            let capture = try content.prepareToggle(item, session: a, nowMs: 100, cacheURL: url)
            let invalid = url.appendingPathComponent("missing-parent").appendingPathComponent("cache")
            XCTAssertThrowsError(try content.transition(to: b, cacheURL: invalid))
            XCTAssertTrue(content.recipes.isEmpty)
            XCTAssertTrue(content.shopping.isEmpty)
            XCTAssertNil(content.generation)
            XCTAssertThrowsError(try content.validate(capture, session: b))
            // The old bytes that could not be replaced are still tagged A and
            // cannot leak on a subsequent B launch.
            XCTAssertTrue(WatchOwnedContent(session: b, cacheURL: url).shopping.isEmpty)
        }
    }

}
