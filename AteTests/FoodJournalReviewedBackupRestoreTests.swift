import XCTest
import SwiftData
@testable import Ate

/// Disk-backed explicit meal-backup recovery. Not full app archive restore or process-death proof.
@MainActor
final class FoodJournalReviewedBackupRestoreTests: XCTestCase {
    private func meal() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Sample lunch", date: Date(timeIntervalSince1970: 1_794_000_000),
            meal: .lunch, quantity: 1, quantityUnit: "portion", servings: 1,
            source: .userProvided, sourceName: "You", nutrientsPerServing: NutritionSnapshot(
                energyKcal: 715, proteinGrams: 55, carbohydratesGrams: nil, fatGrams: 55, fibreGrams: nil),
            dayKey: "2026-11-06")
    }
    private func withDiskWorld(state: JournalOpenState = .ok, afterCommit: @escaping () throws -> Void = {},
                               mealWrite: @escaping (ModelContext) throws -> Void = { try $0.save() }, _ body: (FoodJournalCoordinator, JournalStore, UserDefaults, URL) throws -> Void) throws {
        let id = "ReviewedBackup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: id))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: id); try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        let journal = JournalStore(container: container, openState: state)
        let coordinator = FoodJournalCoordinator(journal: journal,
            legacy: NutritionDiaryRepository(defaults: defaults), markerDefaults: defaults,
            backupDirectory: root.appendingPathComponent("migration"), afterRestoreCommit: afterCommit, mealWriteContext: mealWrite)
        try body(coordinator, journal, defaults, root)
    }
    func testExplicitBackupRestoreIsAdditiveIdempotentAndNeverRecreatesLegacy() throws {
        try withDiskWorld { coordinator, journal, defaults, root in
            let reflection = try journal.saveManual(text: "Keep this reflection")
            let entry = meal()
            let raw = try JSONEncoder().encode([entry])
            let selectedBackup = root.appendingPathComponent("selected-backup.json")
            try raw.write(to: selectedBackup, options: .atomic)
            let preserved = root.appendingPathComponent("reviewed-copies")
            XCTAssertEqual(try coordinator.restoreReviewedLegacyBackup(Data(contentsOf: selectedBackup),
                preservedCopyDirectory: preserved), 1)
            XCTAssertEqual(try coordinator.restoreReviewedLegacyBackup(raw, preservedCopyDirectory: preserved), 0)
            XCTAssertEqual(try coordinator.readMeals(), [entry])
            XCTAssertEqual(try coordinator.timelineItems().count, 2)
            XCTAssertEqual(try journal.readReflections().map(\.id), [reflection])
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
            XCTAssertEqual(try Data(contentsOf: selectedBackup), raw, "Selected original must never be removed or changed")
            let copies = try FileManager.default.contentsOfDirectory(at: preserved, includingPropertiesForKeys: nil)
            XCTAssertEqual(copies.count, 2)
            for copy in copies { XCTAssertEqual(try Data(contentsOf: copy), raw) }
            // No background scan/import: a subsequent ordinary read is only a read.
            XCTAssertEqual(try coordinator.readMeals(), [entry])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: preserved, includingPropertiesForKeys: nil).count, 2)
            // A second same-process container reads disk truth. This does not prove process death or release.
            let reopened = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
            let reopenedJournal = JournalStore(container: reopened, openState: .ok)
            XCTAssertEqual(try FoodJournalStore(container: reopened).readMeals(), [entry])
            XCTAssertEqual(try reopenedJournal.readReflections().map(\.id), [reflection])
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        }
    }
    func testBlockedPreservedCopyPreventsCanonicalInsertion() throws {
        try withDiskWorld { coordinator, _, defaults, root in
            let blocker = root.appendingPathComponent("not-a-directory")
            let sentinel = Data("leave this alone".utf8)
            try sentinel.write(to: blocker)
            let raw = try JSONEncoder().encode([meal()])
            XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(raw, preservedCopyDirectory: blocker))
            XCTAssertTrue(try coordinator.readMeals().isEmpty)
            XCTAssertEqual(try Data(contentsOf: blocker), sentinel)
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        }
    }
    func testConflictingIdentityNeverReplacesCanonicalMeal() throws {
        try withDiskWorld { coordinator, _, defaults, root in
            let original = meal()
            try coordinator.saveMeal(original)
            var conflict = original; conflict.servings = 2
            XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(JSONEncoder().encode([conflict]),
                preservedCopyDirectory: root.appendingPathComponent("copies")))
            XCTAssertEqual(try coordinator.readMeals(), [original])
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        }
    }
    func testCorruptBackupCannotWriteCanonicalDataOrRecoveryCopies() throws {
        try withDiskWorld { coordinator, _, defaults, root in
            let copies = root.appendingPathComponent("copies")
            XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(Data("broken".utf8),
                preservedCopyDirectory: copies))
            XCTAssertTrue(try coordinator.readMeals().isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: copies.path))
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        }
    }
    func testPostCommitVerificationFailureReportsCommittedNotNothingChanged() throws {
        enum Failure: Error { case injected }
        try withDiskWorld(afterCommit: { throw Failure.injected }) { coordinator, _, defaults, root in
            let original = meal()
            XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(JSONEncoder().encode([original]),
                preservedCopyDirectory: root.appendingPathComponent("copies"))) { error in
                XCTAssertEqual(error as? FoodJournalCoordinator.AccessError, .restoreCommittedButUnverified)
            }
            XCTAssertEqual(try coordinator.readMeals(), [original], "Commit occurred despite failed verification")
            XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        }
    }
    func testExistingLegacyConflictIsRejectedBeforeMigrationRetirement() throws {
        try withDiskWorld { coordinator, journal, defaults, root in
            let original = meal()
            let raw = try JSONEncoder().encode([original])
            defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
            var conflict = original; conflict.servings = 2
            XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(JSONEncoder().encode([conflict]),
                preservedCopyDirectory: root.appendingPathComponent("copies")))
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
            XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
            XCTAssertTrue(try FoodJournalStore(container: journal.container).readMeals().isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("copies").path))
        }
    }
    func testFallbackAndUnavailableBackupsCannotImportOrCreateCopies() throws {
        let states: [JournalOpenState] = [.inMemoryFallback(error: "fixture"), .unavailable(error: "fixture")]
        for state in states {
            try withDiskWorld(state: state) { coordinator, journal, defaults, root in
                XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(JSONEncoder().encode([meal()]),
                    preservedCopyDirectory: root.appendingPathComponent("copies")))
                XCTAssertTrue(try FoodJournalStore(container: journal.container).readMeals().isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("copies").path))
                XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
            }
        }
    }
    func testDuplicateOrInvalidDayBackupCannotImportOrCreateCopies() throws {
        let original = meal()
        var invalid = original; invalid.dayKey = "2026-02-30"
        for entries in [[original, original], [invalid]] {
            try withDiskWorld { coordinator, journal, defaults, root in
                XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(JSONEncoder().encode(entries),
                    preservedCopyDirectory: root.appendingPathComponent("copies")))
                XCTAssertTrue(try FoodJournalStore(container: journal.container).readMeals().isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("copies").path))
                XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
            }
        }
    }

    func testImportSaveThrowsBeforeOrAfterActualCommitReportsUncertain() throws {
        enum Failure: Error { case injected }
        for commitFirst in [false, true] {
            try withDiskWorld(mealWrite: { context in
                if commitFirst { try context.save() }
                throw Failure.injected
            }) { coordinator, journal, defaults, root in
                let original = meal()
                let raw = try JSONEncoder().encode([original])
                let copies = root.appendingPathComponent("copies")
                XCTAssertThrowsError(try coordinator.restoreReviewedLegacyBackup(raw,
                    preservedCopyDirectory: copies)) { error in
                    XCTAssertEqual(error as? FoodJournalCoordinator.AccessError, .restoreOutcomeUncertain)
                }
                let actual = try FoodJournalStore(container: journal.container).readMeals()
                XCTAssertEqual(actual, commitFirst ? [original] : [], "Read committed-store truth after save threw; not process-death or power-loss proof")
                let retained = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: copies,
                    includingPropertiesForKeys: nil).first)
                XCTAssertEqual(try Data(contentsOf: retained), raw)
                XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
            }
        }
    }

    func testControllerCommittedButUnverifiedShowsHonestFailureWithoutAutomaticRetry() throws {
        enum Failure: Error { case injected }
        var commits = 0
        try withDiskWorld(afterCommit: { throw Failure.injected }, mealWrite: { context in
            try context.save(); commits += 1
        }) { coordinator, journal, defaults, root in
            let legacy = NutritionDiaryRepository(defaults: defaults)
            let controller = NutritionDiaryController(coordinator: coordinator,
                goalsRepository: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
                repair: LegacyDiaryRepair(repository: legacy, backupDirectory: root.appendingPathComponent("repair")))
            let backup = try ReviewedMealBackup(JSONEncoder().encode([meal()]))
            XCTAssertThrowsError(try controller.restoreReviewedMealBackup(backup)) { error in
                XCTAssertTrue(error.localizedDescription.contains("could not confirm"))
                XCTAssertFalse(error.localizedDescription.contains("have not been replaced"))
            }
            XCTAssertEqual(commits, 1, "Never retry an uncertain committed restore")
            XCTAssertEqual(try FoodJournalStore(container: journal.container).readMeals(), backup.entries)
            controller.reload()
            XCTAssertEqual(controller.entries, backup.entries)
        }
    }

}
