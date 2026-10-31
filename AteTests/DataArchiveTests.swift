import XCTest
@testable import Ate

@MainActor
final class DataArchiveTests: XCTestCase {
    func testExportAndImportRoundTripIncludesDiaryShoppingAndGoals() throws {
        let priorSettings = UserDefaults.standard.data(forKey: "ate.settings.v1")
        let priorTimerPrefs = UserDefaults.standard.data(forKey: "ate.timerprefs.v1")
        defer {
            if let priorSettings { UserDefaults.standard.set(priorSettings, forKey: "ate.settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.settings.v1") }
            if let priorTimerPrefs { UserDefaults.standard.set(priorTimerPrefs, forKey: "ate.timerprefs.v1") }
            else { UserDefaults.standard.removeObject(forKey: "ate.timerprefs.v1") }
        }
        let sourceFixture = makeStore()
        defer {
            sourceFixture.defaults.removePersistentDomain(forName: sourceFixture.suite)
            try? FileManager.default.removeItem(at: sourceFixture.directory)
        }
        let source = sourceFixture.store
        source.recipes = [RecipeCard(id: "recipe-1", title: "Bean stew",
                                     ingredients: [Ingredient(name: "beans", quantity: 1, unit: "cup")],
                                     steps: [Step(order: 1, instruction: "Cook", timeSeconds: nil)])]
        source.shopping = [ShoppingItem(id: "shop-1", name: "Beans", quantity: 2, unit: "cups")]
        let diaryEntry = NutritionDiaryEntry(foodName: "Bean stew", date: .now, meal: .dinner, quantity: 1,
                                             quantityUnit: "bowl", servings: 1, source: .externalFoodRecord,
                                             sourceName: "FoodData Central", sourceIdentifier: "fdc-123",
                                             verificationNote: "Exact cooked match", nutrientsPerServing: NutritionSnapshot(
                                                energyKcal: 340, proteinGrams: 18, carbohydratesGrams: nil,
                                                fatGrams: 10, fibreGrams: 8))
        try sourceFixture.diary.save([diaryEntry])
        try sourceFixture.goals.save(DailyNutritionGoals(energyKcal: 2_000, proteinGrams: 100,
                                                         carbohydratesGrams: nil, fatGrams: nil,
                                                         fibreGrams: nil))

        let data = try source.exportJSON()
        let archive = try JSONDecoder().decode(AteDataArchive.self, from: data)
        XCTAssertEqual(archive.format, AteDataArchive.formatName)
        XCTAssertEqual(archive.version, AteDataArchive.currentVersion)
        XCTAssertEqual(archive.nutritionDiaryEntries, [diaryEntry])
        XCTAssertEqual(archive.nutritionDiaryEntries.first?.sourceIdentifier, "fdc-123")
        XCTAssertNil(archive.nutritionDiaryEntries.first?.nutrientsPerServing.carbohydratesGrams)
        XCTAssertEqual(archive.shoppingItems, source.shopping)
        XCTAssertEqual(archive.nutritionGoals.energyKcal, 2_000)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("accessToken"))

        let destinationFixture = makeStore()
        defer {
            destinationFixture.defaults.removePersistentDomain(forName: destinationFixture.suite)
            try? FileManager.default.removeItem(at: destinationFixture.directory)
        }
        let destination = destinationFixture.store
        let summary = try destination.importJSON(data)
        XCTAssertEqual(summary.recipesAdded, 1)
        XCTAssertEqual(summary.shoppingItemsAdded, 1)
        XCTAssertEqual(summary.nutritionEntriesAdded, 1)
        XCTAssertEqual(destination.recipes.map(\.id), ["recipe-1"])
        XCTAssertEqual(destination.shopping, source.shopping)
        XCTAssertEqual(destinationFixture.diary.load(), [diaryEntry])
        XCTAssertEqual(try destinationFixture.goals.load().energyKcal, 2_000)
    }

    func testArchiveImportDoesNotPartiallyCommitWhenGoalsWriteFails() throws {
        let suite = "DataArchiveAtomicImport-\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let previousDiaryEntry = NutritionDiaryEntry(
            foodName: "Existing lunch", date: .now, meal: .lunch, quantity: 1, quantityUnit: "plate",
            servings: 1, source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: 450, proteinGrams: nil,
                                                   carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        )
        let previousGoals = DailyNutritionGoals(energyKcal: 1_900, proteinGrams: 80,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        let storage = ArchiveFailingNutritionGoalsStorage(data: try JSONEncoder().encode(previousGoals))
        let diary = NutritionDiaryRepository(defaults: defaults)
        let goals = NutritionGoalsRepository(defaults: defaults, storage: storage)
        try diary.save([previousDiaryEntry])

        let store = AppStore(context: nil, backend: MockBackend(), nutritionDiaryRepository: diary,
                             nutritionGoalsRepository: goals)
        store.recipes = [RecipeCard(id: "existing-recipe", title: "Existing recipe")]
        store.shopping = [ShoppingItem(id: "existing-shopping", name: "Existing item", quantity: 1, unit: "bag")]
        let originalRecipes = store.recipes
        let originalShopping = store.shopping
        let originalSettings = store.settings
        let originalTimerPreferences = store.timerPrefs

        let importedEntry = NutritionDiaryEntry(
            foodName: "Imported dinner", date: .now, meal: .dinner, quantity: 1, quantityUnit: "bowl",
            servings: 1, source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: 600, proteinGrams: nil,
                                                   carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)
        )
        let archive = AteDataArchive(
            recipes: [RecipeCard(id: "new-recipe", title: "Imported recipe")],
            shoppingItems: [ShoppingItem(id: "new-shopping", name: "Imported item", quantity: 2, unit: "bags")],
            nutritionDiaryEntries: [importedEntry],
            nutritionGoals: DailyNutritionGoals(energyKcal: 2_200, proteinGrams: 100,
                                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
            appSettings: originalSettings,
            timerPreferences: originalTimerPreferences
        )
        let data = try JSONEncoder().encode(archive)

        XCTAssertThrowsError(try store.importJSON(data))
        XCTAssertEqual(store.recipes, originalRecipes)
        XCTAssertEqual(store.shopping, originalShopping)
        XCTAssertEqual(diary.load(), [previousDiaryEntry])
        XCTAssertEqual(try goals.load(), previousGoals)
        XCTAssertEqual(store.settings, originalSettings)
        XCTAssertEqual(store.timerPrefs, originalTimerPreferences)
    }

    func testLegacyRecipeArrayImportStillWorks() throws {
        let fixture = makeStore()
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        fixture.store.recipes = [RecipeCard(id: "legacy-recipe", title: "Keep local copy")]
        let legacy = try JSONEncoder().encode([
            RecipeCard(id: "legacy-recipe", title: "Older copy"),
            RecipeCard(id: "new-recipe", title: "Soup",
                       ingredients: [Ingredient(name: "beans", quantity: 1, unit: "cup")],
                       steps: [Step(order: 1, instruction: "Cook", timeSeconds: nil)])
        ])
        let summary = try fixture.store.importJSON(legacy)
        XCTAssertEqual(summary.recipesAdded, 1)
        XCTAssertEqual(fixture.store.recipe("legacy-recipe")?.title, "Keep local copy")
        XCTAssertTrue(fixture.store.shopping.isEmpty)
        XCTAssertTrue(fixture.diary.load().isEmpty)
    }

    func testSignOutRemovingLocalDataClearsNutritionDiaryAndGoals() async throws {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.recipes = [RecipeCard(id: "recipe-1", title: "Soup")]
        store.shopping = [ShoppingItem(id: "shop-1", name: "Beans", quantity: 1, unit: "bag")]
        try fixture.diary.save([NutritionDiaryEntry(
            foodName: "Soup", date: .now, meal: .lunch, quantity: 1, quantityUnit: "bowl", servings: 1,
            source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil,
                                                   fatGrams: nil, fibreGrams: nil)
        )])
        try fixture.goals.save(DailyNutritionGoals(energyKcal: 1_800, proteinGrams: nil,
                                                    carbohydratesGrams: nil, fatGrams: nil,
                                                    fibreGrams: nil))

        await store.signOut(removeLocalData: true)

        XCTAssertTrue(store.recipes.isEmpty)
        XCTAssertTrue(store.shopping.isEmpty)
        XCTAssertTrue(fixture.diary.load().isEmpty)
        XCTAssertTrue(try fixture.goals.load().isEmpty)
    }

    func testSignOutKeepingLocalDataPreservesNutritionDiaryAndGoals() async throws {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let entry = NutritionDiaryEntry(foodName: "Lunch", date: .now, meal: .lunch, quantity: 1,
                                        quantityUnit: "plate", servings: 1, source: .userProvided, sourceName: "You",
                                        nutrientsPerServing: NutritionSnapshot(energyKcal: 500, proteinGrams: nil,
                                                                               carbohydratesGrams: nil, fatGrams: nil,
                                                                               fibreGrams: nil))
        let goals = DailyNutritionGoals(energyKcal: 2_000, proteinGrams: nil, carbohydratesGrams: nil,
                                        fatGrams: nil, fibreGrams: nil)
        try fixture.diary.save([entry])
        try fixture.goals.save(goals)

        await fixture.store.signOut(removeLocalData: false)

        XCTAssertEqual(fixture.diary.load(), [entry])
        XCTAssertEqual(try fixture.goals.load(), goals)
    }

    private func makeStore() -> (store: AppStore, diary: NutritionDiaryRepository,
                                 goals: NutritionGoalsRepository, defaults: UserDefaults, suite: String,
                                 directory: URL) {
        let suite = "DataArchiveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataArchiveTests-\(UUID().uuidString)", isDirectory: true)
        let diary = NutritionDiaryRepository(defaults: defaults)
        let goals = NutritionGoalsRepository(
            defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))
        )
        let store = AppStore(context: nil, backend: MockBackend(), nutritionDiaryRepository: diary,
                             nutritionGoalsRepository: goals)
        return (store, diary, goals, defaults, suite, directory)
    }
}

private final class ArchiveFailingNutritionGoalsStorage: NutritionGoalsStorage {
    private(set) var data: Data?
    init(data: Data?) { self.data = data }
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { throw ArchiveImportStorageError.writeFailed }
    func remove() throws { throw ArchiveImportStorageError.removeFailed }
}

private enum ArchiveImportStorageError: Error {
    case writeFailed
    case removeFailed
}
