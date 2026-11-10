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
                 foodJournalRuntime: runtime)
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

    // MARK: clear-library

    func testClearLibraryUnifiedClearsThroughRuntimeStores() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        store.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew")]
        runtime.cookingHistory.record(recipeID: "recipe-1", date: Date(timeIntervalSince1970: 1_790_000_000))
        defaults.set(Data("outbox".utf8), forKey: "ate.cook.completionOutbox.v1")

        store.clearLibrary()

        XCTAssertTrue(store.recipes.isEmpty)
        XCTAssertFalse(runtime.cookingHistory.cooked(on: Date(timeIntervalSince1970: 1_790_000_000)),
                       "The unified history must be cleared, not only the legacy singleton")
        XCTAssertNil(defaults.object(forKey: "ate.cook.completionOutbox.v1"))
    }

    func testClearLibraryUnifiedRefusesWhileBoundaryUnbound() {
        let store = makeStore(runtime: makeRuntime())
        store.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew")]
        store.clearLibrary()
        XCTAssertEqual(store.recipes.map(\.id), ["recipe-1"], "An unbound boundary must refuse the wipe")
        XCTAssertEqual(store.toast?.message, "The unified Journal reset is not ready. Nothing was cleared.")
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
        var validatorCalls = 0
        store.journalWriterEffect = { work in effectCalls += 1; return try work() }
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
