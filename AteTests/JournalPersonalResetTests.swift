import XCTest
@testable import Ate

/// Actual user-action entry points with isolated defaults, Journal container and files.
/// These are executable native tests, not a claim that native execution passed.
@MainActor
final class JournalPersonalResetTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var root: URL!
    private var stores: [AppStore] = []
    private enum Refused: Error { case writer }

    override func setUpWithError() throws {
        suite = "JournalPersonalResetTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() {
        for store in stores {
            store.session = nil
            store.journalWriterEffect = { _ in throw Refused.writer }
            store.journalWriterValidator = { throw Refused.writer }
        }
        stores = []
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }
    private func makeStore(unified: Bool = false, auth: AuthService = MockAuth()) -> AppStore {
        let journal = JournalStore(inMemory: true)
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")))
        let runtime = unified ? FoodJournalRuntime(journal: journal, goalsRepository: goals, defaults: defaults) : nil
        let store = AppStore(context: nil, backend: MockBackend(),
            nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults), nutritionGoalsRepository: goals,
            foodJournalRuntime: runtime, journalStoreOverride: journal,
            injectedAuth: auth,
            cookPlanNotifications: CookPlanNotifications(client: CookPlanFakeNotificationClient()))
        store.saveSessionCredentials = { _ in true }
        store.session = nil
        store.meta = SyncMeta()
        store.journalPersonalResetInventory = JournalLocalReset(journal: journal, defaults: defaults,
            goalsStorage: goals.storage, mediaDirectory: root.appendingPathComponent("media"),
            migrationBackupDirectory: root.appendingPathComponent("legacy"),
            repairBackupDirectory: root.appendingPathComponent("corrupt"),
            preservationDirectory: root.appendingPathComponent("preservation"),
            storeFileURL: root.appendingPathComponent("Journal.store"))
        if unified { store.journalWriterEffect = { try $0() }; store.journalWriterValidator = {} }
        stores.append(store)
        return store
    }
    private func seed(_ store: AppStore) throws {
        _ = try store.journalStore.saveManual(text: "Synthetic account-private reflection")
        let meal = NutritionDiaryEntry(foodName: "Synthetic meal", date: .now, meal: .lunch,
            quantity: 1, quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: 400, proteinGrams: nil,
                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        try NutritionDiaryRepository(defaults: defaults).save([meal])
        try FoodJournalStore(container: store.journalStore.container).saveMeal(meal)
        defaults.set(Data("synthetic".utf8), forKey: "insights.lifecycle.v1.account.test")
        defaults.set("keep", forKey: "unrelated-preference")
        for name in ["media", "legacy", "corrupt", "preservation"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("synthetic private bytes".utf8).write(to: directory.appendingPathComponent("sample"))
        }
        store.manualJournalDraft = "Unsaved synthetic draft"
        store.journalReflection.text = "Unsaved reflection"
        store.manualJournalHost = .root
        store.recipes = [RecipeCard(id: "keep-recipe", title: "Test stew")]
    }
    private func assertEmpty(_ store: AppStore, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try store.journalStore.readEntries().isEmpty, file: file, line: line)
        XCTAssertTrue(try FoodJournalStore(container: store.journalStore.container).readMeals().isEmpty, file: file, line: line)
        XCTAssertTrue(NutritionDiaryRepository(defaults: defaults).load().isEmpty, file: file, line: line)
        XCTAssertNil(defaults.object(forKey: "insights.lifecycle.v1.account.test"), file: file, line: line)
        for name in ["media", "legacy", "corrupt", "preservation"] {
            let path = root.appendingPathComponent(name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.appendingPathComponent("sample").path), file: file, line: line)
        }
        XCTAssertEqual(store.manualJournalDraft, "", file: file, line: line)
        XCTAssertEqual(store.journalReflection.text, "", file: file, line: line)
        XCTAssertNil(store.manualJournalHost, file: file, line: line)
        XCTAssertGreaterThan(store.journalRevision, 0, file: file, line: line)
        XCTAssertEqual(defaults.string(forKey: "unrelated-preference"), "keep", file: file, line: line)
    }
    func testSettingsClearAllErasesLegacyActualOwnerAndPersonalFiles() async throws {
        let store = makeStore(); try seed(store)
        let cleared = await store.clearLibrary()
        XCTAssertTrue(cleared); try assertEmpty(store); XCTAssertTrue(store.recipes.isEmpty)
    }
    func testSettingsClearAllErasesBoundActualOwnerNotAnotherContainer() async throws {
        let other = JournalStore(inMemory: true)
        _ = try other.saveManual(text: "Unrelated container")
        let store = makeStore(unified: true); try seed(store)
        store.journalCookingHistory.record(recipeID: "test-cook")
        let cleared = await store.clearLibrary()
        XCTAssertTrue(cleared); try assertEmpty(store)
        XCTAssertTrue(store.journalCookingHistory.events.isEmpty)
        XCTAssertEqual(try other.readEntries().count, 1)
    }
    func testExplicitSignOutKeepRecipesStillErasesJournal() async throws {
        let store = makeStore(); try seed(store)
        store.session = MockAuth().make("first@example.com")
        await store.signOut(removeLocalData: false)
        XCTAssertNil(store.session); try assertEmpty(store)
        XCTAssertEqual(store.recipes.map(\.id), ["keep-recipe"])
    }
    func testSwitchToDifferentAccountErasesBeforePublishingNewIdentity() async throws {
        let store = makeStore(); try seed(store)
        store.session = MockAuth().make("first@example.com")
        store.meta.userID = store.session?.userID
        var checkedAtCredentialWrite = false
        store.saveSessionCredentials = { data in
            guard data != nil else { return true }
            checkedAtCredentialWrite = (try? store.journalStore.readEntries().isEmpty) == true
            return checkedAtCredentialWrite
        }
        let error = await store.signIn(email: "second@example.com", password: "password123")
        XCTAssertNil(error); XCTAssertTrue(checkedAtCredentialWrite)
        XCTAssertEqual(store.session?.email, "second@example.com"); try assertEmpty(store)
    }
    func testDifferentAccountAfterExpiryWithoutCompletedSyncStillErasesJournal() async throws {
        let store = makeStore()
        let firstError = await store.signIn(email: "first@example.com", password: "password123")
        XCTAssertNil(firstError)
        try seed(store)
        store.meta = SyncMeta() // No completed sync has ever recorded an owner.
        store.expireSession()
        XCTAssertEqual(try store.journalStore.readEntries().count, 2)
        let error = await store.signIn(email: "second@example.com", password: "password123")
        XCTAssertNil(error); XCTAssertEqual(store.session?.email, "second@example.com")
        try assertEmpty(store)
    }
    func testSameAccountReauthenticationPreservesJournal() async throws {
        let store = makeStore(); try seed(store)
        store.session = MockAuth().make("first@example.com")
        let error = await store.signIn(email: "first@example.com", password: "password123")
        XCTAssertNil(error); XCTAssertEqual(try store.journalStore.readEntries().count, 2)
        XCTAssertEqual(NutritionDiaryRepository(defaults: defaults).load().count, 1)
        XCTAssertEqual(store.journalRevision, 0)
    }
    func testExpiryPreservesJournalMealsFilesAndDrafts() throws {
        let store = makeStore(); try seed(store)
        store.session = MockAuth().make("first@example.com")
        store.expireSession()
        XCTAssertNil(store.session); XCTAssertTrue(store.sessionExpired)
        XCTAssertEqual(try store.journalStore.readEntries().count, 2)
        XCTAssertEqual(NutritionDiaryRepository(defaults: defaults).load().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("media/sample").path))
        XCTAssertEqual(store.manualJournalDraft, "Unsaved synthetic draft")
        XCTAssertEqual(store.journalRevision, 0)
    }
    func testNilSessionDoesNotInventExpiry() {
        let store = makeStore(); store.expireSession()
        XCTAssertFalse(store.sessionExpired)
    }
    func testRefusedWriterDoesNotEraseJournalOrPublishNewIdentity() async throws {
        let store = makeStore(unified: true); try seed(store)
        store.session = MockAuth().make("first@example.com")
        store.journalWriterEffect = { _ in throw Refused.writer }
        store.journalWriterValidator = { throw Refused.writer }
        let cleared = await store.clearLibrary()
        XCTAssertFalse(cleared)
        let error = await store.signIn(email: "second@example.com", password: "password123")
        XCTAssertNotNil(error); XCTAssertEqual(store.session?.email, "first@example.com")
        XCTAssertEqual(try store.journalStore.readEntries().count, 2)
        XCTAssertEqual(store.journalRevision, 0)
    }
    func testStaleSignOutCannotEraseNewAccountsJournalInLegacyGraph() async throws {
        let auth = JournalResetSuspendedAuth()
        let store = makeStore(auth: auth)
        store.session = MockAuth().make("first@example.com")
        let task = Task { await store.signOut(removeLocalData: false) }
        await auth.waitUntilSignOutEntered()
        defer { auth.releaseSignOut() }
        store.session = MockAuth().make("second@example.com")
        try seed(store)
        auth.releaseSignOut()
        await task.value
        XCTAssertEqual(store.session?.email, "second@example.com")
        XCTAssertEqual(try store.journalStore.readEntries().count, 2)
        XCTAssertEqual(store.manualJournalDraft, "Unsaved synthetic draft")
        XCTAssertEqual(store.journalRevision, 0)
    }
    func testPartialEraseCannotClaimSuccessOrSwitchAccount() async throws {
        let store = makeStore(); try seed(store)
        store.session = MockAuth().make("first@example.com")
        // A non-directory at the trusted media directory fails closed.
        let media = root.appendingPathComponent("media")
        try FileManager.default.removeItem(at: media)
        try Data("blocked".utf8).write(to: media)
        let error = await store.signIn(email: "second@example.com", password: "password123")
        XCTAssertNotNil(error); XCTAssertEqual(store.session?.email, "first@example.com")
        XCTAssertGreaterThan(store.journalRevision, 0, "Partial deletion must invalidate stale UI too")
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))
    }
}

@MainActor
private final class JournalResetSuspendedAuth: AuthService {
    private let base = MockAuth()
    private var gate: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func waitUntilSignOutEntered() async {
        if gate != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func releaseSignOut() { gate?.resume(); gate = nil }
    func signOut(_ session: AuthSession) async {
        await withCheckedContinuation { continuation in
            gate = continuation
            entered?.resume(); entered = nil
        }
    }
    func signUp(email: String, password: String) async throws -> AuthSession? { try await base.signUp(email: email, password: password) }
    func signIn(email: String, password: String) async throws -> AuthSession { try await base.signIn(email: email, password: password) }
    func sendMagicLink(email: String) async throws { try await base.sendMagicLink(email: email) }
    func resendConfirmation(email: String) async throws { try await base.resendConfirmation(email: email) }
    func recoverPassword(email: String) async throws { try await base.recoverPassword(email: email) }
    func updatePassword(_ session: AuthSession, to password: String) async throws { try await base.updatePassword(session, to: password) }
    func refresh(_ session: AuthSession) async throws -> AuthSession { try await base.refresh(session) }
    func session(fromCallback url: URL) async throws -> AuthCallback? { try await base.session(fromCallback: url) }
    func deleteAccount(_ session: AuthSession) async throws { try await base.deleteAccount(session) }
}
