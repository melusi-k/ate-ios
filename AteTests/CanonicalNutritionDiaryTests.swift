import XCTest
@testable import Ate

@MainActor
final class CanonicalNutritionDiaryTests: XCTestCase, Sendable {
    private var suite: String!
    private var defaults: UserDefaults!
    private var backup: URL!
    private var repository: NutritionDiaryRepository!
    private var repair: LegacyDiaryRepair!
    private var coordinator: FoodJournalCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        suite = "CanonicalNutritionDiaryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        backup = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        repository = NutritionDiaryRepository(defaults: defaults, backupDirectory: backup)
        repair = LegacyDiaryRepair(repository: repository, backupDirectory: backup)
        coordinator = FoodJournalCoordinator(journal: JournalStore(inMemory: true),
                                             legacy: repository,
                                             markerDefaults: defaults,
                                             backupDirectory: backup)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: backup)
        defaults = nil
        repository = nil
        repair = nil
        coordinator = nil
        try await super.tearDown()
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeController(selectedDayKey: String = "2026-11-04") -> NutritionDiaryController {
        NutritionDiaryController(coordinator: coordinator,
                                 goalsRepository: NutritionGoalsRepository(defaults: defaults),
                                 repair: repair,
                                 selectedDayKey: selectedDayKey,
                                 calendar: testCalendar)
    }

    private func makeEntry(id: UUID = UUID(), foodName: String = "Pap", dayKey: String = "2026-11-04",
                           date: Date = Date(timeIntervalSince1970: 1_800_000_000),
                           meal: NutritionMeal = .lunch, servings: Double = 1,
                           energy: Double? = 200, protein: Double? = 10) -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: foodName, date: date, meal: meal, quantity: 1,
                            quantityUnit: "portion", servings: servings, source: .userProvided,
                            sourceName: "You",
                            nutrientsPerServing: NutritionSnapshot(energyKcal: energy, proteinGrams: protein,
                                                                   carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
                            dayKey: dayKey)
    }

    func testAddUpdateDeleteReloadsFromCanonicalStore() throws {
        let controller = makeController()
        controller.reload()
        XCTAssertEqual(controller.entries, [])
        XCTAssertNil(controller.issue)

        let first = makeEntry(date: Date(timeIntervalSince1970: 1_800_000_000))
        let second = makeEntry(foodName: "Rice", date: Date(timeIntervalSince1970: 1_800_003_600))
        try controller.add(first)
        try controller.add(second)
        // Canonical order: newer time first within the same day.
        XCTAssertEqual(controller.entries, [second, first])

        var changed = first
        changed.foodName = "Changed pap"
        try controller.update(changed)
        XCTAssertEqual(controller.entries, [second, changed])
        XCTAssertEqual(controller.entries.last?.id, first.id)

        try controller.delete(id: second.id)
        XCTAssertEqual(controller.entries, [changed])
        XCTAssertNil(controller.issue)
    }

    func testEditPreservesIdentityInstantAndUnknownNutrients() throws {
        let original = makeEntry(foodName: "Pap", energy: 200, protein: nil)
        var draft = NutritionDiaryEntryDraft(entry: original)
        // Unknown nutrients stay blank, stored values become stable editable text.
        XCTAssertEqual(draft.nutrientText[.protein], "")
        XCTAssertEqual(draft.nutrientText[.energy], "200")
        XCTAssertEqual(draft.quantity, "1")

        draft.foodName = "Edited pap"
        let parsed = draft.parsedEntry(existing: original, calendar: testCalendar)
        guard case .success(let edited) = parsed else { return XCTFail("edit draft must parse") }
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.date, original.date)
        XCTAssertEqual(edited.dayKey, original.dayKey)
        XCTAssertEqual(edited.foodName, "Edited pap")
        XCTAssertEqual(edited.nutrientsPerServing.energyKcal, 200)
        XCTAssertNil(edited.nutrientsPerServing.proteinGrams)
    }

    func testDeliberateDayMoveChangesOnlyDayKey() throws {
        let original = makeEntry()
        var draft = NutritionDiaryEntryDraft(entry: original)
        draft.dayKey = "2026-11-05"
        guard case .success(let moved) = draft.parsedEntry(existing: original, calendar: testCalendar) else {
            return XCTFail("day move must parse")
        }
        XCTAssertEqual(moved.dayKey, "2026-11-05")
        XCTAssertEqual(moved.date, original.date)
        XCTAssertEqual(moved.id, original.id)

        let controller = makeController()
        try controller.add(original)
        try controller.update(moved)
        XCTAssertEqual(controller.entries, [moved])
        XCTAssertTrue(controller.dayEntries.isEmpty)
        controller.selectedDayKey = "2026-11-05"
        XCTAssertEqual(controller.dayEntries, [moved])
    }

    func testDraftValidationFailuresAreTypedAndKeepTheDraftIntact() {
        let dayKey = "2026-11-04"
        var draft = NutritionDiaryEntryDraft(dayKey: dayKey)
        draft.foodName = "Pap"

        draft.quantity = "0"
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidAmounts))
        draft.quantity = "abc"
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidAmounts))
        draft.quantity = "1"
        draft.servings = "-1"
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidAmounts))
        draft.servings = "1"

        draft.nutrientText = [.energy: "not a number"]
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidNutrient))
        draft.nutrientText = [.energy: "-5"]
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidNutrient))
        draft.nutrientText = [:]

        draft.foodName = "   "
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidEntry))
        draft.foodName = "Pap"

        // Strict calendar days: February 30 and month 13 can never be smuggled in.
        draft.dayKey = "2026-02-30"
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidEntry))
        draft.dayKey = "2026-13-01"
        XCTAssertEqual(draft.parsedEntry(calendar: testCalendar), .failure(.invalidEntry))
        draft.dayKey = dayKey

        guard case .success(let entry) = draft.parsedEntry(calendar: testCalendar) else {
            return XCTFail("valid draft must parse")
        }
        XCTAssertEqual(entry.dayKey, dayKey)
        XCTAssertEqual(entry.date, NutritionDiaryDayKey.date(for: dayKey, calendar: testCalendar))
        XCTAssertTrue(entry.nutrientsPerServing.energyKcal == nil)
    }

    func testBlockedInvalidLegacyRoutesToRepairThenRepairAndRetryRecovers() throws {
        var invalid = makeEntry()
        invalid.foodName = ""
        // Bypass repository validation solely to model an older invalid on-disk payload.
        let raw = try JSONEncoder().encode([invalid])
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)

        let controller = makeController()
        controller.reload()
        XCTAssertEqual(controller.issue, .legacyRepairNeeded(reason: "invalid or duplicate legacy records preserved; no meals imported"))
        XCTAssertEqual(controller.entries, [])

        // Writes are blocked with the typed error; nothing reaches the canonical store or the legacy key.
        XCTAssertThrowsError(try controller.add(makeEntry())) {
            XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError,
                           .migrationFailed("invalid or duplicate legacy records preserved; no meals imported"))
        }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)

        var fixed = invalid
        fixed.foodName = "Fixed pap"
        let snapshot = try repair.snapshot()
        XCTAssertEqual(snapshot.invalidIndices, [0])
        try repair.replace(index: 0, with: fixed, in: snapshot)

        XCTAssertTrue(controller.retry())
        XCTAssertNil(controller.issue)
        XCTAssertEqual(controller.entries, [fixed])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        XCTAssertTrue(defaults.bool(forKey: FoodJournalMigration.markerKey))

        // The diary is writable again after recovery.
        let extra = makeEntry(foodName: "Rice", date: Date(timeIntervalSince1970: 1_800_003_600))
        try controller.add(extra)
        XCTAssertEqual(controller.entries, [extra, fixed])
    }

    func testUndecodableLegacyRoutesToRepairResetThenRetryRecovers() throws {
        let raw = Data("not a diary".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)

        let controller = makeController()
        controller.reload()
        guard case .legacyRepairNeeded = controller.issue else { return XCTFail("undecodable legacy must route to repair") }
        XCTAssertThrowsError(try controller.add(makeEntry())) {
            XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt)
        }
        XCTAssertThrowsError(try controller.update(makeEntry())) {
            XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt)
        }
        XCTAssertThrowsError(try controller.delete(id: UUID())) {
            XCTAssertEqual($0 as? FoodJournalCoordinator.AccessError, .legacyCorrupt)
        }
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)

        try repair.backUpAndResetUndecodableData()
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        let backups = try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), raw)

        XCTAssertTrue(controller.retry())
        XCTAssertNil(controller.issue)
        XCTAssertEqual(controller.entries, [])

        let entry = makeEntry()
        try controller.add(entry)
        XCTAssertEqual(controller.entries, [entry])
    }

    func testClassificationMatchesActualLegacyContent() throws {
        let controller = makeController()
        // No legacy data at all: repair cannot help, only retry is honest.
        XCTAssertEqual(controller.classify(FoodJournalCoordinator.AccessError.migrationFailed("journal is not durably available")),
                       .migrationRetryNeeded(reason: "journal is not durably available"))
        XCTAssertEqual(controller.classify(FoodJournalCoordinator.AccessError.legacyCorrupt),
                       .legacyRepairNeeded(reason: "The older diary couldn't be decoded. Repair it below, then retry."))

        // Fully valid legacy present (the normal pre-migration case): an environmental failure -
        // durability, read, import, verification or backup - is retry-only with the real reason.
        // Routing it to repair would be a dead end: the repair view would list nothing and its
        // reset refuses decodable data.
        let valid = makeEntry()
        try repository.save([valid])
        XCTAssertEqual(controller.classify(FoodJournalCoordinator.AccessError.migrationFailed("journal is not durably available")),
                       .migrationRetryNeeded(reason: "journal is not durably available"))
        XCTAssertEqual(controller.classify(FoodJournalCoordinator.AccessError.migrationFailed("backup failed: disk full")),
                       .migrationRetryNeeded(reason: "backup failed: disk full"))

        // Duplicate identities in an otherwise valid payload need the repair route (indexed removal).
        defaults.set(try JSONEncoder().encode([valid, valid]), forKey: NutritionDiaryRepository.storageKey)
        guard case .legacyRepairNeeded = controller.classify(
            FoodJournalCoordinator.AccessError.migrationFailed("invalid or duplicate legacy records preserved; no meals imported"))
        else { return XCTFail("duplicate legacy rows must classify as repairable") }

        // Decodable-but-invalid legacy present: the repair route owns it.
        var invalid = makeEntry()
        invalid.foodName = ""
        defaults.set(try JSONEncoder().encode([invalid]), forKey: NutritionDiaryRepository.storageKey)
        guard case .legacyRepairNeeded = controller.classify(
            FoodJournalCoordinator.AccessError.migrationFailed("invalid or duplicate legacy records preserved; no meals imported"))
        else { return XCTFail("decodable invalid legacy must classify as repairable") }

        // Undecodable legacy present: same repair route (the repair view owns the reset path).
        defaults.set(Data("raw".utf8), forKey: NutritionDiaryRepository.storageKey)
        guard case .legacyRepairNeeded = controller.classify(
            FoodJournalCoordinator.AccessError.migrationFailed("any")) else { return XCTFail("undecodable legacy must classify as repairable") }

        // Non-coordinator failures are honest read failures, never an empty diary.
        guard case .readFailed = controller.classify(FoodJournalStoreError.unreadableStore) else {
            return XCTFail("store failures must classify as readFailed")
        }
    }

    func testValidLegacyEnvironmentalBackupFailureRoutesToRetryAndRecoversIdempotently() throws {
        // A backup directory whose parent is a plain file cannot be created: the migration imports
        // and verifies but fails at the backup step, leaving the legacy payload and marker untouched.
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalDiary-blocker-\(UUID().uuidString)")
        try Data("blocker".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let journal = JournalStore(inMemory: true)
        let blockedCoordinator = FoodJournalCoordinator(
            journal: journal, legacy: repository, markerDefaults: defaults,
            backupDirectory: blockingFile.appendingPathComponent("backups", isDirectory: true))
        let controller = NutritionDiaryController(coordinator: blockedCoordinator,
                                                  goalsRepository: NutritionGoalsRepository(defaults: defaults),
                                                  repair: repair, selectedDayKey: "2026-11-04", calendar: testCalendar)
        let valid = makeEntry()
        try repository.save([valid])
        controller.reload()
        guard case .migrationRetryNeeded(let reason) = controller.issue else {
            return XCTFail("environmental backup failure with valid legacy must route to retry, not repair")
        }
        XCTAssertTrue(reason.hasPrefix("backup failed"))
        XCTAssertEqual(controller.entries, [])
        XCTAssertNotNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))

        // Once the environment is fixed, the same retry path migrates idempotently: the meal
        // imported before the backup failure is not duplicated, then the legacy key retires.
        let fixedCoordinator = FoodJournalCoordinator(journal: journal, legacy: repository,
                                                      markerDefaults: defaults, backupDirectory: backup)
        let fixedController = NutritionDiaryController(coordinator: fixedCoordinator,
                                                       goalsRepository: NutritionGoalsRepository(defaults: defaults),
                                                       repair: repair, selectedDayKey: "2026-11-04", calendar: testCalendar)
        XCTAssertTrue(fixedController.retry())
        XCTAssertNil(fixedController.issue)
        XCTAssertEqual(fixedController.entries, [valid])
        XCTAssertNil(defaults.data(forKey: NutritionDiaryRepository.storageKey))
        XCTAssertTrue(defaults.bool(forKey: FoodJournalMigration.markerKey))
    }

    func testJournalOpenStateIsExposedForHonestPresentation() {
        let controller = makeController()
        // The controller passes the actual state through; composition owns the banner.
        XCTAssertEqual(controller.journalOpenState, coordinator.openState)
        // An isolated in-memory journal is .ok by design - never a production fallback claim.
        XCTAssertEqual(controller.journalOpenState, .ok)
    }

    func testWeekScopingIsHalfOpenAndKeepsUnknownTotalsUnavailable() throws {
        let calendar = testCalendar
        let selected = try XCTUnwrap(NutritionDiaryDayKey.date(for: "2026-11-04", calendar: calendar))
        let week = try XCTUnwrap(NutritionWeekTotals.weekInterval(containing: selected, calendar: calendar))
        let firstDay = NutritionDiaryDayKey.make(week.start, calendar: calendar)
        let lastDay = NutritionDiaryDayKey.make(week.end.addingTimeInterval(-86_400), calendar: calendar)
        let nextWeekDay = NutritionDiaryDayKey.make(week.end, calendar: calendar)

        let controller = makeController()
        let startEntry = makeEntry(foodName: "Week start", dayKey: firstDay, energy: 100, protein: 10)
        let endEntry = makeEntry(foodName: "Week end", dayKey: lastDay, energy: 50, protein: 5)
        let unknownProtein = makeEntry(foodName: "Unknown protein", dayKey: firstDay, energy: 1, protein: nil)
        let nextWeek = makeEntry(foodName: "Next week", dayKey: nextWeekDay, energy: 999, protein: 99)
        for entry in [startEntry, endEntry, unknownProtein, nextWeek] { try controller.add(entry) }

        let weekIDs = Set(controller.weekEntries.map(\.id))
        XCTAssertTrue(weekIDs.contains(startEntry.id))
        XCTAssertTrue(weekIDs.contains(endEntry.id))
        XCTAssertTrue(weekIDs.contains(unknownProtein.id))
        // The first day of the following week belongs to that week, never to this one.
        XCTAssertFalse(weekIDs.contains(nextWeek.id))

        XCTAssertEqual(controller.weekTotals.value(for: .energy), 151)
        // One unknown value in the week makes that week's total honestly unavailable, never an estimate.
        XCTAssertNil(controller.weekTotals.value(for: .protein))
        // Day scoping is unaffected by the week logic.
        XCTAssertEqual(controller.dayEntries, [])
        controller.selectedDayKey = firstDay
        XCTAssertEqual(Set(controller.dayEntries.map(\.id)), [startEntry.id, unknownProtein.id])

        let currentWeek = NutritionWeekTotals.weekInterval(containing: .now, calendar: calendar)
        XCTAssertEqual(controller.selectedWeekIsCurrent, week.start == currentWeek?.start)
    }

    func testBlockedLegacyLeavesCanonicalStoreUnwrittenAcrossAllMutations() throws {
        let raw = Data("undecodable".utf8)
        defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        let controller = makeController()
        controller.reload()

        XCTAssertThrowsError(try controller.add(makeEntry()))
        XCTAssertThrowsError(try controller.update(makeEntry()))
        XCTAssertThrowsError(try controller.delete(id: UUID()))
        XCTAssertEqual(controller.entries, [])
        XCTAssertNotNil(controller.issue)
        XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertFalse(defaults.bool(forKey: FoodJournalMigration.markerKey))
        // After the failure the controller reloads stayed honest: still blocked, never an empty diary.
        guard case .legacyRepairNeeded = controller.issue else { return XCTFail("blocked legacy must keep the repair route") }
    }
}
