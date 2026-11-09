import XCTest
import SwiftData
@testable import Ate

/// Disk-backed boundary fixtures, not process-termination or production activation evidence.
@MainActor
final class FoodJournalUpgradeFailureDiskTests: XCTestCase {
    private struct World {
        let defaults: UserDefaults
        let directory: URL
        let journal: JournalStore
        let runtime: FoodJournalRuntime
        let controller: NutritionDiaryController
    }
    private func entry() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Sample dinner", date: Date(timeIntervalSince1970: 1_794_000_000),
            meal: .dinner, quantity: 1, quantityUnit: "portion", servings: 1,
            source: .userProvided, sourceName: "You",
            nutrientsPerServing: NutritionSnapshot(energyKcal: 200, proteinGrams: nil,
                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil), dayKey: "2026-11-06")
    }
    private func withWorld(state: JournalOpenState = .ok, backupBlocked: Bool = false,
                           _ body: (World) throws -> Void) throws {
        let suite = "FoodJournalUpgradeFailure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("journal.store")))
        let journal = JournalStore(container: container, openState: state)
        let backup = directory.appendingPathComponent("legacy-backups")
        if backupBlocked { try Data("not a directory".utf8).write(to: backup) }
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json")))
        let runtime = FoodJournalRuntime(journal: journal, goalsRepository: goals, defaults: defaults,
            migrationBackupDirectory: backup, repairBackupDirectory: directory.appendingPathComponent("repair"))
        let controller = NutritionDiaryController(coordinator: runtime.coordinator,
            goalsRepository: goals, repair: runtime.repair)
        try body(World(defaults: defaults, directory: directory, journal: journal,
                       runtime: runtime, controller: controller))
    }
    private func assertLegacyUntouched(_ raw: Data, world: World,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(world.defaults.data(forKey: NutritionDiaryRepository.storageKey), raw, file: file, line: line)
        XCTAssertFalse(world.defaults.bool(forKey: FoodJournalMigration.markerKey), file: file, line: line)
        XCTAssertTrue(try FoodJournalStore(container: world.journal.container).readMeals().isEmpty, file: file, line: line)
    }
    func testCorruptLegacyKeepsBytesAndOffersRepairNotEmptySuccess() throws {
        try withWorld { world in
            let raw = Data("broken legacy sample".utf8)
            world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            XCTAssertThrowsError(try world.runtime.readMeals())
            world.controller.reload()
            guard case .legacyRepairNeeded? = world.controller.issue else {
                return XCTFail("Corrupt legacy must expose repair")
            }
            try assertLegacyUntouched(raw, world: world)
        }
    }
    func testInvalidHistoricalDayKeepsBytesAndOffersRepair() throws {
        try withWorld { world in
            var invalid = entry(); invalid.dayKey = "2026-02-30"
            let raw = try JSONEncoder().encode([invalid])
            world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            world.controller.reload()
            guard case .legacyRepairNeeded? = world.controller.issue else {
                return XCTFail("Invalid day must expose repair")
            }
            XCTAssertEqual(try world.runtime.repair.snapshot().invalidIndices, [0])
            try assertLegacyUntouched(raw, world: world)
        }
    }
    func testDuplicateLegacyIDsKeepBothOriginalRowsAndOfferRepair() throws {
        try withWorld { world in
            let meal = entry()
            let raw = try JSONEncoder().encode([meal, meal])
            world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            world.controller.reload()
            guard case .legacyRepairNeeded? = world.controller.issue else {
                return XCTFail("Duplicate identity must expose repair")
            }
            XCTAssertEqual(try world.runtime.repair.snapshot().duplicateIndices, [1])
            try assertLegacyUntouched(raw, world: world)
        }
    }
    func testBlockedBackupPrecedesCanonicalMutationAndOffersRetry() throws {
        try withWorld(backupBlocked: true) { world in
            let raw = try JSONEncoder().encode([entry()])
            world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            world.controller.reload()
            guard case .migrationRetryNeeded? = world.controller.issue else {
                return XCTFail("Storage failure must offer retry, not invalid-data repair")
            }
            try assertLegacyUntouched(raw, world: world)
            XCTAssertEqual(try Data(contentsOf: world.directory.appendingPathComponent("legacy-backups")),
                           Data("not a directory".utf8))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: world.directory.appendingPathComponent("repair").path))
        }
    }
    func testFallbackAndUnavailableCannotRetireOrWriteMeals() throws {
        let states: [JournalOpenState] = [.inMemoryFallback(error: "fixture"), .unavailable(error: "fixture")]
        for state in states {
            try withWorld(state: state) { world in
                let raw = try JSONEncoder().encode([entry()])
                world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
                world.controller.reload()
                guard case .migrationRetryNeeded? = world.controller.issue else {
                    return XCTFail("Nondurable state must expose retry")
                }
                XCTAssertThrowsError(try world.runtime.coordinator.saveMeal(entry()))
                try assertLegacyUntouched(raw, world: world)
            }
        }
    }
    func testCanonicalIdentityAlreadyCommittedBeforeRetirementRetriesWithoutDuplicate() throws {
        try withWorld { world in
            let meal = entry()
            let raw = try JSONEncoder().encode([meal])
            world.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            // Simulates the persisted boundary state after an import but before key retirement.
            // This is NOT an actual process-kill test or complete migration crash-window proof.
            try FoodJournalStore(container: world.journal.container).saveMeal(meal)
            XCTAssertEqual(try world.runtime.readMeals(), [meal])
            XCTAssertEqual(try world.runtime.timelineItems().filter { $0.id == meal.id.uuidString }.count, 1)
            XCTAssertNil(world.defaults.data(forKey: NutritionDiaryRepository.storageKey))
            XCTAssertTrue(world.defaults.bool(forKey: FoodJournalMigration.markerKey))
            let backups = try FileManager.default.contentsOfDirectory(
                at: world.directory.appendingPathComponent("legacy-backups"), includingPropertiesForKeys: nil)
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), raw)
        }
    }
}
