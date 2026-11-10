import XCTest
import SwiftData
import CryptoKit
@testable import Ate

@MainActor
final class ArchiveImportBindingTests: XCTestCase {
    enum Injected: Error { case failure }

    private struct Fixture {
        let root: URL
        let controlDir: URL
        let mediaDir: URL
        let suiteName: String
        let defaults: UserDefaults
        let container: ModelContainer
        let journalStore: JournalStore
        let session: ArchiveStandaloneImportSession
        let binding: UnifiedArchiveImportBinding
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveImport-" + UUID().uuidString)
        let controlDir = root.appendingPathComponent("control")
        let mediaDir = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let suiteName = "ArchiveImport-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let journalStore = JournalStore(inMemory: true)
        let session = try ArchiveStandaloneImportSession(controlDirectory: controlDir, resetPending: { false })
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")))
        let binding = try UnifiedArchiveImportBinding(lease: session.lease,
            recoveryJournal: session.recoveryJournal, ownerIdentity: "fixture-owner",
            journal: journalStore, recipeContainer: container,
            diary: NutritionDiaryRepository(defaults: defaults), goals: goals,
            defaults: defaults, mediaDirectory: mediaDir)
        return Fixture(root: root, controlDir: controlDir, mediaDir: mediaDir, suiteName: suiteName,
                       defaults: defaults, container: container, journalStore: journalStore,
                       session: session, binding: binding)
    }

    private func cleanup(_ f: Fixture) {
        f.session.lease.release()
        UserDefaults(suiteName: f.suiteName)?.removePersistentDomain(forName: f.suiteName)
        try? FileManager.default.removeItem(at: f.root)
    }

    private func card(_ id: String, empty: Bool = false) -> RecipeCard {
        RecipeCard(id: id, title: "Recipe " + id,
                   ingredients: empty ? [] : [Ingredient(name: "Pap", quantity: 1, unit: "cup")],
                   steps: empty ? [] : [Step(order: 0, instruction: "Cook")], createdAt: 1234)
    }

    private func item(_ id: String) -> ShoppingItem { ShoppingItem(id: id, name: "Rice", quantity: 1, unit: "kg") }

    private func diaryEntry(id: UUID = UUID(), food: String = "Pap", dayKey: String = "2026-11-09") -> NutritionDiaryEntry {
        NutritionDiaryEntry(id: id, foodName: food, date: Date(timeIntervalSince1970: 1_762_000_000),
            meal: .lunch, quantity: 1, quantityUnit: "cup", servings: 1,
            source: .userProvided, sourceName: "Me",
            nutrientsPerServing: NutritionSnapshot(), dayKey: dayKey)
    }

    private func reflectionEntry(_ id: String, media: [String] = []) -> JournalArchiveEntry {
        JournalArchiveEntry(id: id, createdAt: Date(timeIntervalSince1970: 1234),
            prompt: "Dinner?", text: "Dinner", stateRaw: "future-state", recipeIDs: ["r-old"],
            journalingSuggestionTitle: nil, momentDate: nil, sourceRaw: "future-source",
            locationName: "Home", latitude: -26.2, longitude: 28.0, mediaFileNames: media,
            editedAt: Date(timeIntervalSince1970: 1250), kindRaw: "reflection",
            dayKey: nil, recipeSnapshotsRaw: "{future", meal: nil)
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func archive(f: Fixture, journal: JournalArchive? = nil) throws -> AteUnifiedArchive {
        let mediaBytes = Data("photo".utf8)
        let journalSection = journal ?? JournalArchive(
            entries: [reflectionEntry("j-new", media: ["m-1.jpg"])],
            media: ["m-1.jpg": mediaBytes], mediaSHA256: ["m-1.jpg": sha(mediaBytes)])
        return AteUnifiedArchive(recipes: [card("r-new")], shoppingItems: [item("s-new")],
            nutritionDiaryEntries: [diaryEntry()],
            nutritionGoals: DailyNutritionGoals(energyKcal: 2500, proteinGrams: nil,
                carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
            appSettings: AppSettings(onDeviceOnly: true), timerPreferences: TimerPrefs(),
            journal: journalSection)
    }

    // MARK: - happy path

    func testCleanImportAppliesEverySectionAndAdvancesGenerationOnce() throws {
        let f = try fixture(); defer { cleanup(f) }
        // Pre-existing local state the import must merge with, never erase.
        let seededRecipe = Data("{\"id\":\"r-old\",trailing-junk".utf8) // undecodable: survives verbatim
        let ctx = ModelContext(f.container); ctx.autosaveEnabled = false
        ctx.insert(RecipeEntity(id: "r-old", createdAt: 111, position: 0, json: seededRecipe))
        ctx.insert(ShoppingEntity(id: "s-old", position: 0, json: try JSONEncoder().encode(item("s-old"))))
        try ctx.save()
        let existingDiary = diaryEntry(food: "Inhloko")
        let diary = NutritionDiaryRepository(defaults: f.defaults)
        try diary.savePrepared(diary.prepare([existingDiary]))

        // A meal-kind entry proves the structured payload round-trips through the binding.
        let mealID = UUID()
        let mealEntry = JournalArchiveEntry(id: mealID.uuidString,
            createdAt: Date(timeIntervalSince1970: 1_762_000_000),
            prompt: "", text: "Pap and inhloko", stateRaw: "", recipeIDs: [],
            journalingSuggestionTitle: nil, momentDate: nil, sourceRaw: "ate",
            locationName: nil, latitude: nil, longitude: nil, mediaFileNames: [],
            editedAt: nil, kindRaw: "meal", dayKey: "2026-11-09", recipeSnapshotsRaw: nil,
            meal: diaryEntry(id: mealID))
        let mediaBytes = Data("photo".utf8)
        let journalSection = JournalArchive(
            entries: [reflectionEntry("j-new", media: ["m-1.jpg"]), mealEntry],
            media: ["m-1.jpg": mediaBytes], mediaSHA256: ["m-1.jpg": sha(mediaBytes)])
        let value = try archive(f: f, journal: journalSection)
        let result = try f.session.importArchive(value, binding: f.binding)

        XCTAssertEqual(result.journalEntriesAdded, 2)
        XCTAssertEqual(result.journalEntriesSkippedExisting, 0)
        XCTAssertEqual(f.session.lease.generation, 1, "exactly one advance for the committed unit")
        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty, "committed transaction retired")

        let recipes = try UnifiedArchiveImportBinding.snapshotRecipeShopping(f.container)
        XCTAssertEqual(recipes.recipes.map(\.id), ["r-new", "r-old"], "new recipes prepend")
        XCTAssertEqual(recipes.recipes.last?.json, seededRecipe, "existing bytes verbatim")
        XCTAssertEqual(recipes.shopping.map(\.id), ["s-old", "s-new"])
        switch diary.loadState() {
        case .loaded(let entries): XCTAssertEqual(Set(entries.map(\.id)), Set([existingDiary.id, value.nutritionDiaryEntries[0].id]))
        default: XCTFail("diary must be readable after import")
        }
        XCTAssertEqual(try f.binding.goals.load().energyKcal, 2500)
        XCTAssertNil(f.defaults.data(forKey: DailyNutritionGoals.defaultsKey), "legacy goals key removed")
        XCTAssertEqual(f.defaults.data(forKey: ArchiveDefaultsParticipant.settingsKey),
                       try JSONEncoder().encode(AppSettings(onDeviceOnly: true)))
        let journalContext = ModelContext(try XCTUnwrap(f.journalStore.container))
        let rows = try journalContext.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(Set(rows.map(\.id)), Set(["j-new", mealID.uuidString]))
        XCTAssertEqual(rows.first { $0.id == "j-new" }?.stateRaw, "future-state", "raw fields preserved verbatim")
        let payloads = try journalContext.fetch(FetchDescriptor<JournalMealPayload>())
        XCTAssertEqual(payloads.map(\.entryID), [mealID.uuidString], "meal payload attached to its entry")
        let meals = try FoodJournalStore(container: XCTUnwrap(f.journalStore.container)).readMeals()
        XCTAssertEqual(meals.map(\.id), [mealID])
        let published = try Data(contentsOf: f.mediaDir.appendingPathComponent("m-1.jpg"))
        XCTAssertEqual(published, Data("photo".utf8))
    }

    func testRepeatImportIsAdditiveNoOp() throws {
        let f = try fixture(); defer { cleanup(f) }
        let value = try archive(f: f)
        _ = try f.session.importArchive(value, binding: f.binding)
        let again = try f.session.importArchive(value, binding: f.binding)
        XCTAssertEqual(again.journalEntriesAdded, 0)
        XCTAssertEqual(again.journalEntriesSkippedExisting, 1)
        XCTAssertEqual(f.session.lease.generation, 2, "each committed unit advances once")
        let rows = try ModelContext(try XCTUnwrap(f.journalStore.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.count, 1)
    }

    func testV1ArchiveImportsOuterSectionsWithEmptyJournalPlan() throws {
        let f = try fixture(); defer { cleanup(f) }
        let legacy = AteDataArchive(recipes: [card("r-1")], shoppingItems: [],
                                    nutritionDiaryEntries: [diaryEntry()],
                                    nutritionGoals: DailyNutritionGoals(),
                                    appSettings: AppSettings(), timerPreferences: TimerPrefs())
        let decoded = try f.binding.decode(JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.version, 1)
        let result = try f.session.importArchive(decoded, binding: f.binding)
        XCTAssertEqual(result.journalEntriesAdded, 0)
        XCTAssertEqual(try UnifiedArchiveImportBinding.snapshotRecipeShopping(f.container).recipes.map(\.id), ["r-1"])
        XCTAssertEqual(f.session.lease.generation, 1)
    }

    // MARK: - validation

    func testDecodeRejectsTornOrUnsupportedArchives() throws {
        let f = try fixture(); defer { cleanup(f) }
        var torn = try archive(f: f); torn.journal = nil
        XCTAssertThrowsError(try f.binding.decode(JSONEncoder().encode(torn))) { error in
            guard case UnifiedArchiveImportBinding.Failure.journalSectionMissing = error else {
                return XCTFail("expected journalSectionMissing, got \(error)")
            }
        }
        var wrongFormat = try archive(f: f); wrongFormat.format = "other"
        XCTAssertThrowsError(try f.binding.decode(JSONEncoder().encode(wrongFormat)))
        var future = try archive(f: f); future.version = 99
        XCTAssertThrowsError(try f.binding.decode(JSONEncoder().encode(future))) { error in
            guard case UnifiedArchiveImportBinding.Failure.unsupportedVersion(99) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
        }
    }

    func testCorruptLocalDiaryRefusesBeforeAnyRecordOrMutation() throws {
        let f = try fixture(); defer { cleanup(f) }
        let raw = Data("corrupt local diary".utf8)
        f.defaults.set(raw, forKey: NutritionDiaryRepository.storageKey)
        XCTAssertThrowsError(try f.binding.importArchive(archive(f: f)))
        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty,
                      "no recovery record may exist when nothing was attempted")
        XCTAssertEqual(f.defaults.data(forKey: NutritionDiaryRepository.storageKey), raw)
        XCTAssertEqual(f.session.lease.generation, 0)
    }

    func testEmptyOwnerIdentityRefused() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveImportOwner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lease = try POSIXArchiveWriterLease(directory: root); defer { lease.release() }
        let suite = "ArchiveImportOwner-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")))
        XCTAssertThrowsError(try UnifiedArchiveImportBinding(lease: lease,
            recoveryJournal: DiskArchiveRecoveryJournal(lease: lease), ownerIdentity: "",
            journal: JournalStore(inMemory: true),
            recipeContainer: ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)),
            diary: NutritionDiaryRepository(defaults: defaults), goals: goals,
            defaults: defaults, mediaDirectory: root))
    }

    // MARK: - failure + recovery arc

    func testFailedImportLeavesRecoverableTransactionAndStartupRestoresBeforeImages() throws {
        let f = try fixture(); defer { cleanup(f) }
        let originalSettings = try JSONEncoder().encode(AppSettings(units: .metric))
        f.defaults.set(originalSettings, forKey: ArchiveDefaultsParticipant.settingsKey)
        let ctx = ModelContext(f.container); ctx.autosaveEnabled = false
        ctx.insert(RecipeEntity(id: "r-old", createdAt: 111, position: 0, json: try JSONEncoder().encode(card("r-old"))))
        try ctx.save()

        XCTAssertThrowsError(try f.binding.importArchive(archive(f: f), checkpoint: {
            if $0 == .afterOuter { throw Injected.failure } // crash after every store write
        }))
        XCTAssertEqual(f.session.lease.generation, 0, "failed unit commits nothing")
        let pending = try f.session.recoveryJournal.transactions()
        XCTAssertEqual(pending.count, 1, "interrupted transaction retained for startup recovery")

        // The next launch runs startup recovery over the same stores.
        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: f.session.lease,
            journal: f.session.recoveryJournal, ownerIdentity: "fixture-owner",
            defaults: f.defaults, diary: NutritionDiaryRepository(defaults: f.defaults),
            goals: f.binding.goals, recipeContainer: f.container,
            journalContainer: { try XCTUnwrap(f.journalStore.container) }, mediaDirectory: f.mediaDir)

        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty)
        XCTAssertEqual(f.defaults.data(forKey: ArchiveDefaultsParticipant.settingsKey), originalSettings)
        let recipes = try UnifiedArchiveImportBinding.snapshotRecipeShopping(f.container)
        XCTAssertEqual(recipes.recipes.map(\.id), ["r-old"], "imported recipe rolled back")
        let rows = try ModelContext(try XCTUnwrap(f.journalStore.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertTrue(rows.isEmpty, "imported journal entry rolled back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.mediaDir.appendingPathComponent("m-1.jpg").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.mediaDir.path).isEmpty,
                      "staging leftovers cleaned")
    }

    func testPlannedRawImagesAreStableAcrossIndependentEncoders() throws {
        let f = try fixture(); defer { cleanup(f) }
        let value = try archive(f: f)
        let before = try f.binding.readNutritionImage()
        let expected = try UnifiedArchiveImportBinding.plannedNutritionImage(before: before,
            incomingDiary: value.nutritionDiaryEntries, incomingGoals: value.nutritionGoals)
        let defaultsBefore = f.binding.readDefaultsImage()
        let expectedDefaults = try UnifiedArchiveImportBinding.plannedDefaultsImage(before: defaultsBefore,
            settings: value.appSettings, timerPrefs: value.timerPreferences)
        let recipesBefore = try UnifiedArchiveImportBinding.snapshotRecipeShopping(f.container)
        let expectedRecipes = try UnifiedArchiveImportBinding.plannedRecipeShoppingImage(before: recipesBefore,
            incomingRecipes: value.recipes, incomingShopping: value.shoppingItems)
        for _ in 0..<32 {
            XCTAssertEqual(try UnifiedArchiveImportBinding.plannedNutritionImage(before: before,
                incomingDiary: value.nutritionDiaryEntries, incomingGoals: value.nutritionGoals), expected)
            XCTAssertEqual(try UnifiedArchiveImportBinding.plannedDefaultsImage(before: defaultsBefore,
                settings: value.appSettings, timerPrefs: value.timerPreferences), expectedDefaults)
            XCTAssertEqual(try UnifiedArchiveImportBinding.plannedRecipeShoppingImage(before: recipesBefore,
                incomingRecipes: value.recipes, incomingShopping: value.shoppingItems), expectedRecipes)
        }
    }

    func testRecordImagesMatchActualPlannedWrites() throws {
        let f = try fixture(); defer { cleanup(f) }
        let existingDiary = diaryEntry(food: "Inhloko")
        let diary = NutritionDiaryRepository(defaults: f.defaults)
        try diary.savePrepared(diary.prepare([existingDiary]))
        let value = try archive(f: f)
        XCTAssertThrowsError(try f.binding.importArchive(value, checkpoint: {
            if $0 == .beforeStage { throw Injected.failure } // stop before any mutation
        }))
        let id = try XCTUnwrap(f.session.recoveryJournal.transactions().first)
        let record = try f.session.recoveryJournal.read(id)
        XCTAssertEqual(record.ownerIdentity, "fixture-owner")
        XCTAssertEqual(record.storeGeneration, 0)
        XCTAssertEqual(Set(record.images.map(\.component)),
                       Set([ArchiveComponentName.nutrition, ArchiveComponentName.defaults,
                            ArchiveComponentName.recipeShopping]))

        let dec = JSONDecoder()
        let nutritionBefore = try dec.decode(ArchiveNutritionImage.self, from: XCTUnwrap(
            record.images.first { $0.component == ArchiveComponentName.nutrition }?.before))
        XCTAssertEqual(nutritionBefore.diary, diary.defaults.data(forKey: NutritionDiaryRepository.storageKey))
        let nutritionAfter = try dec.decode(ArchiveNutritionImage.self, from: XCTUnwrap(
            record.images.first { $0.component == ArchiveComponentName.nutrition }?.after))
        let expectedAfter = try UnifiedArchiveImportBinding.plannedNutritionImage(before: nutritionBefore,
            incomingDiary: value.nutritionDiaryEntries, incomingGoals: value.nutritionGoals)
        XCTAssertEqual(nutritionAfter, expectedAfter)
        XCTAssertNil(nutritionAfter.legacyGoals)

        let payload = try dec.decode(JournalMediaRecoveryPayload.self, from: record.journalAndMediaRecovery)
        XCTAssertEqual(payload.entries.map(\.id), ["j-new"])
        XCTAssertEqual(payload.media["m-1.jpg"], sha(Data("photo".utf8)))

        // Startup recovery retires the never-applied transaction without changing anything.
        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: f.session.lease,
            journal: f.session.recoveryJournal, ownerIdentity: "fixture-owner",
            defaults: f.defaults, diary: diary, goals: f.binding.goals, recipeContainer: f.container,
            journalContainer: { try XCTUnwrap(f.journalStore.container) }, mediaDirectory: f.mediaDir)
        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty)
        switch diary.loadState() {
        case .loaded(let entries): XCTAssertEqual(entries.map(\.id), [existingDiary.id])
        default: XCTFail("local diary must survive an unapplied import")
        }
    }

    /// Crash window 1: the committed marker is durable but the process died before the
    /// session advanced the generation and retired. The transaction stays unresolved, so
    /// startup recovery verifies the after-images against the actual stores, finishes,
    /// retires, and advances the generation exactly once.
    func testCrashBetweenCommitAndGenerationAdvanceIsCompletedExactlyOnceAtStartup() throws {
        let f = try fixture(); defer { cleanup(f) }
        let value = try archive(f: f)
        let result = try f.binding.importArchive(value) // committed; NO advance, NO retire
        XCTAssertEqual(f.session.lease.generation, 0)
        XCTAssertEqual(try f.session.recoveryJournal.transactions(), [result.committedTransactionID],
                       "committed transaction stays unresolved until the advance is durable")

        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: f.session.lease,
            journal: f.session.recoveryJournal, ownerIdentity: "fixture-owner",
            defaults: f.defaults, diary: NutritionDiaryRepository(defaults: f.defaults),
            goals: f.binding.goals, recipeContainer: f.container,
            journalContainer: { try XCTUnwrap(f.journalStore.container) }, mediaDirectory: f.mediaDir)

        XCTAssertEqual(f.session.lease.generation, 1, "startup completed the advance exactly once")
        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty, "startup retired the transaction")
        let rows = try ModelContext(try XCTUnwrap(f.journalStore.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.map(\.id), ["j-new"], "committed import stays applied")
        XCTAssertEqual(try Data(contentsOf: f.mediaDir.appendingPathComponent("m-1.jpg")), Data("photo".utf8))
    }

    /// Crash window 2: the generation advanced but the process died before the retire.
    /// Startup recovery retires WITHOUT advancing again (authorized-advance path).
    func testCrashBetweenGenerationAdvanceAndRetireNeverAdvancesAgain() throws {
        let f = try fixture(); defer { cleanup(f) }
        let result = try f.binding.importArchive(archive(f: f)) // committed, unresolved
        try f.session.lease.commitGeneration(f.session.lease.generation + 1) // session's advance
        XCTAssertEqual(f.session.lease.generation, 1)
        XCTAssertEqual(try f.session.recoveryJournal.transactions(), [result.committedTransactionID])

        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: f.session.lease,
            journal: f.session.recoveryJournal, ownerIdentity: "fixture-owner",
            defaults: f.defaults, diary: NutritionDiaryRepository(defaults: f.defaults),
            goals: f.binding.goals, recipeContainer: f.container,
            journalContainer: { try XCTUnwrap(f.journalStore.container) }, mediaDirectory: f.mediaDir)

        XCTAssertEqual(f.session.lease.generation, 1, "already-advanced generation is never re-committed")
        XCTAssertTrue(try f.session.recoveryJournal.transactions().isEmpty)
        let rows = try ModelContext(try XCTUnwrap(f.journalStore.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.map(\.id), ["j-new"], "committed import stays applied")
    }

    /// The session owns the full ordering: committed unit, durable advance, then retire.
    func testSessionAdvancesThenRetires() throws {
        let f = try fixture(); defer { cleanup(f) }
        let result = try f.session.importArchive(try archive(f: f), binding: f.binding)
        XCTAssertEqual(f.session.lease.generation, 1)
        XCTAssertFalse(try f.session.recoveryJournal.transactions().contains(result.committedTransactionID))
    }

    // MARK: - lease modes

    /// A reset control record created between the pre-check and the flock must still be
    /// caught under the held lock: the factory releases and refuses, never interleaving
    /// with the reset writer.
    func testStandaloneLeaseRechecksResetPendingUnderHeldLock() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveLeaseRace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var calls = 0
        XCTAssertThrowsError(try ArchiveStandaloneLeaseFactory.lease(controlDirectory: root, resetPending: {
            calls += 1
            return calls > 1 // reset appears between the pre-check and the held-lock recheck
        })) { error in
            guard case ArchiveStandaloneLeaseFailure.resetPending = error else {
                return XCTFail("expected resetPending, got \(error)")
            }
        }
        XCTAssertEqual(calls, 2, "reset state is rechecked under the acquired flock")
        let lease = try ArchiveStandaloneLeaseFactory.lease(controlDirectory: root, resetPending: { false })
        lease.release()
    }

    func testStandaloneLeaseFlocksSharedFileAndRefusesWhileResetPending() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveLease-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try ArchiveStandaloneLeaseFactory.lease(controlDirectory: root, resetPending: { true })) { error in
            guard case ArchiveStandaloneLeaseFailure.resetPending = error else {
                return XCTFail("expected resetPending, got \(error)")
            }
        }
        let lease = try ArchiveStandaloneLeaseFactory.lease(controlDirectory: root, resetPending: { false })
        defer { lease.release() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("writer-gate-v1.lock").path),
                      "retargeted to the ONE shared lock file")
        XCTAssertThrowsError(try ArchiveStandaloneLeaseFactory.lease(controlDirectory: root, resetPending: { false }),
                             "a second holder of the shared file conflicts")
    }

    func testNestedBoundaryAdvancesOncePerSuccessAndNeverOnThrow() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveNested-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let boundary = ArchiveNestedGenerationBoundary(directory: root)
        try boundary.withNestedLease { }
        try boundary.withNestedLease { }
        XCTAssertThrowsError(try boundary.withNestedLease { throw Injected.failure })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("writer-gate-v1.lock").path),
                       "nested mode never opens or flocks a lock file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".ate-writer.lock").path))
        // Two successful effects advanced exactly twice; the throwing effect committed nothing.
        // (This standalone check lease creates .ate-writer.lock, so it comes last.)
        let check = try POSIXArchiveWriterLease(directory: root); defer { check.release() }
        XCTAssertEqual(check.generation, 2)
    }

    /// While any recovery transaction is unresolved, the nested boundary refuses every
    /// covered writer effect - validating the generation alone is not enough: writing over
    /// an open transaction would fork the generation chain.
    func testNestedBoundaryRefusesWhileRecoveryTransactionUnresolved() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveNestedBlocked-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let boundary = ArchiveNestedGenerationBoundary(directory: root)
        let journal = DiskArchiveRecoveryJournal(lease: try POSIXArchiveWriterLease(nestedDirectory: root))
        let record = ArchiveRecoveryRecord(version: 1, transactionID: UUID(), ownerIdentity: "fixture-owner",
            storeGeneration: 0, images: [],
            journalAndMediaRecovery: try JSONEncoder().encode(JournalMediaRecoveryPayload(version: 1, entries: [], media: [:])))
        try journal.prepare(record)

        XCTAssertThrowsError(try boundary.withNestedLease { }) { error in
            guard case ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction = error else {
                return XCTFail("expected unresolvedRecoveryTransaction, got \(error)")
            }
        }
        // The refused effect committed nothing.
        let check = try POSIXArchiveWriterLease(directory: root); defer { check.release() }
        XCTAssertEqual(check.generation, 0)

        // Once recovery resolves the transaction, covered effects run and advance again.
        try journal.transition(record.transactionID, to: .applying)
        try journal.transition(record.transactionID, to: .committed)
        try journal.retire(record.transactionID)
        try boundary.withNestedLease { }
        XCTAssertEqual(check.generation, 1)
    }
}
