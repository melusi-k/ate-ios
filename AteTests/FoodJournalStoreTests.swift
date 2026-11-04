import XCTest
import SwiftData
@testable import Ate

/// #245 phase 2: unified Food Journal meal store, diary migration and journal-store recovery.
@MainActor
final class FoodJournalStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: FoodJournalStore!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var backupDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = FoodJournalStore(container: container)
        suiteName = "FoodJournalStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodJournalStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        store = nil
        if let backupDir { try? FileManager.default.removeItem(at: backupDir) }
        backupDir = nil
        super.tearDown()
    }

    private func legacyRepository() -> NutritionDiaryRepository {
        NutritionDiaryRepository(defaults: defaults, backupDirectory: backupDir)
    }

    private func sampleEntry(id: UUID = UUID(), foodName: String = "Pap and wors",
                             date: Date = Date(timeIntervalSince1970: 1_790_000_000),
                             dayKey: String? = nil, meal: NutritionMeal = .dinner) -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: foodName, date: date, meal: meal, quantity: 250,
                            quantityUnit: "g", servings: 1.5, source: .userProvided,
                            sourceName: "Label", sourceIdentifier: "record-42", verificationNote: "cooked",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: 320, proteinGrams: nil,
                                                                   carbohydratesGrams: 40, fatGrams: 8, fibreGrams: nil),
                            dayKey: dayKey)
    }

    private func assertSameEntry(_ actual: NutritionDiaryEntry, _ expected: NutritionDiaryEntry,
                                 _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, message, file: file, line: line)
        XCTAssertEqual(actual.foodName, expected.foodName, message, file: file, line: line)
        XCTAssertEqual(actual.date.timeIntervalSince1970, expected.date.timeIntervalSince1970, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.dayKey, expected.dayKey, message, file: file, line: line)
        XCTAssertEqual(actual.meal, expected.meal, message, file: file, line: line)
        XCTAssertEqual(actual.quantity, expected.quantity, message, file: file, line: line)
        XCTAssertEqual(actual.quantityUnit, expected.quantityUnit, message, file: file, line: line)
        XCTAssertEqual(actual.servings, expected.servings, message, file: file, line: line)
        XCTAssertEqual(actual.source, expected.source, message, file: file, line: line)
        XCTAssertEqual(actual.sourceName, expected.sourceName, message, file: file, line: line)
        XCTAssertEqual(actual.sourceIdentifier, expected.sourceIdentifier, message, file: file, line: line)
        XCTAssertEqual(actual.verificationNote, expected.verificationNote, message, file: file, line: line)
        XCTAssertEqual(actual.nutrientsPerServing, expected.nutrientsPerServing, message, file: file, line: line)
    }

    // MARK: Store round trips

    func testMealRoundTripsEveryFieldVerbatim() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        let loaded = try XCTUnwrap(store.mealEntries().first)
        assertSameEntry(loaded, entry)
    }

    func testSavedMealIsOneJournalEntryWithMealKind() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        let journalEntries = try container.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(journalEntries.count, 1, "exactly one journal entry per saved meal")
        let stored = try XCTUnwrap(journalEntries.first)
        XCTAssertEqual(stored.kind, .meal)
        XCTAssertEqual(stored.id, entry.id.uuidString, "entry identity is the diary UUID")
        XCTAssertEqual(stored.dayKey, entry.dayKey)
        XCTAssertEqual(stored.createdAt.timeIntervalSince1970, entry.date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(stored.text, "", "a meal never requires reflection text")
        let payloads = try container.mainContext.fetch(FetchDescriptor<JournalMealPayload>())
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.entryID, stored.id)
    }

    func testExistingReflectionDefaultsToReflectionKind() throws {
        container.mainContext.autosaveEnabled = false
        let reflection = Ate.JournalEntry(prompt: "What did you enjoy?", text: "Pap night", state: .balanced)
        container.mainContext.insert(reflection)
        try container.mainContext.save()
        XCTAssertEqual(reflection.kind, .reflection, "pre-unification rows decode as reflections via the model default")
        XCTAssertNil(reflection.dayKey)
        XCTAssertTrue(store.mealEntries().isEmpty, "reflections are not diary meals")
    }

    func testDayKeyPreservedVerbatimNotRecomputed() throws {
        // Logged at 23:30 Los Angeles on Jan 15; the stored day must stay Jan 15 even though the
        // instant is already Jan 16 in Johannesburg. The day key travels verbatim.
        var loggingCalendar = Calendar(identifier: .gregorian)
        loggingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = loggingCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 23, minute: 30))!
        let entry = sampleEntry(date: date, dayKey: NutritionDiaryDayKey.make(date, calendar: loggingCalendar))
        try store.saveMeal(entry)
        var viewingCalendar = Calendar(identifier: .gregorian)
        viewingCalendar.timeZone = TimeZone(identifier: "Africa/Johannesburg")!
        let loaded = try XCTUnwrap(store.mealEntries().first)
        XCTAssertEqual(loaded.dayKey, "2026-01-15")
        XCTAssertEqual(NutritionDiaryDayKey.make(loaded.date, calendar: viewingCalendar), "2026-01-16",
                       "the instant may render on another local day; the persisted day key must not follow it")
    }

    func testTotalsAreIdenticalToLegacyCalculation() throws {
        let a = sampleEntry(foodName: "Pap", dayKey: "2026-10-31")
        let b = sampleEntry(foodName: "Chakalaka", dayKey: "2026-10-31", meal: .lunch)
        try store.saveMeal(a)
        try store.saveMeal(b)
        XCTAssertEqual(NutritionDayTotals.calculate(entries: store.mealEntries()),
                       NutritionDayTotals.calculate(entries: [a, b]))
    }

    func testSaveRejectsInvalidEntry() {
        var entry = sampleEntry(foodName: " ")
        entry.quantity = 0
        XCTAssertThrowsError(try store.saveMeal(entry)) { XCTAssertEqual($0 as? FoodJournalStoreError, .invalidEntry) }
        XCTAssertTrue(store.mealEntries().isEmpty)
    }

    func testSaveRejectsDuplicateIdentity() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        XCTAssertThrowsError(try store.saveMeal(entry)) { XCTAssertEqual($0 as? FoodJournalStoreError, .duplicateEntry) }
        XCTAssertEqual(store.mealEntries().count, 1, "a saved meal appears exactly once")
    }

    func testUpdateKeepsIdentityAndOriginalDay() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        var edited = entry
        edited.quantity = 400
        edited.verificationNote = "weighed"
        try store.updateMeal(edited)
        let all = store.mealEntries()
        XCTAssertEqual(all.count, 1, "editing updates the same entry; it never duplicates")
        assertSameEntry(all[0], edited)
        XCTAssertEqual(all[0].dayKey, entry.dayKey, "original local day is preserved")
    }

    func testDeleteRemovesEntryAndPayloadTogether() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        store.deleteMeal(id: entry.id)
        XCTAssertTrue(store.mealEntries().isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<JournalMealPayload>()).isEmpty)
    }

    // MARK: Migration

    func testMigrationImportsPopulatedLegacyStoreVerbatim() throws {
        let entries = [sampleEntry(foodName: "Pap", dayKey: "2026-10-30"),
                       sampleEntry(foodName: "Samp", dayKey: "2026-10-31", meal: .lunch),
                       sampleEntry(foodName: "Chakalaka", dayKey: "2026-10-31")]
        try legacyRepository().save(entries)
        let result = FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                          backupDirectory: backupDir, markerDefaults: defaults)
        XCTAssertEqual(result, .migrated(3))
        let loaded = store.mealEntries()
        XCTAssertEqual(loaded.count, 3)
        for entry in entries {
            assertSameEntry(try XCTUnwrap(loaded.first { $0.id == entry.id }), entry, "migrated entry must be verbatim")
        }
    }

    func testMigrationBacksUpPayloadBeforeRetiringLegacyKey() throws {
        let entries = [sampleEntry()]
        try legacyRepository().save(entries)
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .migrated(1))
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey), "legacy key retired after backup")
        let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            .filter { $0.hasPrefix("nutrition-diary-legacy-") }
        XCTAssertEqual(backups.count, 1, "the original payload survives as a backup file")
        let backupData = try Data(contentsOf: backupDir.appendingPathComponent(backups[0]))
        XCTAssertEqual(try JSONDecoder().decode([NutritionDiaryEntry].self, from: backupData), entries)
        XCTAssertTrue(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }

    func testMigrationIsIdempotentAcrossRunsAndRecovery() throws {
        let entries = [sampleEntry(foodName: "Pap"), sampleEntry(foodName: "Samp")]
        try legacyRepository().save(entries)
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .migrated(2))
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .alreadyMigrated)
        XCTAssertEqual(store.mealEntries().count, 2, "a second run never duplicates a meal")

        // Journal-store recovery scenario: the store is gone but the legacy backup semantics let the
        // migrator repopulate a fresh store from a payload that still exists (never silently lost).
        let freshStore = FoodJournalStore(container: try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try legacyRepository().save(entries)
        defaults.removeObject(forKey: FoodJournalMigration.markerKey)
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: freshStore,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .migrated(2))
        XCTAssertEqual(freshStore.mealEntries().count, 2)
    }

    func testMigrationLeavesUnreadableLegacyUntouched() throws {
        defaults.set(Data("not json".utf8), forKey: NutritionDiaryRepository.storageKey)
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .legacyCorrupt)
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), Data("not json".utf8),
                       "the only copy of an unreadable diary is never touched")
        XCTAssertTrue(store.mealEntries().isEmpty)
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
        // The existing diary recovery still works afterwards; then migration can proceed.
        try legacyRepository().recoverCorruptData()
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .noLegacyData)
    }

    func testMigrationPreservesMalformedRecordsAndReportsHonestly() throws {
        let valid = sampleEntry(foodName: "Pap")
        var malformed = sampleEntry(foodName: "Broken")
        malformed.servings = -1
        try legacyRepository().savePrepared(legacyRepository().prepare([valid, malformed]))
        let result = FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                          backupDirectory: backupDir, markerDefaults: defaults)
        guard case .failed(let message) = result else { return XCTFail("malformed records must be reported, got \(result)") }
        XCTAssertTrue(message.contains("invalid or duplicate"), message)
        XCTAssertNotNil(defaults.data(forKey: NutritionDiaryRepository.storageKey),
                        "malformed records are never silently discarded: the legacy payload stays")
        XCTAssertTrue(try store.readMeals().isEmpty, "invalid input must not create a partial copy")
    }

    func testMigrationFailsWithoutRetiringWhenBackupCannotBeWritten() throws {
        let entries = [sampleEntry()]
        try legacyRepository().save(entries)
        // A regular file where the backup directory must be created makes the backup write fail.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("file".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let result = FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                          backupDirectory: blocker, markerDefaults: defaults)
        guard case .failed = result else { return XCTFail("backup failure must be reported, got \(result)") }
        XCTAssertNotNil(defaults.data(forKey: NutritionDiaryRepository.storageKey),
                        "legacy key is retired only after the backup is proven written")
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }

    func testMigrationWithNoLegacyDiary() {
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: legacyRepository(), store: store, openState: .ok,
                                                            backupDirectory: backupDir, markerDefaults: defaults), .noLegacyData)
    }

    // MARK: Journal store persistence and recovery (R-DATA-01 for the journal container)

    func testJournalStorePersistsMealsAcrossReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fj-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("journal.store")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let make: (ModelConfiguration) throws -> ModelContainer = {
            try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self, configurations: $0)
        }
        let first = FoodJournalStore(container: try make(ModelConfiguration(url: url)))
        try first.saveMeal(sampleEntry())
        let reopened = FoodJournalStore(container: try make(ModelConfiguration(url: url)))
        XCTAssertEqual(reopened.mealEntries().count, 1, "meals survive a container reopen on the same store file")
    }

    func testCorruptJournalStoreIsMovedAsideAndReplacesItself() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fj-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("journal.store")
        try Data(repeating: 0x5A, count: 4096).write(to: url)               // corrupt fixture: not SQLite
        try Data("junk".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        let outcome = StoreRecovery.open(url: url) {
            try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self, configurations: $0)
        }
        XCTAssertTrue(outcome.recovered, "a corrupt journal store is moved aside, never mistaken for an empty journal")
        let backup = try XCTUnwrap(outcome.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "the corrupt store file is preserved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path + "-wal"), "the WAL sidecar is preserved with it")
        let store = FoodJournalStore(container: try XCTUnwrap(outcome.container))
        try store.saveMeal(sampleEntry())
        XCTAssertEqual(store.mealEntries().count, 1, "the recovered store works")
    }

    func testThrowingReadRejectsUnavailableInsteadOfReportingEmpty() {
        XCTAssertThrowsError(try FoodJournalStore(container: nil).readMeals())
    }

    func testConflictingIdentityPreservesLegacyAndUnifiedPayload() throws {
        let id = UUID()
        let canonical = sampleEntry(id: id, foodName: "Existing meal")
        let legacy = sampleEntry(id: id, foodName: "Conflicting legacy meal")
        try store.saveMeal(canonical)
        let repository = legacyRepository()
        try repository.save([legacy])
        let before = defaults.data(forKey: NutritionDiaryRepository.storageKey)
        let result = FoodJournalMigration.migrateIfNeeded(legacy: repository, store: store, openState: .ok,
            backupDirectory: backupDir, markerDefaults: defaults)
        guard case .failed = result else { return XCTFail("Conflict must block retirement") }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), before)
        XCTAssertEqual(try store.readMeals(), [canonical])
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }

    func testBatchInvalidInputDoesNotLeavePendingRows() throws {
        let valid = sampleEntry()
        var invalid = sampleEntry(); invalid.quantity = -1
        XCTAssertThrowsError(try store.importMeals([valid, invalid]))
        try container.mainContext.save()
        XCTAssertTrue(try store.readMeals().isEmpty)
    }

    func testIsolatedSaveFailureLeavesUnrelatedMainContextEditPending() throws {
        enum Failure: Error { case injected }
        container.mainContext.autosaveEnabled = false
        let reflection = Ate.JournalEntry(prompt: "", text: "Unrelated unsaved reflection", state: .balanced)
        container.mainContext.insert(reflection)
        let failing = FoodJournalStore(container: container, writeContext: { _ in throw Failure.injected })
        XCTAssertThrowsError(try failing.saveMeal(sampleEntry()))
        XCTAssertTrue(try store.readMeals().isEmpty)
        XCTAssertTrue(container.mainContext.hasChanges, "A failed meal save must not roll back another screen's draft")
        try container.mainContext.save()
        XCTAssertNotNil(try container.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>()).first { $0.id == reflection.id })
    }

    func testMigrationThenCreateUpdateDeletePreservesIdentityAndHistoricalDay() throws {
        let repository = legacyRepository()
        let old = sampleEntry(dayKey: "2020-01-01")
        try repository.save([old])
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: repository, store: store, openState: .ok,
            backupDirectory: backupDir, markerDefaults: defaults), .migrated(1))
        XCTAssertEqual(try store.readMeals(), [old])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        XCTAssertEqual(FoodJournalMigration.migrateIfNeeded(legacy: repository, store: store, openState: .ok,
            backupDirectory: backupDir, markerDefaults: defaults), .alreadyMigrated)
        var added = sampleEntry(dayKey: "2019-12-31")
        try store.saveMeal(added)
        added.quantity = 100; added.foodName = "Edited meal"
        try store.updateMeal(added)
        XCTAssertEqual(try store.readMeals().first { $0.id == added.id }, added)
        try store.deleteMealSafely(id: old.id)
        XCTAssertEqual(try store.readMeals(), [added])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
    }

    func testOrphanPayloadIsUnreadableAndCannotTriggerLegacyRetirement() throws {
        let entry = sampleEntry()
        try store.saveMeal(entry)
        let row = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>()).first)
        container.mainContext.delete(row); try container.mainContext.save()
        XCTAssertThrowsError(try store.readMeals())
        let repository = legacyRepository(); try repository.save([sampleEntry()])
        guard case .failed = FoodJournalMigration.migrateIfNeeded(legacy: repository, store: store, openState: .ok,
            backupDirectory: backupDir, markerDefaults: defaults) else { return XCTFail("Unreadable store must block migration") }
        XCTAssertNotNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
    }

    func testFallbackCannotImportOrRetireDurableLegacy() throws {
        let legacy = legacyRepository(); let entry = sampleEntry(); try legacy.save([entry])
        let raw = defaults.data(forKey: NutritionDiaryRepository.storageKey)
        guard case .failed = FoodJournalMigration.migrateIfNeeded(legacy: legacy, store: store,
            openState: .inMemoryFallback(error: "test"), backupDirectory: backupDir, markerDefaults: defaults)
            else { return XCTFail("Nondurable open must block retirement") }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
        XCTAssertTrue(try store.readMeals().isEmpty)
    }

    func testDuplicateLegacyIdentityDoesNotImportEitherCopy() throws {
        let legacy = legacyRepository(); let entry = sampleEntry()
        legacy.savePrepared(try legacy.prepare([entry, entry]))
        guard case .failed = FoodJournalMigration.migrateIfNeeded(legacy: legacy, store: store,
            openState: .ok, backupDirectory: backupDir, markerDefaults: defaults)
            else { return XCTFail("Duplicate legacy identities must block import") }
        XCTAssertNotNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        XCTAssertTrue(try store.readMeals().isEmpty)
    }
}
