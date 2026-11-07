import XCTest
@testable import Ate

@MainActor
final class FoodJournalMigrationSnapshotTests: XCTestCase {
    private func goals(_ defaults: UserDefaults, suite: String) -> NutritionGoalsRepository {
        NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suite).appendingPathComponent("goals.json")))
    }

    private func entry() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Pap", date: Date(timeIntervalSince1970: 1_790_000_000),
                            meal: .dinner, quantity: 1, quantityUnit: "portion", servings: 1,
                            source: .userProvided, sourceName: "You",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: 200, proteinGrams: nil,
                                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil), dayKey: "2026-10-30")
    }

    func testMigrationBacksUpExactPreDayKeyBytes() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry())) as? [String: Any])
        object.removeValue(forKey: "dayKey")
        let raw = try JSONSerialization.data(withJSONObject: [object], options: [.prettyPrinted, .sortedKeys])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true), goalsRepository: goals(defaults, suite: suite), defaults: defaults,
                                         migrationBackupDirectory: dir, repairBackupDirectory: dir)
        XCTAssertEqual(try runtime.readMeals().count, 1)
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        let backups = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), raw)
    }

    func testBackupFailureDoesNotInsertCanonicalCopyOrNormalizeLegacyBytes() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: blocker) }
        try Data("not a directory".utf8).write(to: blocker)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry())) as? [String: Any])
        object.removeValue(forKey: "dayKey")
        let raw = try JSONSerialization.data(withJSONObject: [object], options: [.prettyPrinted])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let journal = JournalStore(inMemory: true)
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals(defaults, suite: suite), defaults: defaults, migrationBackupDirectory: blocker)
        XCTAssertThrowsError(try runtime.readMeals())
        XCTAssertTrue(try FoodJournalStore(container: journal.container).readMeals().isEmpty)
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }

    func testRuntimeUsesActualUnavailableStateWithoutLegacyRetirement() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = try JSONEncoder().encode([entry()])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let journal = JournalStore(container: nil, openState: .unavailable(error: "fixture"))
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals(defaults, suite: suite), defaults: defaults)
        XCTAssertThrowsError(try runtime.readMeals())
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertEqual(runtime.coordinator.openState, .unavailable(error: "fixture"))
    }

    func testRepairMarksStrictlyInvalidCalendarDay() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var invalid = entry(); invalid.dayKey = "2026-02-30"
        defaults.set(try JSONEncoder().encode([invalid]), forKey: NutritionDiaryRepository.storageKey)
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true), goalsRepository: goals(defaults, suite: suite), defaults: defaults)
        XCTAssertEqual(try runtime.repair.snapshot().invalidIndices, [0])
        XCTAssertThrowsError(try runtime.readMeals())
    }
    func testTimelineBarrierMigratesOnceAndPreservesMealFieldsAndReflection() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let meal = entry()
        defaults.set(try JSONEncoder().encode([meal]), forKey: NutritionDiaryRepository.storageKey)
        let journal = JournalStore(inMemory: true)
        let reflection = try journal.saveManual(text: "Remember this dinner")
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals(defaults, suite: suite), defaults: defaults, migrationBackupDirectory: dir)
        let rows = try runtime.timelineItems()
        XCTAssertEqual(rows.count, 2)
        let mealRow = try XCTUnwrap(rows.first { $0.id == meal.id.uuidString })
        XCTAssertEqual(mealRow.kind, .meal)
        XCTAssertEqual(mealRow.dayKey, meal.dayKey)
        XCTAssertEqual(mealRow.summary, meal.foodName)
        XCTAssertEqual(rows.first { $0.id == reflection }?.summary, "Remember this dinner")
        XCTAssertEqual(try runtime.timelineItems().count, 2)
        XCTAssertEqual(try runtime.readMeals(), [meal])
    }

    func testTimelineBarrierKeepsCorruptLegacyAsFailureNotEmptyHistory() throws {
        let suite = "MigrationSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = Data("unreadable diary".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let runtime = FoodJournalRuntime(journal: JournalStore(inMemory: true), goalsRepository: goals(defaults, suite: suite), defaults: defaults)
        XCTAssertThrowsError(try runtime.timelineItems())
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
    }

}
