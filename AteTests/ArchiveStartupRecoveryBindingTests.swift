import XCTest
import SwiftData
import CryptoKit
@testable import Ate

/// Crash-simulation tests for the production startup-recovery binding: real recovery
/// journal on disk, real UserDefaults suites, real goals files, in-memory stores standing
/// in for the on-disk stores (injected, so the "reopened" container is the crashed one).
@MainActor
final class ArchiveStartupRecoveryBindingTests: XCTestCase {
    enum Injected: Error { case failure }

    private struct Rig {
        let root: URL
        let mediaDir: URL
        let lease: POSIXArchiveWriterLease
        let journal: DiskArchiveRecoveryJournal
        let suiteName: String
        let defaults: UserDefaults
        let diary: NutritionDiaryRepository
        let goals: NutritionGoalsRepository
        let container: ModelContainer
        let journalStore: JournalStore
    }

    private func rig() throws -> Rig {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveStartup-" + UUID().uuidString)
        let mediaDir = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let lease = try POSIXArchiveWriterLease(directory: root)
        let suiteName = "ArchiveStartup-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return Rig(root: root, mediaDir: mediaDir, lease: lease,
                   journal: DiskArchiveRecoveryJournal(lease: lease), suiteName: suiteName,
                   defaults: defaults, diary: NutritionDiaryRepository(defaults: defaults),
                   goals: NutritionGoalsRepository(defaults: defaults,
                       storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
                   container: try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
                   journalStore: JournalStore(inMemory: true))
    }

    private func cleanup(_ r: Rig) {
        r.lease.release()
        UserDefaults(suiteName: r.suiteName)?.removePersistentDomain(forName: r.suiteName)
        try? FileManager.default.removeItem(at: r.root)
    }

    private func recover(_ r: Rig) throws {
        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: r.lease, journal: r.journal,
            ownerIdentity: "fixture-owner", defaults: r.defaults, diary: r.diary, goals: r.goals,
            recipeContainer: r.container,
            journalContainer: { try XCTUnwrap(r.journalStore.container) }, mediaDirectory: r.mediaDir)
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func reflectionEntry(_ id: String, text: String = "Dinner") -> JournalArchiveEntry {
        JournalArchiveEntry(id: id, createdAt: Date(timeIntervalSince1970: 1234),
            prompt: "Dinner?", text: text, stateRaw: "future-state", recipeIDs: [],
            journalingSuggestionTitle: nil, momentDate: nil, sourceRaw: "future-source",
            locationName: nil, latitude: nil, longitude: nil, mediaFileNames: [],
            editedAt: nil, kindRaw: "reflection", dayKey: nil, recipeSnapshotsRaw: nil, meal: nil)
    }

    /// Inserts a journal row exactly as JournalArchiveRestore would have written it.
    private func insertRow(_ entry: JournalArchiveEntry, into store: JournalStore) throws {
        let ctx = ModelContext(try XCTUnwrap(store.container)); ctx.autosaveEnabled = false
        let row = Ate.JournalEntry(id: entry.id, createdAt: entry.createdAt, prompt: entry.prompt,
                               text: entry.text, state: nil, recipeIDs: entry.recipeIDs,
                               journalingSuggestionTitle: entry.journalingSuggestionTitle,
                               momentDate: entry.momentDate)
        row.stateRaw = entry.stateRaw; row.sourceRaw = entry.sourceRaw; row.kindRaw = entry.kindRaw
        row.locationName = entry.locationName; row.latitude = entry.latitude; row.longitude = entry.longitude
        row.mediaFileNames = entry.mediaFileNames; row.editedAt = entry.editedAt
        row.dayKey = entry.dayKey; row.recipeSnapshotsRaw = entry.recipeSnapshotsRaw
        ctx.insert(row)
        try ctx.save()
    }

    private func prepareRecord(_ r: Rig, images: [ArchiveRecoveryImage],
                               payload: JournalMediaRecoveryPayload) throws -> UUID {
        let record = ArchiveRecoveryRecord(version: 1, transactionID: UUID(),
            ownerIdentity: "fixture-owner", storeGeneration: r.lease.generation, images: images,
            journalAndMediaRecovery: try JSONEncoder().encode(payload))
        try r.journal.prepare(record)
        return record.transactionID
    }

    private func image(_ component: String, _ before: Codable, _ after: Codable) throws -> ArchiveRecoveryImage {
        ArchiveRecoveryImage(component: component, before: try JSONEncoder().encode(before),
                             after: try JSONEncoder().encode(after))
    }

    private func outerImages(_ r: Rig, before: (ArchiveNutritionImage, ArchiveDefaultsImage, ArchiveRecipeShoppingImage),
                             after: (ArchiveNutritionImage, ArchiveDefaultsImage, ArchiveRecipeShoppingImage)) throws -> [ArchiveRecoveryImage] {
        [try image(ArchiveComponentName.nutrition, before.0, after.0),
         try image(ArchiveComponentName.defaults, before.1, after.1),
         try image(ArchiveComponentName.recipeShopping, before.2, after.2)]
    }

    private func currentImages(_ r: Rig) throws -> (ArchiveNutritionImage, ArchiveDefaultsImage, ArchiveRecipeShoppingImage) {
        (try UnifiedArchiveStartupRecovery.readNutritionImage(diary: r.diary, goals: r.goals),
         UnifiedArchiveStartupRecovery.readDefaultsImage(defaults: r.defaults),
         try UnifiedArchiveImportBinding.snapshotRecipeShopping(r.container))
    }

    // MARK: - uncommitted: exact before-image restoration

    func testInterruptedApplyRestoresExactBeforeImagesEverywhere() throws {
        let r = try rig(); defer { cleanup(r) }
        // Before-state.
        let diaryBytes = try JSONEncoder().encode([
            NutritionDiaryEntry(foodName: "Inhloko", date: Date(timeIntervalSince1970: 1_762_000_000),
                meal: .dinner, quantity: 1, quantityUnit: "portion", servings: 1,
                source: .userProvided, sourceName: "Me", nutrientsPerServing: NutritionSnapshot(),
                dayKey: "2026-11-08")])
        r.defaults.set(diaryBytes, forKey: NutritionDiaryRepository.storageKey)
        try r.goals.storage.write(JSONEncoder().encode(DailyNutritionGoals(
            energyKcal: 2000, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)))
        let settingsBytes = try JSONEncoder().encode(AppSettings(units: .metric))
        r.defaults.set(settingsBytes, forKey: ArchiveDefaultsParticipant.settingsKey)
        let ctx = ModelContext(r.container); ctx.autosaveEnabled = false
        ctx.insert(RecipeEntity(id: "r-old", createdAt: 111, position: 0, json: Data("{\"id\":\"r-old\",junk".utf8)))
        try ctx.save()
        let before = try currentImages(r)

        // After-state the interrupted transaction was heading for.
        let after = (ArchiveNutritionImage(diary: try JSONEncoder().encode([
            NutritionDiaryEntry(foodName: "Other", date: Date(timeIntervalSince1970: 1_762_000_100),
                meal: .lunch, quantity: 1, quantityUnit: "cup", servings: 1,
                source: .userProvided, sourceName: "Me", nutrientsPerServing: NutritionSnapshot(),
                dayKey: "2026-11-09")]), goalFile: nil, legacyGoals: nil),
            ArchiveDefaultsImage(settings: try JSONEncoder().encode(AppSettings(units: .imperial)),
                                 timer: try JSONEncoder().encode(TimerPrefs()), syncMeta: nil),
            ArchiveRecipeShoppingImage(recipes: [ArchiveRawRecipeImage(id: "r-new", createdAt: 1,
                position: 0, json: try JSONEncoder().encode(RecipeCard(id: "r-new",
                    ingredients: [Ingredient(name: "Rice", quantity: 1, unit: "kg")],
                    steps: [Step(order: 0, instruction: "Cook")], createdAt: 1)))], shopping: []))

        let id = try prepareRecord(r, images: outerImages(r, before: before, after: after),
                                   payload: JournalMediaRecoveryPayload(version: 1, entries: [], media: [:]))
        try r.journal.transition(id, to: .applying)

        // Process death mid-apply: every component sits at its after-value.
        try UnifiedArchiveStartupRecovery.restoreNutrition(after.0, diary: r.diary, goals: r.goals)
        try UnifiedArchiveStartupRecovery.restoreDefaults(after.1, defaults: r.defaults)
        try UnifiedArchiveStartupRecovery.restoreRecipeShopping(after.2, container: r.container)

        try recover(r)

        let now = try currentImages(r)
        XCTAssertEqual(now.0, before.0, "diary/goals bytes restored exactly")
        XCTAssertEqual(now.1, before.1, "settings/timer restored exactly")
        XCTAssertEqual(now.2, before.2, "recipe store restored to before-image")
        XCTAssertEqual(r.lease.generation, 0, "no commit, no generation advance")
        XCTAssertTrue(try r.journal.transactions().isEmpty, "transaction retired after rollback")
    }

    // MARK: - committed: verify after, finish, complete the generation advance

    func testCommittedCrashBeforeGenerationAdvanceVerifiesFinishesAndAdvancesOnce() throws {
        let r = try rig(); defer { cleanup(r) }
        let mediaBytes = Data("photo".utf8)
        let entry = reflectionEntry("j-1")
        let payload = JournalMediaRecoveryPayload(version: 1, entries: [entry],
                                                  media: ["m-1.jpg": sha(mediaBytes)])
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before), payload: payload)
        try r.journal.transition(id, to: .applying)

        // The transaction fully applied, committed, then the process died before
        // commitGeneration and before media finish: staging leftover remains.
        try insertRow(entry, into: r.journalStore)
        try mediaBytes.write(to: r.mediaDir.appendingPathComponent("m-1.jpg"))
        let staging = r.mediaDir.appendingPathComponent(".ate-restore-4291B6C9-3A5B-4C63-9A4B-5D0F2C63E001")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("receipt".utf8).write(to: staging.appendingPathComponent(".receipt-x.json"))
        try r.journal.transition(id, to: .committed)

        try recover(r)

        XCTAssertEqual(r.lease.generation, 1, "committed unit's generation advance completed exactly once")
        XCTAssertTrue(try r.journal.transactions().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path), "staging leftover cleaned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.mediaDir.appendingPathComponent("m-1.jpg").path),
                      "committed media is kept")
        let rows = try ModelContext(try XCTUnwrap(r.journalStore.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.map(\.id), ["j-1"], "committed entries are kept")
    }

    func testCommittedCrashAfterGenerationAdvanceDoesNotDoubleCommit() throws {
        let r = try rig(); defer { cleanup(r) }
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
                                   payload: JournalMediaRecoveryPayload(version: 1, entries: [], media: [:]))
        try r.journal.transition(id, to: .applying)
        try r.journal.transition(id, to: .committed)
        try r.lease.commitGeneration(1) // advance landed; retire did not

        try recover(r)

        XCTAssertEqual(r.lease.generation, 1, "never re-commits an already-advanced generation")
        XCTAssertTrue(try r.journal.transactions().isEmpty)
    }

    // MARK: - the generation commit lands inside the retire boundary

    /// Crash BEFORE the pending generation commit inside beforeRetire: the transaction
    /// stays unresolved with its committed marker, the generation is unmoved, and the next
    /// startup completes the advance exactly once.
    func testCrashInsideBeforeRetireBeforeCommitLeavesPendingAdvanceForNextStartup() throws {
        let r = try rig(); defer { cleanup(r) }
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
                                   payload: JournalMediaRecoveryPayload(version: 1, entries: [], media: [:]))
        try r.journal.transition(id, to: .applying)
        try r.journal.transition(id, to: .committed)

        let recovery = UnifiedArchiveStartupRecovery.makeRecovery(journal: r.journal, defaults: r.defaults,
            diary: r.diary, goals: r.goals, recipeContainer: r.container,
            journalContainer: { try XCTUnwrap(r.journalStore.container) }, mediaDirectory: r.mediaDir)
        XCTAssertThrowsError(try recovery.run(ownerIdentity: "fixture-owner", beforeRetire: { _ in
            throw Injected.failure // process died before the pending commitGeneration
        }))
        XCTAssertEqual(r.lease.generation, 0, "no advance landed")
        XCTAssertEqual(try r.journal.transactions(), [id], "transaction still unresolved")

        try recover(r) // next startup: the pendingAdvance path completes it exactly once
        XCTAssertEqual(r.lease.generation, 1)
        XCTAssertTrue(try r.journal.transactions().isEmpty)
    }

    /// Crash AFTER the pending generation commit but BEFORE the retire: the next startup
    /// retires via the authorized-advance path and never re-commits the generation.
    func testCrashInsideBeforeRetireAfterCommitRetiresWithoutReAdvancing() throws {
        let r = try rig(); defer { cleanup(r) }
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
                                   payload: JournalMediaRecoveryPayload(version: 1, entries: [], media: [:]))
        try r.journal.transition(id, to: .applying)
        try r.journal.transition(id, to: .committed)

        let recovery = UnifiedArchiveStartupRecovery.makeRecovery(journal: r.journal, defaults: r.defaults,
            diary: r.diary, goals: r.goals, recipeContainer: r.container,
            journalContainer: { try XCTUnwrap(r.journalStore.container) }, mediaDirectory: r.mediaDir)
        XCTAssertThrowsError(try recovery.run(ownerIdentity: "fixture-owner", beforeRetire: { _ in
            try r.lease.commitGeneration(r.lease.generation + 1) // advance landed...
            throw Injected.failure // ...then the process died before the retire
        }))
        XCTAssertEqual(r.lease.generation, 1)
        XCTAssertEqual(try r.journal.transactions(), [id], "transaction still unresolved")

        try recover(r) // next startup: authorizedAdvance retires, never re-commits
        XCTAssertEqual(r.lease.generation, 1)
        XCTAssertTrue(try r.journal.transactions().isEmpty)
    }

    // MARK: - foreign writes are preserved and surfaced

    func testForeignJournalEditBlocksCompensationAndIsPreserved() throws {
        let r = try rig(); defer { cleanup(r) }
        let planned = reflectionEntry("j-1", text: "imported text")
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
            payload: JournalMediaRecoveryPayload(version: 1, entries: [planned], media: [:]))
        try r.journal.transition(id, to: .applying)
        try insertRow(planned, into: r.journalStore)
        // Another writer edited the imported row before the crash.
        let ctx = ModelContext(try XCTUnwrap(r.journalStore.container))
        let row = try XCTUnwrap(ctx.fetch(FetchDescriptor<Ate.JournalEntry>()).first { $0.id == "j-1" })
        row.text = "edited elsewhere"
        try ctx.save()

        XCTAssertThrowsError(try recover(r)) { error in
            guard case ArchiveRestoreFailure.recoveryRequired = error else {
                return XCTFail("expected recoveryRequired, got \(error)")
            }
        }
        let kept = try XCTUnwrap(ModelContext(try XCTUnwrap(r.journalStore.container))
            .fetch(FetchDescriptor<Ate.JournalEntry>()).first { $0.id == "j-1" })
        XCTAssertEqual(kept.text, "edited elsewhere", "foreign edit is never overwritten")
        XCTAssertEqual(try r.journal.transactions(), [id], "evidence retained")
    }

    func testForeignMediaContentBlocksRemovalAndIsPreserved() throws {
        let r = try rig(); defer { cleanup(r) }
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
            payload: JournalMediaRecoveryPayload(version: 1, entries: [],
                                                 media: ["m-1.jpg": sha(Data("ours".utf8))]))
        try r.journal.transition(id, to: .applying)
        let foreign = Data("someone else's file".utf8)
        try foreign.write(to: r.mediaDir.appendingPathComponent("m-1.jpg"))

        XCTAssertThrowsError(try recover(r)) { error in
            guard case ArchiveRestoreFailure.recoveryRequired = error else {
                return XCTFail("expected recoveryRequired, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: r.mediaDir.appendingPathComponent("m-1.jpg")), foreign)
        XCTAssertEqual(try r.journal.transactions(), [id], "evidence retained")
    }

    // MARK: - admission blocking

    func testOwnerMismatchBlocksAdmissionAndRunsNoHandler() throws {
        let r = try rig(); defer { cleanup(r) }
        let diaryBytes = Data("original".utf8)
        r.defaults.set(diaryBytes, forKey: NutritionDiaryRepository.storageKey)
        let before = try currentImages(r)
        let id = try prepareRecord(r, images: outerImages(r, before: before, after: before),
                                   payload: JournalMediaRecoveryPayload(version: 1, entries: [], media: [:]))
        try r.journal.transition(id, to: .applying)

        XCTAssertThrowsError(try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: r.lease,
            journal: r.journal, ownerIdentity: "other-owner", defaults: r.defaults, diary: r.diary,
            goals: r.goals, recipeContainer: r.container,
            journalContainer: { try XCTUnwrap(r.journalStore.container) }, mediaDirectory: r.mediaDir))
        XCTAssertEqual(r.defaults.data(forKey: NutritionDiaryRepository.storageKey), diaryBytes,
                       "no handler ran")
        XCTAssertEqual(try r.journal.transactions(), [id], "evidence retained")
    }

    func testCleanStartupWithNoTransactionAdvancesNothing() throws {
        let r = try rig(); defer { cleanup(r) }
        try recover(r)
        XCTAssertEqual(r.lease.generation, 0)
        XCTAssertTrue(try r.journal.transactions().isEmpty)
    }
}
