import XCTest
@testable import Ate

/// #245 lane 1: AppStore's ordinary writers enter the bound writer boundary BEFORE
/// mutating (recipes, shopping, cook session, settings, legacy import, local wipe), and
/// async flows re-prove session + epoch after each await before publishing. While the
/// boundary is unbound the dormant legacy graph keeps today's behavior exactly. Boundary
/// mechanics themselves (flock, epoch, nested archive lease) are covered by
/// AccountWriterGateTests and the archive lane tests; here the boundary is an injected
/// spy/refusing closure and the tests assert AppStore's routing and honesty only.
@MainActor
final class AppStoreWriterBoundaryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "AppStoreWriterBoundaryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private enum StubError: Error { case boundaryRefused }

    private func makeStore(auth: AuthService? = nil, sync: SyncService? = nil) -> AppStore {
        AppStore(context: nil, backend: MockBackend(),
                 nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                 nutritionGoalsRepository: NutritionGoalsRepository(defaults: defaults,
                     storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString))),
                 foodJournalRuntime: nil,
                 injectedAuth: auth, injectedSync: sync)
    }

    private func card(_ id: String, _ title: String = "Bean stew") -> RecipeCard {
        RecipeCard(id: id, title: title)
    }

    // MARK: bound boundary is entered before mutating

    func testOrdinaryWritersEnterBoundBoundary() {
        let store = makeStore()
        var entries = 0
        store.journalWriterEffect = { work in entries += 1; try work() }

        store.add(card("r1"))
        XCTAssertEqual(store.recipes.map(\.id), ["r1"])
        let afterAdd = entries
        XCTAssertGreaterThan(afterAdd, 0, "add must enter the bound boundary before mutating")

        var edited = card("r1"); edited.title = "Bean stew reworked"
        store.update(edited)
        XCTAssertGreaterThan(entries, afterAdd, "update must enter the bound boundary")

        store.addManual("Spinach")
        store.toggle(store.shopping[0].id)
        let afterShopping = entries
        XCTAssertTrue(store.shopping[0].done)

        store.beginCookSession(recipeID: "r1", factor: 2)
        XCTAssertNotNil(store.cookSession)
        store.settings.units = .imperial
        XCTAssertGreaterThan(entries, afterShopping, "cook-session and settings writes must enter the bound boundary")
    }

    // MARK: refusal blocks the publish and reports honestly

    func testRefusalBlocksPublishAndShowsHonestFailure() {
        let store = makeStore()
        store.journalWriterEffect = { _ in throw StubError.boundaryRefused }

        store.add(card("r1"))
        XCTAssertTrue(store.recipes.isEmpty, "a refused write must not publish in memory")
        XCTAssertEqual(store.toast?.message, AppStore.ordinaryWriteFailureMessage)
        XCTAssertEqual(store.toast?.isError, true,
                       "the failure copy names the failed action and never claims a rollback")

        store.toast = nil
        store.addManual("Spinach")
        XCTAssertTrue(store.shopping.isEmpty)
        XCTAssertEqual(store.toast?.message, AppStore.ordinaryWriteFailureMessage)

        store.toast = nil
        store.beginCookSession(recipeID: "r1", factor: 1)
        XCTAssertNil(store.cookSession, "a refused cook-session write must not publish")
        XCTAssertEqual(store.toast?.message, AppStore.ordinaryWriteFailureMessage)
    }

    // MARK: throwing writers propagate the refusal through their existing errors

    func testThrowingWritersPropagateBoundaryRefusal() {
        let store = makeStore()
        store.journalWriterEffect = { _ in throw StubError.boundaryRefused }
        let data = try! JSONEncoder().encode([card("r1")])
        XCTAssertThrowsError(try store.importJSON(data)) { error in
            XCTAssertEqual(error as? StubError, .boundaryRefused,
                           "the boundary refusal reaches the import caller, not a fake import error")
        }
        XCTAssertTrue(store.recipes.isEmpty)
    }

    // MARK: dormant graph is byte-for-byte the legacy behavior

    func testDormantGraphRunsUngated() {
        let store = makeStore()   // no bindings: #245 stays dormant
        store.add(card("r1"))
        XCTAssertEqual(store.recipes.map(\.id), ["r1"])
        store.addManual("Spinach")
        XCTAssertEqual(store.shopping.count, 1)
        store.beginCookSession(recipeID: "r1", factor: 2)
        XCTAssertEqual(store.cookSession?.factor, 2)
        store.toggleCookIngredientChecked(0)
        XCTAssertEqual(store.cookSession?.checked, [0])
        XCTAssertNil(store.toast, "no boundary, no boundary failure copy")
    }

    func testDormantLegacyImportStillWorks() throws {
        let store = makeStore()
        let data = try JSONEncoder().encode([card("r1")])
        let summary = try store.importJSON(data)
        XCTAssertEqual(summary.recipesAdded, 1)
        XCTAssertEqual(store.recipes.map(\.id), ["r1"])
    }

    // MARK: constructor binding (boundary present before launch writes)

    func testConstructorBoundBoundarySeesLaunchWrites() {
        var entries = 0
        let effect: ((() throws -> Void) throws -> Void) = { work in entries += 1; try work() }
        let store = AppStore(context: nil, backend: MockBackend(),
                             nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                             nutritionGoalsRepository: NutritionGoalsRepository(defaults: defaults),
                             foodJournalRuntime: nil,
                             journalWriterEffect: effect, journalWriterValidator: {})
        XCTAssertTrue(store.journalWriterEffect != nil,
                      "the constructor binds the boundary itself, not a property set after construction")
        store.add(card("r1"))
        XCTAssertGreaterThan(entries, 0)
    }

    // MARK: post-await publish guard (sync)

    private func signIn(_ store: AppStore) async {
        let error = await store.signIn(email: "lane1@example.com", password: "password123")
        XCTAssertNil(error)
    }

    private func seedRemoteRecipe(_ sync: SyncService, session: AuthSession, id: String) async throws {
        let data = try JSONEncoder().encode(card(id, "Remote chakalaka"))
        try await sync.push([SyncRecord(user_id: session.userID, kind: "recipe", id: id,
                                        data: AnyJSON(data), stampMs: 1_790_000_000_000, deleted: false)],
                            session: session)
    }

    func testSyncAbandonsPublishWhenPostAwaitValidationFails() async throws {
        let sync = MockSync()
        let store = makeStore(auth: MockAuth(), sync: sync)
        store.journalWriterEffect = { work in try work() }
        store.journalWriterValidator = {}
        await signIn(store)
        await store.syncNow()   // baseline: ownership persisted, empty server
        guard case .synced = store.syncState else { return XCTFail("baseline sync must succeed") }

        let session = try XCTUnwrap(store.session)
        try await seedRemoteRecipe(sync, session: session, id: "remote-1")

        // The epoch/session proof fails after the pull: the pulled rows must not publish.
        store.journalWriterValidator = { throw StubError.boundaryRefused }
        await store.syncNow()
        XCTAssertFalse(store.recipes.contains { $0.id == "remote-1" },
                       "a stale post-await proof abandons the merge publish")
        guard case .failed(let message) = store.syncState else {
            return XCTFail("an abandoned publish reports an honest sync failure")
        }
        XCTAssertEqual(message, AppStore.syncInterruptedMessage)

        // The next healthy sync merges the same rows honestly; nothing was lost or duplicated.
        store.journalWriterValidator = {}
        await store.syncNow()
        XCTAssertTrue(store.recipes.contains { $0.id == "remote-1" })
    }

    func testSyncMergesNormallyWhileDormant() async throws {
        let sync = MockSync()
        let store = makeStore(auth: MockAuth(), sync: sync)   // no bindings: guard is inert
        await signIn(store)
        await store.syncNow()
        let session = try XCTUnwrap(store.session)
        try await seedRemoteRecipe(sync, session: session, id: "remote-1")
        await store.syncNow()
        XCTAssertTrue(store.recipes.contains { $0.id == "remote-1" },
                      "without a bound boundary the legacy merge publishes exactly as before")
    }
}
