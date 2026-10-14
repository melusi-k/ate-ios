import XCTest
@testable import Ate

/// A-SYNC-02/03 and A-SYNC-06: the same fixtures as scripts/e2e/backend_e2e.py, run against SyncMerge, plus an older-schema store.
final class SyncFixtureTests: XCTestCase {
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        let dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: dir.appendingPathComponent(name))
    }
    private func raw(_ v: Any) -> Data { try! JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) }
    private func obj(_ d: Data) -> NSDictionary { (try? JSONSerialization.jsonObject(with: d)) as? NSDictionary ?? [:] }

    func testMergeFixtures() throws {
        let root = try JSONSerialization.jsonObject(with: fixture("sync_fixtures.json")) as! [String: Any]
        let scenarios = root["scenarios"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(scenarios.count, 7)
        for sc in scenarios {
            let name = sc["name"] as! String
            let l = sc["local"] as! [String: Any]
            let local = SyncMerge.Local(
                data: (l["data"] as! [String: Any]).mapValues { raw($0) },
                stamps: (l["stamps"] as! [String: NSNumber]).mapValues { $0.doubleValue },
                tombstones: (l["tombstones"] as! [String: NSNumber]).mapValues { $0.doubleValue })
            let remote = (sc["remote"] as! [[String: Any]]).map { r in
                SyncRecord(user_id: "u", kind: "recipe", id: r["id"] as! String,
                           data: (r["data"] is NSNull || r["data"] == nil) ? nil : AnyJSON(raw(r["data"]!)),
                           updated_at: (r["updated_at"] as! NSNumber).int64Value, deleted: r["deleted"] as! Bool)
            }
            let res = SyncMerge.merge(local: local, remote: remote)
            let exp = sc["expect"] as! [String: Any]
            let expData = exp["data"] as! [String: Any]
            XCTAssertEqual(Set(res.data.keys), Set(expData.keys), name)
            for (k, v) in expData { XCTAssertEqual(obj(res.data[k] ?? Data()), v as? NSDictionary, "\(name) \(k)") }
            XCTAssertEqual(Set(res.tombstones.keys), Set(exp["tombstones"] as! [String]), name)
            XCTAssertEqual(res.push, exp["push"] as! [String], name)
            XCTAssertEqual(res.pushDeletes, exp["pushDeletes"] as! [String], name)
            // Second sync against what we'd push is a no-op (idempotent duplicate-ID upsert).
            var after = remote.filter { r in !res.push.contains(r.id) && !res.pushDeletes.contains(r.id) }
            for id in res.push { after.append(SyncRecord(user_id: "u", kind: "recipe", id: id, data: AnyJSON(res.data[id]!), stampMs: res.stamps[id]!, deleted: false)) }
            for id in res.pushDeletes { after.append(SyncRecord(user_id: "u", kind: "recipe", id: id, data: nil, stampMs: res.tombstones[id]!, deleted: true)) }
            let again = SyncMerge.merge(local: .init(data: res.data, stamps: res.stamps, tombstones: res.tombstones), remote: after)
            XCTAssertTrue(again.push.isEmpty && again.pushDeletes.isEmpty, "\(name): re-sync not a no-op")
            XCTAssertEqual(again.data.keys.sorted(), res.data.keys.sorted(), name)
        }
    }

    func testOlderSchemaStoreMigrates() throws {
        let root = try JSONSerialization.jsonObject(with: fixture("legacy_v1_store.json")) as! [String: Any]
        let data = try JSONSerialization.data(withJSONObject: root["recipes"]!)
        let cards = try JSONDecoder().decode([RecipeCard].self, from: data)
        XCTAssertEqual(cards.count, 3)
        let mogodu = cards[0]
        XCTAssertEqual(mogodu.servings, 6); XCTAssertEqual(mogodu.timeMinutes, 180)
        XCTAssertEqual(mogodu.source, .unknown); XCTAssertNil(mogodu.origin); XCTAssertNil(mogodu.coverImage)
        XCTAssertNil(mogodu.ingredients[0].notes); XCTAssertNil(mogodu.steps[0].timeSeconds)
        XCTAssertEqual(cards[1].source, .unknown, "unknown future source must not break decoding")
        XCTAssertTrue(cards[1].favorite); XCTAssertEqual(cards[1].servings, 2)
        // Import (same path as restoring an old export) drops empty cards and keeps the rest.
        let imported = RecipeLogic.importCards(cards, into: [])
        XCTAssertEqual(imported.added, 2)
        XCTAssertEqual(Set(imported.result.map(\.id)), ["legacy-1", "legacy-2"])
        // Round-trip in the current schema is lossless.
        let re = try JSONDecoder().decode([RecipeCard].self, from: JSONEncoder().encode(imported.result))
        XCTAssertEqual(re, imported.result)
        // Fractional legacy sync stamps still compare as whole ms (no spurious re-push).
        let sync = root["sync_v1"] as! [String: Any]
        let stamps = (sync["stamps"] as! [String: NSNumber]).mapValues { $0.doubleValue }
        let res = SyncMerge.merge(local: .init(data: ["legacy-1": try JSONEncoder().encode(mogodu)], stamps: stamps,
                                               tombstones: (sync["tombstones"] as! [String: NSNumber]).mapValues { $0.doubleValue }),
                                  remote: [SyncRecord(user_id: "u", kind: "recipe", id: "legacy-1", data: AnyJSON(try JSONEncoder().encode(mogodu)), updated_at: 1700000000000, deleted: false),
                                           SyncRecord(user_id: "u", kind: "recipe", id: "gone", data: nil, updated_at: 1700000000001, deleted: true)])
        XCTAssertTrue(res.push.isEmpty, "\(res.push)"); XCTAssertTrue(res.pushDeletes.isEmpty)
    }

    func testInterruptedPhotoGenerationRestoresImageInput() {
        let defaults = UserDefaults(suiteName: "ate.tests.draft.photo")!
        let store = DraftStore(defaults: defaults, enabled: true)
        store.clear()
        let photo = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])
        store.begin(mode: "Image", text: "", imageData: photo)
        XCTAssertEqual(store.pending?.mode, "Image")
        XCTAssertEqual(store.pending?.imageData, photo, "retry after relaunch must retain the selected photo")
        store.end()
        XCTAssertNil(store.pending)
        store.clear()
    }

    func testLegacyPendingDraftWithoutPhotoStillDecodes() throws {
        let json = Data(#"{"mode":"Image","text":"","startedAt":1700000000}"#.utf8)
        let pending = try JSONDecoder().decode(DraftStore.Pending.self, from: json)
        XCTAssertEqual(pending.mode, "Image")
        XCTAssertNil(pending.imageData, "legacy drafts require a friendly reselect-photo recovery path")
    }

    func testInterruptedGenerationDraftRoundTrip() {
        let store = DraftStore(defaults: UserDefaults(suiteName: "ate.tests.draft")!, enabled: true)
        store.clear()
        store.begin(mode: "Prompt", text: "Mogodu")
        XCTAssertEqual(store.pending?.text, "Mogodu")
        var c = RecipeCard(title: "Mogodu"); c.steps = [Step(order: 1, instruction: "Simmer", timeSeconds: nil)]
        store.saveDraft(c)
        XCTAssertNil(store.pending, "a finished generation is no longer pending")
        XCTAssertEqual(store.draft?.title, "Mogodu")
        store.clear()
        XCTAssertNil(store.draft)
    }
}
