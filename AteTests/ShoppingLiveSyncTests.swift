import XCTest
@testable import Ate

final class ShoppingLiveSyncTests: XCTestCase {
    func testSameMillisecondShoppingConvergesToServerWinner() {
        let local = Data(#"{"name":"local"}"#.utf8)
        let server = Data(#"{"name":"server"}"#.utf8)
        let remote = SyncRecord(user_id: "u", kind: "shopping", id: "item", data: AnyJSON(server), updated_at: 10, deleted: false)
        let result = SyncMerge.merge(local: .init(data: ["item": local], stamps: ["item": 10], tombstones: [:]), remote: [remote])
        XCTAssertEqual(result.data["item"], server)
        XCTAssertTrue(result.push.isEmpty)
        let second = SyncMerge.merge(local: .init(data: result.data, stamps: result.stamps, tombstones: result.tombstones), remote: [remote])
        XCTAssertEqual(second.data, result.data)
        XCTAssertTrue(second.push.isEmpty)
    }
    func testEqualServerTombstonePreventsResurrection() {
        let remote = SyncRecord(user_id: "u", kind: "shopping", id: "item", data: nil, updated_at: 10, deleted: true)
        let result = SyncMerge.merge(local: .init(data: ["item": Data("local".utf8)], stamps: ["item": 10], tombstones: [:]), remote: [remote])
        XCTAssertNil(result.data["item"])
        XCTAssertEqual(result.tombstones["item"], 10)
        XCTAssertTrue(result.push.isEmpty)
    }
    func testEqualUnsentDeleteConvergesToExistingServerItem() {
        let remote = SyncRecord(user_id: "u", kind: "shopping", id: "item", data: AnyJSON(Data("server".utf8)), updated_at: 10, deleted: false)
        let result = SyncMerge.merge(local: .init(data: [:], stamps: [:], tombstones: ["item": 10]), remote: [remote])
        XCTAssertNotNil(result.data["item"])
        XCTAssertNil(result.tombstones["item"])
        XCTAssertTrue(result.pushDeletes.isEmpty)
    }
    func testNewerLocalShoppingRemainsQueuedAndOlderRemoteCannotEraseIt() {
        let local = Data("new".utf8)
        let remote = SyncRecord(user_id: "u", kind: "shopping", id: "item", data: nil, updated_at: 10, deleted: true)
        let result = SyncMerge.merge(local: .init(data: ["item": local], stamps: ["item": 11], tombstones: [:]), remote: [remote])
        XCTAssertEqual(result.data["item"], local)
        XCTAssertEqual(result.push, ["item"])
    }
    func testRecipeEqualTimestampContractUnchanged() {
        let remote = SyncRecord(user_id: "u", kind: "recipe", id: "r", data: AnyJSON(Data("server".utf8)), updated_at: 10, deleted: false)
        let local = Data("local".utf8)
        let result = SyncMerge.merge(local: .init(data: ["r": local], stamps: ["r": 10], tombstones: [:]), remote: [remote])
        XCTAssertEqual(result.data["r"], local)
    }
    func testLocalEditClockNeverRepeatsOrGoesBackwards() {
        XCTAssertEqual(ShoppingSyncCadence.nextStamp(now: 10, prior: 10), 11)
        XCTAssertEqual(ShoppingSyncCadence.nextStamp(now: 8, prior: 11), 12)
        XCTAssertEqual(ShoppingSyncCadence.nextStamp(now: 20, prior: 11), 20)
    }
    func testVisibleSyncBackoffIsBounded() {
        XCTAssertEqual(ShoppingSyncCadence.seconds(consecutiveFailures: 0), 30)
        XCTAssertEqual(ShoppingSyncCadence.seconds(consecutiveFailures: 1), 60)
        XCTAssertEqual(ShoppingSyncCadence.seconds(consecutiveFailures: 2), 120)
        XCTAssertEqual(ShoppingSyncCadence.seconds(consecutiveFailures: 100), 300)
    }
}

@MainActor
final class ShoppingSyncLifecycleTests: XCTestCase {
    private final class ControlledSync: SyncService {
        var pulls = 0
        var pushes = 0
        var pushed: [SyncRecord] = []
        var duringPull: (() async -> Void)?
        var rows: [SyncRecord] = []
        var failure: Error?
        func pull(session: AuthSession) async throws -> [SyncRecord] {
            pulls += 1
            let action = duringPull; duringPull = nil
            await action?()
            if let failure { throw failure }
            return rows
        }
        func push(_ records: [SyncRecord], session: AuthSession) async throws { pushes += 1; pushed = records }
    }
    private var savedMeta: Data?
    private var savedSession: Data?
    private var stores: [AppStore] = []
    override func setUp() {
        savedMeta = UserDefaults.standard.data(forKey: "ate.sync.v1")
        savedSession = Keychain.load(account: "session")
        UserDefaults.standard.removeObject(forKey: "ate.sync.v1")
        Keychain.save(nil, account: "session")
    }
    override func tearDown() {
        // A scheduled post-busy reconciliation must not touch restored host data.
        for store in stores { store.session = nil }
        stores = []
        UserDefaults.standard.set(savedMeta, forKey: "ate.sync.v1")
        Keychain.save(savedSession, account: "session")
    }
    private func make(_ transport: ControlledSync) -> AppStore {
        let store = AppStore(context: nil, backend: MockBackend(), injectedAuth: MockAuth(), injectedSync: transport)
        store.session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000, userID: "owner-a", email: "a@example.test")
        stores.append(store)
        return store
    }
    func testIncompatibleReceiptPreservesBothDomainsAndMetadataWithoutPush() async throws {
        let transport = ControlledSync()
        let store = make(transport)
        let recipe = RecipeCard(id: "recipe-local", title: "Keep soup")
        let item = ShoppingItem(id: "shopping-local", name: "Beans", quantity: 1, unit: "bag")
        store.recipes = [recipe]; store.shopping = [item]
        // A valid deletion plus a malformed update must not partially apply.
        transport.rows = [
            SyncRecord(user_id: "owner-a", kind: "recipe", id: recipe.id, data: nil, updated_at: 9_000_000_000_000, deleted: true),
            SyncRecord(user_id: "owner-a", kind: "shopping", id: item.id, data: AnyJSON(Data("[]".utf8)), updated_at: 9_000_000_000_000, deleted: false)
        ]
        var before: Data?
        transport.duringPull = { before = UserDefaults.standard.data(forKey: "ate.sync.v1") }
        await store.syncNow()
        XCTAssertEqual(store.recipes, [recipe]); XCTAssertEqual(store.shopping, [item])
        XCTAssertEqual(UserDefaults.standard.data(forKey: "ate.sync.v1"), before)
        XCTAssertEqual(transport.pushes, 0)
        guard case .failed(let message) = store.syncState else { return XCTFail("Must surface incompatible count") }
        XCTAssertTrue(message.contains("1 incompatible server row"))
    }
    func testOfflineServerFailureAndCancelledPullPreserveLocalData() async {
        for failure in [URLError(.notConnectedToInternet) as Error, SyncError.http(503, "Unavailable"), CancellationError()] {
            let transport = ControlledSync()
            let store = make(transport)
            let recipe = RecipeCard(id: "r", title: "Local soup")
            let item = ShoppingItem(id: "s", name: "Beans", quantity: 1, unit: "bag")
            store.recipes = [recipe]; store.shopping = [item]
            transport.failure = failure
            await store.syncNow()
            XCTAssertEqual(store.recipes, [recipe]); XCTAssertEqual(store.shopping, [item])
            XCTAssertEqual(transport.pushes, 0)
            guard case .failed = store.syncState else { return XCTFail("Failure must not claim synced") }
            store.session = nil
        }
    }
    func testReentrantRequestDoesNotStartOverlappingPull() async {
        let transport = ControlledSync()
        let tested = make(transport)
        transport.duringPull = { await tested.syncNow() }
        await tested.syncNow()
        XCTAssertEqual(transport.pulls, 1, "Request during pull must queue, not recursively overlap")
        XCTAssertEqual(transport.pushes, 1)
    }
    func testLocalAdditionDuringPullIsIncludedRatherThanOverwritten() async {
        let transport = ControlledSync()
        let store = make(transport)
        store.shopping = []
        transport.duringPull = {
            store.shopping.append(ShoppingItem(id: "during-await", name: "Beans", quantity: 1, unit: "bag"))
        }
        await store.syncNow(reconcileShoppingPush: false)
        XCTAssertEqual(store.shopping.map(\.id), ["during-await"])
        XCTAssertTrue(transport.pushed.contains { $0.kind == "shopping" && $0.id == "during-await" && !$0.deleted })
    }
    func testOldOwnerUnauthorizedResponseCannotExpireNewSession() async {
        let transport = ControlledSync()
        let store = make(transport)
        transport.failure = SyncError.unauthorized
        transport.duringPull = { store.session?.userID = "owner-b" }
        await store.syncNow()
        XCTAssertEqual(store.session?.userID, "owner-b")
        XCTAssertEqual(transport.pushes, 0)
    }
    func testOwnerChangeDuringPullCannotPublishPreviousOwnerShopping() async throws {
        let transport = ControlledSync()
        let store = make(transport)
        store.shopping = [ShoppingItem(id: "retained", name: "Beans", quantity: 1, unit: "bag")]
        let remote = ShoppingItem(id: "remote-a", name: "Private A", quantity: 1, unit: "bag")
        transport.rows = [SyncRecord(user_id: "owner-a", kind: "shopping", id: remote.id,
                                    data: AnyJSON(try JSONEncoder().encode(remote)), updated_at: 10, deleted: false)]
        transport.duringPull = { store.session?.userID = "owner-b" }
        await store.syncNow()
        XCTAssertEqual(store.shopping.map(\.id), ["retained"])
        XCTAssertEqual(transport.pushes, 0)
        guard case .failed = store.syncState else { return XCTFail("Interrupted owner must not report synced") }
    }
}
