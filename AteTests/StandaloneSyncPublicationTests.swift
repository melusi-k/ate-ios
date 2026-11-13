import XCTest
@testable import Ate

/// AppStore refusal/revision path, native UNRUN. Context nil deliberately proves
/// failure paths without a persistence-success claim. No real account/network.
@MainActor
final class StandaloneSyncPublicationTests: XCTestCase {
    private let session = AuthSession(accessToken: "fixture", refreshToken: "fixture",
        expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.test")
    private func directory() throws -> URL {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let dir = requested.resolvingSymlinksInPath().standardizedFileURL
        let gate = try AccountWriterGate(directory: dir, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) {
            try AccountGenerationReceiptStore(directory: dir).save(.init(ownerID: session.userID, generation: 0))
        }
        return dir
    }
    private func response(_ body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://fixture.invalid")!, statusCode: status,
            httpVersion: nil, headerFields: nil)!)
    }
    private func store(_ dir: URL, perform: @escaping AccountDataResetService.Perform) throws -> AppStore {
        let service = try RecipeShoppingSyncOwner(controlDirectory: dir,
            rpc: AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: perform),
            session: session, currentSession: { self.session })
        let store = AppStore(context: nil, backend: MockBackend(), injectedAuth: MockAuth(), injectedSync: service)
        store.session = nil // seed local pending state without scheduled network tasks
        return store
    }
    func testPushRefusalRetainsActualPendingRecipeShoppingAndTombstones() async throws {
        let previous = UserDefaults.standard.data(forKey: "ate.sync.v1")
        UserDefaults.standard.removeObject(forKey: "ate.sync.v1")
        defer { UserDefaults.standard.set(previous, forKey: "ate.sync.v1") }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var calls = 0
        let store = try store(dir) { _ in
            calls += 1
            return calls == 1 ? self.response(#"{"generation":0,"rows":[]}"#)
                : self.response(#"{"code":"PT409"}"#, status: 409)
        }
        store.add(RecipeCard(id: "deleted", title: "Delete"))
        store.recipes = []; store.persistRecipes() // actual tombstone bookkeeping
        store.add(RecipeCard(id: "pending", title: "Keep pending"))
        store.shopping = [ShoppingItem(id: "deleted", name: "Delete", quantity: 1, unit: "g")]
        store.persistShopping(); store.shopping = []; store.persistShopping()
        store.shopping = [ShoppingItem(id: "pending", name: "Keep", quantity: 1, unit: "g")]
        store.persistShopping()
        let recipes = store.recipes, shopping = store.shopping
        let metadata = UserDefaults.standard.data(forKey: "ate.sync.v1")
        store.session = session
        await store.syncNow()
        XCTAssertEqual(store.recipes, recipes); XCTAssertEqual(store.shopping, shopping)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "ate.sync.v1"), metadata)
        XCTAssertEqual(store.session, session)
        guard case .failed = store.syncState else { return XCTFail("refusal reported success") }
        XCTAssertEqual(calls, 2, "no retry or remaining puts after first stale refusal")
    }
    func testLateSuccessfulUploadCannotOverwriteNewerLocalEditOrReportSynced() async throws {
        let previous = UserDefaults.standard.data(forKey: "ate.sync.v1")
        UserDefaults.standard.removeObject(forKey: "ate.sync.v1")
        defer { UserDefaults.standard.set(previous, forKey: "ate.sync.v1") }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var responseContinuation: CheckedContinuation<(Data, URLResponse), Never>?
        var started: CheckedContinuation<Void, Never>?
        var didStart = false, calls = 0
        let store = try store(dir) { _ in
            calls += 1
            if calls == 1 { return self.response(#"{"generation":0,"rows":[]}"#) }
            return await withCheckedContinuation { continuation in
                responseContinuation = continuation; didStart = true; started?.resume(); started = nil
            }
        }
        store.add(RecipeCard(id: "pending", title: "Before")); store.session = session
        let task = Task { await store.syncNow() }
        if !didStart { await withCheckedContinuation { started = $0 } }
        store.session = nil
        var changed = store.recipes[0]; changed.title = "Newer local edit"
        store.update(changed)
        let metadata = UserDefaults.standard.data(forKey: "ate.sync.v1")
        store.session = session
        responseContinuation?.resume(returning: response("null"))
        await task.value
        XCTAssertEqual(store.recipes[0].title, "Newer local edit")
        XCTAssertEqual(UserDefaults.standard.data(forKey: "ate.sync.v1"), metadata)
        guard case .failed = store.syncState else { return XCTFail("stale completion reported synced") }
        XCTAssertEqual(calls, 2)
    }
}
