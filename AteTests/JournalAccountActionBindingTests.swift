import XCTest
@testable import Ate

/// #245 slice B: bound account actions under the unified Journal graph - clear-library,
/// sign-out-remove, delete-account, Settings import/export routing. The legacy paths are
/// covered by DataArchiveTests and friends; these tests pin the runtime-injected behavior.
/// Unified export/import bytes and merge logic belong to A's archive services; here they
/// are injected callbacks, and the tests assert routing and fail-closed refusals only.
@MainActor
final class JournalAccountActionBindingTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "JournalAccountActionBindingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        root = requested.resolvingSymlinksInPath().standardizedFileURL
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        super.tearDown()
    }

    private func goalsRepo() -> NutritionGoalsRepository {
        NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")))
    }

    private func makeRuntime(journal: JournalStore? = nil) -> FoodJournalRuntime {
        FoodJournalRuntime(journal: journal ?? JournalStore(inMemory: true), goalsRepository: goalsRepo(), defaults: defaults,
                           migrationBackupDirectory: root.appendingPathComponent("NutritionDiaryLegacyBackups", isDirectory: true),
                           repairBackupDirectory: root.appendingPathComponent("NutritionDiaryCorruptBackups", isDirectory: true))
    }

    private func makeStore(runtime: FoodJournalRuntime?) -> AppStore {
        AppStore(context: nil, backend: MockBackend(),
                 nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                 nutritionGoalsRepository: goalsRepo(),
                 foodJournalRuntime: runtime,
                 cookPlanNotifications: CookPlanNotifications(client: CookPlanFakeNotificationClient()))
    }

    private func sampleMeal(id: UUID = UUID(), name: String = "Pap and wors") -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: name,
                            date: Date(timeIntervalSince1970: 1_790_000_000), meal: .dinner,
                            quantity: 250, quantityUnit: "g", servings: 1.5, source: .userProvided,
                            sourceName: "Label", sourceIdentifier: "record-42", verificationNote: "cooked",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: 320, proteinGrams: nil,
                                                                   carbohydratesGrams: 40, fatGrams: 8, fibreGrams: nil),
                            dayKey: nil)
    }

    // MARK: journalCookingHistory (central's consumer binding point)

    func testJournalCookingHistoryRoutesToRuntimeWhileInjected() {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        XCTAssertTrue(store.journalCookingHistory === runtime.cookingHistory)
        XCTAssertFalse(store.journalCookingHistory === CookingHistory.shared)
        let legacy = makeStore(runtime: nil)
        XCTAssertTrue(legacy.journalCookingHistory === CookingHistory.shared,
                      "The legacy singleton is the fallback only while the runtime is nil")
    }

    func testDiscoveryHistoryReadsBoundCookIDsAndRetainedTitlesWithoutAWrite() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.settings.onDeviceOnly = false
        runtime.cookingHistory.record(recipeID: "cooked-in-bound-history")
        let now = Date()
        let event = CookCompletionEvent(recipeID: "deleted-cooked", recipeTitle: "Deleted cooked dish",
            completedAt: now, dayKey: runtime.cookingHistory.key(for: now))
        _ = try runtime.cookOutbox.enqueue(event)
        let context = try RecipeDiscovery.context(store: store)
        XCTAssertTrue(context.cookedIDs.contains("cooked-in-bound-history"))
        XCTAssertTrue(context.cookedRecipes.contains(event.recipeSnapshot))
        XCTAssertEqual(try runtime.cookOutbox.load(), [event], "Reading must not acknowledge a cook")
    }

    func testDiscoveryCannotTreatUnreadableBoundHistoryAsNoCookedRecipes() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.settings.onDeviceOnly = false
        defaults.set(Data("unreadable history".utf8), forKey: "ate.cooking.history.v1")
        XCTAssertThrowsError(try RecipeDiscovery.context(store: store))
    }

    func testDiscoveryAddPreservesUnrelatedPendingDraftBytesAndStillUsesWriterBoundary() {
        let store = makeStore(runtime: nil)
        let defaults = UserDefaults.standard
        let pendingKey = "ate.draft.pending.v1", draftKey = "ate.draft.card.v1"
        let previousPending = defaults.object(forKey: pendingKey), previousDraft = defaults.object(forKey: draftKey)
        defer {
            if let previousPending { defaults.set(previousPending, forKey: pendingKey) } else { defaults.removeObject(forKey: pendingKey) }
            if let previousDraft { defaults.set(previousDraft, forKey: draftKey) } else { defaults.removeObject(forKey: draftKey) }
        }
        let pending = Data("unrelated pending input".utf8), draft = Data("unrelated generated draft".utf8)
        defaults.set(pending, forKey: pendingKey); defaults.set(draft, forKey: draftKey)
        let candidate = RecipeCard(id: "discovery-explicit-save", title: "Fruit Bowl")
        store.add(candidate, clearPendingDraft: false)
        XCTAssertEqual(store.recipe(candidate.id)?.title, candidate.title)
        XCTAssertEqual(defaults.data(forKey: pendingKey), pending)
        XCTAssertEqual(defaults.data(forKey: draftKey), draft)
        store.journalWriterEffect = { _ in throw CookCompletionOutboxError.verifyFailed }
        store.add(RecipeCard(id: "refused", title: "Refused suggestion"), clearPendingDraft: false)
        XCTAssertNil(store.recipe("refused"))
        XCTAssertEqual(defaults.data(forKey: pendingKey), pending)
    }

    // MARK: clear-library

    func testClearLibraryUnifiedClearsThroughRuntimeStores() async throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        store.journalWriterValidator = {}
        store.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew")]
        runtime.cookingHistory.record(recipeID: "recipe-1", date: Date(timeIntervalSince1970: 1_790_000_000))
        defaults.set(Data("outbox".utf8), forKey: "ate.cook.completionOutbox.v1")

        _ = await store.clearLibrary()

        XCTAssertTrue(store.recipes.isEmpty)
        XCTAssertFalse(runtime.cookingHistory.cooked(on: Date(timeIntervalSince1970: 1_790_000_000)),
                       "The unified history must be cleared, not only the legacy singleton")
        XCTAssertNil(defaults.object(forKey: "ate.cook.completionOutbox.v1"))
    }

    func testClearLibraryUnifiedRefusesWhileBoundaryUnbound() async {
        let store = makeStore(runtime: makeRuntime())
        store.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew")]
        _ = await store.clearLibrary()
        XCTAssertEqual(store.recipes.map(\.id), ["recipe-1"], "An unbound boundary must refuse the wipe")
        XCTAssertEqual(store.toast?.message, "The unified Journal reset is not ready. Nothing was cleared.")
    }

    func testClearLibraryBoundaryRefusalDoesNotClaimSuccessOrEraseRecipes() async {
        enum Refusal: Error { case denied }
        let store = makeStore(runtime: makeRuntime())
        store.recipes = [RecipeCard(id: "kept", title: "Retained")]
        store.journalWriterEffect = { _ in throw Refusal.denied }
        store.journalWriterValidator = {}
        let cleared = await store.clearLibrary()
        XCTAssertFalse(cleared)
        XCTAssertEqual(store.recipes.map(\.id), ["kept"])
    }

    func testClearLibraryReprovesBoundaryAfterNotificationCleanup() async {
        enum Refusal: Error { case stale }
        let store = makeStore(runtime: makeRuntime())
        store.recipes = [RecipeCard(id: "kept", title: "Retained")]
        store.journalWriterEffect = { work in try work() }
        var validations = 0
        store.journalWriterValidator = {
            validations += 1
            if validations > 1 { throw Refusal.stale }
        }
        let cleared = await store.clearLibrary()
        XCTAssertFalse(cleared)
        XCTAssertEqual(validations, 2)
        XCTAssertEqual(store.recipes.map(\.id), ["kept"])
    }

    // MARK: Settings export

    func testExportUserDataRoutesToInjectedCaptureWhenUnified() async throws {
        let store = makeStore(runtime: makeRuntime())
        let captureBytes = Data("unified-archive-bytes".utf8)
        store.journalArchiveExport = { captureBytes }
        let exported = try await store.exportUserData()
        XCTAssertEqual(exported, captureBytes,
                       "The unified export is exactly what A's capture service produced")
    }

    func testExportUserDataRefusesWithoutInjectedCapture() async {
        let store = makeStore(runtime: makeRuntime())
        do {
            _ = try await store.exportUserData()
            XCTFail("A unified export with no capture callback must refuse")
        } catch {
            XCTAssertTrue(error is CanonicalConsumerBindingError, "got \(error)")
        }
    }

    func testExportUserDataUsesLegacyPathWithoutRuntime() async throws {
        let store = makeStore(runtime: nil)
        let data = try await store.exportUserData()
        let archive = try JSONDecoder().decode(AteDataArchive.self, from: data)
        XCTAssertEqual(archive.format, AteDataArchive.formatName,
                       "The legacy graph keeps today's legacy export")
    }

    func testSyncExportJSONRefusesWhileUnifiedEvenWithCaptureBound() {
        let store = makeStore(runtime: makeRuntime())
        store.journalArchiveExport = { Data("unified".utf8) }
        XCTAssertThrowsError(try store.exportJSON()) { error in
            XCTAssertTrue(error is CanonicalConsumerBindingError,
                          "The sync export must refuse under the unified graph, never fall back to v1; got \(error)")
        }
    }

    // MARK: Settings import

    func testImportUnifiedRoutesToInjectedSession() throws {
        let store = makeStore(runtime: makeRuntime())
        let bytes = Data("archive-bytes".utf8)
        var received: Data?
        store.journalArchiveImport = { data in
            received = data
            return DataImportSummary(recipesAdded: 2)
        }
        let summary = try store.importJSON(bytes)
        XCTAssertEqual(received, bytes, "The whole file goes to A's standalone import session")
        XCTAssertEqual(summary.recipesAdded, 2, "The session's summary is returned verbatim")
    }

    func testImportUnifiedRefusesWithoutInjectedSession() {
        let store = makeStore(runtime: makeRuntime())
        XCTAssertThrowsError(try store.importJSON(Data("archive-bytes".utf8))) { error in
            XCTAssertTrue(error is CanonicalConsumerBindingError, "got \(error)")
        }
    }

    // MARK: wipe (sign-out-remove / delete-account)

    func testWipeUnifiedErasesJournalAndPreservesLifecycleMarkers() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        var effectCalls = 0
        var generation = 0
        var depth = 0
        var nestedCalls = 0
        var validatorCalls = 0
        // Honest reentrant boundary spy: nested persistence shares the outer effect.
        store.journalWriterEffect = { work in
            if depth > 0 { nestedCalls += 1; return try work() }
            effectCalls += 1
            depth += 1
            defer { depth -= 1 }
            try work()
            generation += 1
        }
        store.journalWriterValidator = { validatorCalls += 1 }
        try runtime.coordinator.saveMeal(sampleMeal())
        defaults.set(Data("legacy diary".utf8), forKey: "ate.nutritionDiary.v1")
        defaults.set(true, forKey: "ate.foodJournal.diaryMigration.v1")

        let report = store.wipeLocalDataUnified()

        XCTAssertTrue(report.complete, "failures: \(report.failures)")
        XCTAssertEqual(try runtime.readMeals(), [])
        XCTAssertNil(defaults.object(forKey: "ate.nutritionDiary.v1"))
        XCTAssertNotNil(defaults.object(forKey: "ate.foodJournal.diaryMigration.v1"),
                        "Migration markers are non-personal control state and must survive a wipe")
        XCTAssertEqual(effectCalls, 1, "The wipe is ONE covered effect, not one per component")
        XCTAssertEqual(generation, 1, "The complete nested wipe advances exactly one generation")
        XCTAssertGreaterThan(nestedCalls, 0, "Nested clear/persist calls must share the active effect")
        XCTAssertEqual(depth, 0, "The outer effect is released after completion")
        XCTAssertGreaterThan(validatorCalls, 0,
                             "Per-component re-proof uses the validator, never an empty effect")
    }

    func testWipeUnifiedReportsFailureInsteadOfClaimingSuccess() {
        let runtime = makeRuntime(journal: JournalStore(container: nil, openState: .ok))
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        store.journalWriterValidator = { }
        let report = store.wipeLocalDataUnified()
        XCTAssertFalse(report.complete, "A nil container in a durable state is a failure, never an empty store")
        XCTAssertTrue(report.failures.contains { $0.component == "journal-rows-payloads" })
    }

    func testWipeUnifiedFailsClosedWithoutValidator() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }   // effect bound, validator NOT bound
        try runtime.coordinator.saveMeal(sampleMeal())
        let report = store.wipeLocalDataUnified()
        XCTAssertFalse(report.complete)
        XCTAssertTrue(report.failures.contains { $0.component == "writer-boundary" },
                      "A missing validator binding is a boundary failure, never a skipped re-proof")
        XCTAssertEqual(try runtime.readMeals().count, 1, "Nothing is erased when the boundary is incomplete")
    }

    // MARK: sign-out / delete-account guards

    func testSignOutRemoveRefusesWhileBoundaryUnbound() async {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew")]
        await store.signOut(removeLocalData: true)
        XCTAssertEqual(store.recipes.map(\.id), ["recipe-1"])
        XCTAssertEqual(store.toast?.message, "The unified Journal reset is not ready. Nothing was cleared.")
    }

    func testSignOutRemoveRefusesWithEffectButNoValidator() async {
        let store = makeStore(runtime: makeRuntime())
        store.journalWriterEffect = { work in try work() }
        await store.signOut(removeLocalData: true)
        XCTAssertEqual(store.toast?.message, "The unified Journal reset is not ready. Nothing was cleared.",
                       "Effect and validator are bound together; half a boundary refuses")
    }

    func testDeleteAccountRefusesWhileBoundaryUnbound() async {
        let store = makeStore(runtime: makeRuntime())
        let error = await store.deleteAccount()
        XCTAssertEqual(error?.message, "The unified Journal reset is not ready. Your account has not been deleted.")
    }
}
