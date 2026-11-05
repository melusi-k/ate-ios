import XCTest
@testable import Ate

@MainActor
final class FoodJournalCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var backup: URL!

    override func setUpWithError() throws {
        suite = "FoodJournalCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        backup = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: backup)
        defaults = nil
        super.tearDown()
    }
    private func entry() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Pap", date: Date(timeIntervalSince1970: 1_790_000_000), meal: .dinner,
                           quantity: 1, quantityUnit: "portion", servings: 1, source: .userProvided,
                           sourceName: "You", nutrientsPerServing: NutritionSnapshot(energyKcal: 200, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
    }
    private func coordinator(_ journal: JournalStore) -> FoodJournalCoordinator {
        FoodJournalCoordinator(journal: journal,
                               legacy: NutritionDiaryRepository(defaults: defaults, backupDirectory: backup),
                               markerDefaults: defaults, backupDirectory: backup)
    }
    func testMigrateThenReadSaveEditDeleteWithoutRecreatingLegacyKey() throws {
        let legacy = NutritionDiaryRepository(defaults: defaults, backupDirectory: backup)
        let original = entry()
        try legacy.save([original])
        let journal = JournalStore(inMemory: true)
        let c = coordinator(journal)
        XCTAssertEqual(try c.readMeals(), [original])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        var changed = original
        changed.foodName = "Changed pap"
        try c.updateMeal(changed)
        XCTAssertEqual(try c.readMeals(), [changed])
        let second = entry()
        try c.saveMeal(second)
        XCTAssertEqual(try c.readMeals().count, 2)
        try c.deleteMeal(id: original.id)
        XCTAssertEqual(try c.readMeals(), [second])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
    }
    func testInvalidLegacyFailsAllCanonicalActionsAndPreservesOriginalBytes() throws {
        let raw = Data("not a diary".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let c = coordinator(JournalStore(inMemory: true))
        XCTAssertThrowsError(try c.readMeals()) { XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt) }
        XCTAssertThrowsError(try c.saveMeal(entry())) { XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt) }
        XCTAssertThrowsError(try c.updateMeal(entry())) { XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt) }
        XCTAssertThrowsError(try c.deleteMeal(id: UUID())) { XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt) }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }
    func testDecodableInvalidLegacyHasTypedFailureThenRepairRetriesWithoutCachedFailure() throws {
        var invalid = entry()
        invalid.foodName = ""
        // Bypass repository validation solely to model an older invalid on-disk payload.
        let raw = try JSONEncoder().encode([invalid])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let c = coordinator(JournalStore(inMemory: true))
        let expected = FoodJournalCoordinator.AccessError.migrationFailed("invalid or duplicate legacy records preserved; no meals imported")
        let actions: [() throws -> Void] = [
            { _ = try c.readMeals() }, { try c.saveMeal(self.entry()) },
            { try c.updateMeal(self.entry()) }, { try c.deleteMeal(id: UUID()) }
        ]
        for action in actions {
            XCTAssertThrowsError(try action()) { XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, expected) }
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
            XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
        }
        let fixed = entry()
        try NutritionDiaryRepository(defaults: defaults, backupDirectory: backup).save([fixed])
        XCTAssertEqual(try c.readMeals(), [fixed])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
    }

}
