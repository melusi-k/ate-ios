import XCTest
@testable import Ate

/// #245 lane 1: action writers enter the boundary before mutating; direct SwiftUI-bound
/// property edits are intentionally memory-first and gate durability in didSet. Async
/// flows re-prove session + epoch after each await before publishing. While the
/// boundary is unbound the dormant legacy graph keeps today's behavior exactly. Boundary
/// mechanics themselves (flock, epoch, nested archive lease) are covered by
/// AccountWriterGateTests and the archive lane tests; here the boundary is an injected
/// spy/refusing closure and the tests assert AppStore's routing and honesty only.
@MainActor
final class AppStoreWriterBoundaryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    // These legacy AppStore inputs are not covered by nutrition repository injection.
    // Preserve only the keys this graph uses; never erase the host's whole domain.
    private let legacyKeys = ["ate.cookSession.v1", "ate.settings.v1", "ate.timerprefs.v1",
                              "ate.sync.v1", RecipeFilter.key, LibraryLayout.key, AppStore.onboardedKey]
    private var legacyValues: [String: Any] = [:]
    private var savedAuthBytes: Data?
    private var stores: [AppStore] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "AppStoreWriterBoundaryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        legacyValues = [:]
        for key in legacyKeys {
            legacyValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        savedAuthBytes = Keychain.load(account: "session")
        Keychain.save(nil, account: "session")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        // Delayed/unstructured sync from a test must not write restored host state.
        for store in stores {
            store.session = nil
            store.journalWriterEffect = { _ in throw StubError.boundaryRefused }
            store.journalWriterValidator = { throw StubError.boundaryRefused }
        }
        stores = []
        for key in legacyKeys {
            if let value = legacyValues[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        Keychain.save(savedAuthBytes, account: "session")
        savedAuthBytes = nil; legacyValues = [:]
        super.tearDown()
    }

    private enum StubError: Error { case boundaryRefused }

    private func makeStore(auth: AuthService? = nil, sync: SyncService? = nil) -> AppStore {
        let store = AppStore(context: nil, backend: MockBackend(),
                 nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                 nutritionGoalsRepository: NutritionGoalsRepository(defaults: defaults,
                     storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString))),
                 foodJournalRuntime: nil,
                 injectedAuth: auth, injectedSync: sync)
        stores.append(store)
        return store
    }

    private func card(_ id: String, _ title: String = "Bean stew") -> RecipeCard {
        RecipeCard(id: id, title: title,
                   ingredients: [Ingredient(name: "Beans", quantity: 1, unit: "cup")],
                   steps: [Step(order: 1, instruction: "Simmer the beans.")])
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
        XCTAssertNil(store.cookSession, "Refusal fixture must start without a persisted cook")
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
        XCTAssertTrue(store.recipes.isEmpty)
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
        XCTAssertTrue(store.recipes.isEmpty)
        await signIn(store)
        await store.syncNow()
        guard case .synced = store.syncState else { return XCTFail("Isolated dormant baseline sync must succeed") }
        let session = try XCTUnwrap(store.session)
        try await seedRemoteRecipe(sync, session: session, id: "remote-1")
        let remote = try await sync.pull(session: session)
        XCTAssertEqual(remote.map(\.id), ["remote-1"])
        await store.syncNow()
        guard case .synced = store.syncState else { return XCTFail("Dormant sync must publish success") }
        XCTAssertTrue(store.recipes.contains { $0.id == "remote-1" },
                      "without a bound boundary the legacy merge publishes exactly as before")
    }
    func testBoundCookSessionLoadWithoutBytesDoesNotEnterEffect() {
        let store = makeStore()
        var effects = 0
        store.journalWriterEffect = { work in effects += 1; try work() }
        store.loadPersistedCookSession(defaults: defaults)
        XCTAssertEqual(effects, 0)
        XCTAssertNil(store.cookSession)
    }

    func testBoundCookSessionWithIdentityAdoptsWithoutRewritingBytes() throws {
        let store = makeStore()
        let session = CookSession(recipeID: "r1", stepIndex: 1)
        let raw = try JSONEncoder().encode(session)
        defaults.set(raw, forKey: "ate.cookSession.v1")
        var effects = 0
        store.journalWriterEffect = { work in effects += 1; try work() }
        store.loadPersistedCookSession(defaults: defaults)
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(store.cookSession, session)
        XCTAssertEqual(defaults.data(forKey: "ate.cookSession.v1"), raw)
    }

    func testDeniedLegacyCookIdentityUpgradeDoesNotPublishOrChangeBytes() throws {
        let store = makeStore()
        let raw = Data("{\"recipeID\":\"r1\",\"stepIndex\":1,\"factor\":1,\"checked\":[],\"ingredientSignature\":\"\"}".utf8)
        defaults.set(raw, forKey: "ate.cookSession.v1")
        store.journalWriterEffect = { _ in throw StubError.boundaryRefused }
        store.loadPersistedCookSession(defaults: defaults)
        XCTAssertNil(store.cookSession)
        XCTAssertEqual(defaults.data(forKey: "ate.cookSession.v1"), raw)
    }


    private final class AuthSpy: AuthService {
        let base = MockAuth()
        var signOuts = 0
        var deletes = 0
        var refreshes = 0
        func signIn(email: String, password: String) async throws -> AuthSession { base.make(email) }
        func signUp(email: String, password: String) async throws -> AuthSession? { base.make(email) }
        func sendMagicLink(email: String) async throws {}
        func resendConfirmation(email: String) async throws {}
        func recoverPassword(email: String) async throws {}
        func updatePassword(_ session: AuthSession, to password: String) async throws {}
        func refresh(_ session: AuthSession) async throws -> AuthSession {
            refreshes += 1
            var value = session; value.expiresAt = Date().timeIntervalSince1970 + 3600
            return value
        }
        func session(fromCallback url: URL) async throws -> AuthCallback? {
            url.query == "recovery" ? .recovery(base.make("recovery@example.com")) : .signedIn(base.make("callback@example.com"))
        }
        func signOut(_ session: AuthSession) async { signOuts += 1 }
        func deleteAccount(_ session: AuthSession) async throws { deletes += 1 }
    }

    private final class SyncSpy: SyncService {
        var pulls = 0
        var pushes = 0
        func pull(session: AuthSession) async throws -> [SyncRecord] { pulls += 1; return [] }
        func push(_ records: [SyncRecord], session: AuthSession) async throws { pushes += 1 }
    }

    private func refuseSessionPublish(_ store: AppStore, afterWork: Bool,
                                      reached: XCTestExpectation? = nil) {
        var depth = 0
        store.journalWriterValidator = {}
        store.journalWriterEffect = { work in
            if depth > 0 { return try work() }
            depth += 1
            defer { depth -= 1; reached?.fulfill() }
            if afterWork { try work() }
            throw StubError.boundaryRefused
        }
    }

    func testSignInAndSignUpReportDeniedAndPostWorkPublishFailure() async {
        for afterWork in [false, true] {
            let auth = AuthSpy(); let sync = SyncSpy()
            let store = makeStore(auth: auth, sync: sync)
            store.session = nil
            store.pendingConfirmation = "still-pending@example.com"
            refuseSessionPublish(store, afterWork: afterWork)
            let error = await store.signIn(email: "signed-in@example.com", password: "unused")
            XCTAssertEqual(error?.message, AppStore.sessionWriteFailureMessage)
            XCTAssertEqual(store.toast?.isError, true)
            XCTAssertEqual(store.toast?.message, AppStore.sessionWriteFailureMessage)
            XCTAssertEqual(store.pendingConfirmation, "still-pending@example.com")
            XCTAssertEqual(store.session?.email, afterWork ? "signed-in@example.com" : nil,
                           "Post-work failure may have published; no rollback is claimed")
            let outcome = await store.signUp(email: "signed-up@example.com", password: "unused")
            XCTAssertEqual(outcome, .failed(AuthError(message: AppStore.sessionWriteFailureMessage)))
            XCTAssertEqual(store.toast?.message, AppStore.sessionWriteFailureMessage)
            await Task.yield()
            XCTAssertEqual(sync.pulls, 0, "Failed publication must not schedule sync")
            XCTAssertEqual(sync.pushes, 0)
        }
    }

    func testHalfBoundPostAwaitPublicationFailsClosed() async {
        for effectOnly in [true, false] {
            let sync = SyncSpy()
            let store = makeStore(auth: AuthSpy(), sync: sync)
            store.session = nil
            var effects = 0
            if effectOnly { store.journalWriterEffect = { work in effects += 1; try work() } }
            else { store.journalWriterValidator = {} }
            let error = await store.signIn(email: "half@example.com", password: "unused")
            XCTAssertNotNil(error)
            XCTAssertNil(store.session)
            XCTAssertEqual(effects, 0)
            XCTAssertEqual(sync.pulls, 0)
        }
    }

    func testCallbacksDoNotFinishOnDeniedOrPostWorkSessionPublish() async {
        for afterWork in [false, true] {
            for recovery in [false, true] {
                let sync = SyncSpy()
                let store = makeStore(auth: AuthSpy(), sync: sync)
                store.session = nil
                store.showOnboarding = true
                store.authSheet = .signIn
                store.pendingConfirmation = "pending@example.com"
                let reached = expectation(description: "callback session effect")
                refuseSessionPublish(store, afterWork: afterWork, reached: reached)
                store.handle(url: URL(string: "ate://auth-callback" + (recovery ? "?recovery" : ""))!)
                await fulfillment(of: [reached], timeout: 2)
                XCTAssertEqual(store.toast?.message, AppStore.sessionWriteFailureMessage)
                XCTAssertTrue(store.showOnboarding)
                XCTAssertEqual(store.pendingConfirmation, "pending@example.com")
                guard case .signIn? = store.authSheet else { return XCTFail("No auth-sheet completion on refusal") }
                XCTAssertEqual(sync.pulls, 0)
            }
        }
    }

    func testSignOutAndDeleteStopLocalCompletionAfterSessionEffectFailure() async {
        for afterWork in [false, true] {
            for deleting in [false, true] {
                let auth = AuthSpy()
                let store = makeStore(auth: auth)
                let original = auth.base.make("owner@example.com")
                store.session = original
                store.recipes = [card("keep")]
                store.showOnboarding = false
                refuseSessionPublish(store, afterWork: afterWork)
                if deleting {
                    let error = await store.deleteAccount()
                    XCTAssertNotNil(error)
                    XCTAssertTrue(error?.message.contains("deleted on the server") == true)
                    XCTAssertEqual(auth.deletes, 1)
                } else {
                    await store.signOut(removeLocalData: true)
                    XCTAssertEqual(auth.signOuts, 1)
                    XCTAssertTrue(store.toast?.message.contains("Signed out on the server") == true)
                    XCTAssertEqual(store.toast?.isError, true)
                }
                XCTAssertEqual(store.recipes.map(\.id), ["keep"], "No dependent wipe after an unproved session publish")
                XCTAssertFalse(store.showOnboarding)
                XCTAssertEqual(store.session, afterWork ? nil : original)
            }
        }
    }

    func testSyncRefreshStopsBeforePullWhenSessionPublishFails() async {
        for afterWork in [false, true] {
            let auth = AuthSpy(); let sync = SyncSpy()
            let store = makeStore(auth: auth, sync: sync)
            var expired = auth.base.make("owner@example.com"); expired.expiresAt = 0
            store.session = expired
            refuseSessionPublish(store, afterWork: afterWork)
            await store.syncNow()
            XCTAssertEqual(auth.refreshes, 1)
            XCTAssertEqual(sync.pulls, 0)
            XCTAssertEqual(sync.pushes, 0)
            guard case .failed(let message) = store.syncState else { return XCTFail("No synced claim") }
            XCTAssertEqual(message, AppStore.sessionWriteFailureMessage)
            XCTAssertEqual(store.toast?.message, AppStore.sessionWriteFailureMessage)
        }
    }

    func testMemoryFirstBoundPropertiesKeepEditButRefusePersistenceHonestly() {
        let keys = ["ate.settings.v1", "ate.timerprefs.v1", RecipeFilter.key,
                    LibraryLayout.key, "ate.cookSession.v1"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let store = makeStore()
        for key in keys { UserDefaults.standard.set(Data("last durable bytes".utf8), forKey: key) }
        store.journalWriterEffect = { _ in throw StubError.boundaryRefused }
        store.settings.units = .imperial
        XCTAssertEqual(store.settings.units, .imperial)
        XCTAssertEqual(store.toast?.message, AppStore.ordinaryWriteFailureMessage)
        store.timerPrefs.sound = false
        XCTAssertFalse(store.timerPrefs.sound)
        store.filter.favouritesOnly = true
        XCTAssertTrue(store.filter.favouritesOnly)
        store.layout.sort = .az
        XCTAssertEqual(store.layout.sort, .az)
        store.cookSession = CookSession(recipeID: "memory-only", stepIndex: 2)
        XCTAssertEqual(store.cookSession?.recipeID, "memory-only")
        XCTAssertEqual(store.toast?.isError, true)
        for key in keys {
            XCTAssertEqual(UserDefaults.standard.data(forKey: key), Data("last durable bytes".utf8),
                           "Memory-first editing does not claim durable persistence")
        }
    }

}
