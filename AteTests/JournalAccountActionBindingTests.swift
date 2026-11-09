import XCTest
@testable import Ate

/// #245 slice B: bound account actions under the unified Journal graph - clear-library,
/// sign-out-remove, delete-account, Settings import/export. The legacy paths are covered
/// by DataArchiveTests and friends; these tests pin the runtime-injected behavior.
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

    private func makeRuntime(journal: JournalStore = JournalStore(inMemory: true)) -> FoodJournalRuntime {
        FoodJournalRuntime(journal: journal, goalsRepository: goalsRepo(), defaults: defaults,
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

    func testExportUnifiedContainsMealsAndGoalsFromTheRuntime() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        let meal = sampleMeal()
        try runtime.coordinator.saveMeal(meal)
        try runtime.goalsRepository.save(DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 100,
                                                             carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))

        let data = try store.exportJSON()
        let archive = try JSONDecoder().decode(AteDataArchive.self, from: data)
        XCTAssertEqual(archive.format, AteDataArchive.formatName)
        XCTAssertEqual(archive.nutritionDiaryEntries, [meal])
        XCTAssertEqual(archive.nutritionGoals.energyKcal, 2_000)
    }

    func testExportUnifiedRefusesANonDurableStore() {
        let runtime = makeRuntime(journal: JournalStore(container: nil, openState: .unavailable(error: "simulated")))
        let store = makeStore(runtime: runtime)
        XCTAssertThrowsError(try store.exportJSON()) { error in
            guard case AteDataArchiveError.localDiaryUnreadableOnExport = error else {
                return XCTFail("An unreadable unified store must never export as an empty diary; got \(error)")
            }
        }
    }

    // MARK: Settings import

    private func archiveData(meals: [NutritionDiaryEntry], goals: DailyNutritionGoals = DailyNutritionGoals()) throws -> Data {
        let archive = AteDataArchive(recipes: [], shoppingItems: [], nutritionDiaryEntries: meals,
                                     nutritionGoals: goals, appSettings: AppSettings(),
                                     timerPreferences: TimerPrefs())
        return try JSONEncoder().encode(archive)
    }

    func testImportUnifiedMergesMealsThroughTheBarrierIdempotently() throws {
        // Import assigns settings/timerPrefs, whose didSet writes .standard; preserve them.
        let priorSettings = UserDefaults.standard.object(forKey: "ate.settings.v1")
        let priorTimers = UserDefaults.standard.object(forKey: "ate.timerprefs.v1")
        defer {
            if let priorSettings { UserDefaults.standard.set(priorSettings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let priorTimers { UserDefaults.standard.set(priorTimers, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        let meal = sampleMeal()
        let data = try archiveData(meals: [meal])

        let first = try store.importJSON(data)
        XCTAssertEqual(first.nutritionEntriesAdded, 1)
        XCTAssertEqual(try runtime.readMeals(), [meal])

        let second = try store.importJSON(data)
        XCTAssertEqual(second.nutritionEntriesAdded, 0, "Imports are additive: a matching ID on this device wins")
        XCTAssertEqual(try runtime.readMeals(), [meal], "Exactly one row per identity, never a duplicate")
        XCTAssertNil(defaults.object(forKey: "ate.nutritionDiary.v1"),
                     "Import must never recreate legacy diary bytes")
    }

    func testImportUnifiedRejectsInvalidMealsBeforeWriting() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        let invalid = NutritionDiaryEntry(foodName: "  ", date: .now, meal: .dinner, quantity: 1,
                                          quantityUnit: "bowl", servings: 1, source: .userProvided,
                                          sourceName: "You",
                                          nutrientsPerServing: NutritionSnapshot(energyKcal: 100, proteinGrams: nil,
                                                                                 carbohydratesGrams: nil, fatGrams: nil,
                                                                                 fibreGrams: nil))
        XCTAssertThrowsError(try store.importJSON(archiveData(meals: [invalid]))) { error in
            guard case AteDataArchiveError.invalidNutritionEntry = error else {
                return XCTFail("expected invalidNutritionEntry, got \(error)")
            }
        }
        XCTAssertEqual(try runtime.readMeals(), [])
    }

    func testImportUnifiedRefusesWhileBoundaryUnbound() throws {
        let store = makeStore(runtime: makeRuntime())
        XCTAssertThrowsError(try store.importJSON(archiveData(meals: [sampleMeal()]))) { error in
            XCTAssertTrue(error is CanonicalConsumerBindingError)
        }
    }

    func testImportUnifiedRefusesANonDurableStore() throws {
        let runtime = makeRuntime(journal: JournalStore(container: nil, openState: .inMemoryFallback(error: "simulated")))
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        XCTAssertThrowsError(try store.importJSON(archiveData(meals: [sampleMeal()]))) { error in
            guard case AteDataArchiveError.localDiaryUnreadable = error else {
                return XCTFail("expected localDiaryUnreadable, got \(error)")
            }
        }
    }

    // MARK: wipe (sign-out-remove / delete-account)

    func testWipeUnifiedErasesJournalAndPreservesLifecycleMarkers() throws {
        let runtime = makeRuntime()
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        try runtime.coordinator.saveMeal(sampleMeal())
        defaults.set(Data("legacy diary".utf8), forKey: "ate.nutritionDiary.v1")
        defaults.set(true, forKey: "ate.foodJournal.diaryMigration.v1")

        let report = store.wipeLocalDataUnified()

        XCTAssertTrue(report.complete, "failures: \(report.failures)")
        XCTAssertEqual(try runtime.readMeals(), [])
        XCTAssertNil(defaults.object(forKey: "ate.nutritionDiary.v1"))
        XCTAssertNotNil(defaults.object(forKey: "ate.foodJournal.diaryMigration.v1"),
                        "Migration markers are non-personal control state and must survive a wipe")
    }

    func testWipeUnifiedReportsFailureInsteadOfClaimingSuccess() {
        let runtime = makeRuntime(journal: JournalStore(container: nil, openState: .ok))
        let store = makeStore(runtime: runtime)
        store.journalWriterEffect = { work in try work() }
        let report = store.wipeLocalDataUnified()
        XCTAssertFalse(report.complete, "A nil container in a durable state is a failure, never an empty store")
        XCTAssertTrue(report.failures.contains { $0.component == "journal-rows-payloads" })
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

    func testDeleteAccountRefusesWhileBoundaryUnbound() async {
        let store = makeStore(runtime: makeRuntime())
        let error = await store.deleteAccount()
        XCTAssertEqual(error?.message, "The unified Journal reset is not ready. Your account has not been deleted.")
    }
}
