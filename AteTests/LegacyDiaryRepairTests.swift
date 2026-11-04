import XCTest
@testable import Ate

@MainActor
final class LegacyDiaryRepairTests: XCTestCase {
    private func entry() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Pap", date: Date(timeIntervalSince1970: 1_790_000_000), meal: .dinner, quantity: 1,
                            quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
    }
    func testRepairPreservesBackupAndUntouchedRowsAndRejectsStaleSnapshot() throws {
        let suite = "LegacyDiaryRepair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        var invalid = entry(); invalid.foodName = ""
        let good = entry()
        let raw = try JSONEncoder().encode([invalid, good])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let repair = LegacyDiaryRepair(repository: NutritionDiaryRepository(defaults: defaults), backupDirectory: dir)
        let before = try repair.snapshot()
        XCTAssertEqual(before.invalidIndices, [0])
        var fixed = invalid; fixed.foodName = "Fixed pap"
        try repair.replace(index: 0, with: fixed, in: before)
        XCTAssertEqual(try repair.snapshot().entries, [fixed, good])
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), raw)
        XCTAssertThrowsError(try repair.remove(index: 1, from: before)) { XCTAssertEqual($0 as? LegacyDiaryRepairError, .changedSinceReview) }
    }
    func testDuplicateIdentityCanBeRemovedByRowIndexWithoutDroppingBoth() throws {
        let suite = "LegacyDiaryRepair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let original = entry()
        let repo = NutritionDiaryRepository(defaults: defaults)
        try repo.save([original, original])
        let repair = LegacyDiaryRepair(repository: repo, backupDirectory: dir)
        let before = try repair.snapshot()
        XCTAssertEqual(before.duplicateIndices, [1])
        try repair.remove(index: 1, from: before)
        XCTAssertEqual(try repair.snapshot().entries, [original])
    }
    func testInvalidDayReplacementDoesNotWriteOrMigratePoisonedRow() throws {
        let suite = "LegacyDiaryRepair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let repo = NutritionDiaryRepository(defaults: defaults)
        let original = entry()
        try repo.save([original])
        let repair = LegacyDiaryRepair(repository: repo, backupDirectory: dir)
        let snapshot = try repair.snapshot()
        var changed = original; changed.dayKey = "hello"
        XCTAssertThrowsError(try repair.replace(index: 0, with: changed, in: snapshot)) {
            XCTAssertEqual($0 as? LegacyDiaryRepairError, .invalidReplacement)
        }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), snapshot.originalBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
    func testUndecodableAndBackupFailurePreserveSourceBytes() throws {
        let suite = "LegacyDiaryRepair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
        let repo = NutritionDiaryRepository(defaults: defaults)
        let repair = LegacyDiaryRepair(repository: repo, backupDirectory: file)
        let raw = Data("undecodable".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        XCTAssertThrowsError(try repair.snapshot()) { XCTAssertEqual($0 as? LegacyDiaryRepairError, .undecodable) }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        try Data("not a directory".utf8).write(to: file)
        let good = try JSONEncoder().encode([entry()])
        defaults.set(good, forKey: NutritionDiaryRepository.storageKey)
        let snapshot = try repair.snapshot()
        XCTAssertThrowsError(try repair.remove(index: 0, from: snapshot)) { XCTAssertEqual($0 as? LegacyDiaryRepairError, .backupFailed) }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), good)
    }

    func testExplicitUndecodableRecoveryBacksUpExactBytesBeforeResetAndRefusesReadableData() throws {
        let suite = "LegacyDiaryRepair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let repo = NutritionDiaryRepository(defaults: defaults)
        let repair = LegacyDiaryRepair(repository: repo, backupDirectory: dir)
        let raw = Data("unreadable".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        try repair.backUpAndResetUndecodableData()
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), raw)
        try repo.save([entry()])
        XCTAssertThrowsError(try repair.backUpAndResetUndecodableData()) { XCTAssertEqual($0 as? LegacyDiaryRepairError, .invalidReplacement) }
        XCTAssertEqual(repo.load().count, 1)
    }

}
