import Foundation
import SwiftData
import CryptoKit

/// Production startup-recovery binding for the unified Journal archive (#245 slice A).
/// Central calls recoverAtStartup inside the composed writer boundary, under the held
/// standalone lease, BEFORE any ordinary store constructor. Any unresolved, torn or
/// foreign transaction throws: admission stays blocked and all evidence is preserved.
/// Only exact before-image restoration (uncommitted) or committed-state verification
/// lets startup continue. Retired .resolved-* records are evidence, never a blocker.
@MainActor
enum UnifiedArchiveStartupRecovery {

    enum Failure: Error {
        /// A recorded image is absent or undecodable; never guess from a partial record.
        case invalidRecoveryImage
    }

    /// The one admission-blocking entry point. Also owns the generation-completion rule:
    /// a historically committed transaction whose durable generation advance never landed
    /// (process death between the committed marker and commitGeneration) is advanced exactly
    /// once, INSIDE run's beforeRetire, so the commit lands before the retire and a crash
    /// anywhere in that window is completed exactly once by a later startup; an
    /// already-advanced generation is never re-committed.
    static func recoverAtStartup(
        lease: POSIXArchiveWriterLease,
        journal: DiskArchiveRecoveryJournal,
        ownerIdentity: String,
        defaults: UserDefaults,
        diary: NutritionDiaryRepository,
        goals: NutritionGoalsRepository,
        recipeContainer: ModelContainer,
        journalContainer: @escaping () throws -> ModelContainer = { try openJournalContainer() },
        mediaDirectory: URL
    ) throws {
        var pendingAdvance = false
        let ids = try journal.transactions()
        if ids.count == 1, let id = ids.first {
            let record = try journal.read(id)
            let history = try journal.history(id)
            pendingAdvance = history.hasCommittedMarker && record.storeGeneration == lease.generation
        }
        let recovery = makeRecovery(journal: journal, defaults: defaults, diary: diary, goals: goals,
                                    recipeContainer: recipeContainer, journalContainer: journalContainer,
                                    mediaDirectory: mediaDirectory)
        try recovery.run(ownerIdentity: ownerIdentity, beforeRetire: { _ in
            // Commit the pending generation BEFORE the transaction retires: a crash after
            // this commit leaves an unresolved committed record one generation behind,
            // which the next startup retires via the authorized-advance path without
            // advancing again. A crash before it leaves pendingAdvance true again.
            if pendingAdvance { try lease.commitGeneration(lease.generation + 1) }
        })
    }

    /// Assembles ArchiveStartupRecovery with handlers bound to the real stores. The handler
    /// component set is exactly the component set UnifiedArchiveImportBinding records;
    /// ArchiveStartupRecovery.run refuses any mismatch.
    static func makeRecovery(journal: DiskArchiveRecoveryJournal, defaults: UserDefaults,
                             diary: NutritionDiaryRepository, goals: NutritionGoalsRepository,
                             recipeContainer: ModelContainer,
                             journalContainer: @escaping () throws -> ModelContainer = { try openJournalContainer() },
                             mediaDirectory: URL) -> ArchiveStartupRecovery {
        // Open the journal store at most once per recovery run; every handler shares it.
        var cachedContainer: ModelContainer?
        let sharedJournalContainer: () throws -> ModelContainer = {
            if let cachedContainer { return cachedContainer }
            let opened = try journalContainer()
            cachedContainer = opened
            return opened
        }
        return ArchiveStartupRecovery(journal: journal, handlers: [
            ArchiveStartupRecovery.Handler(
                component: ArchiveComponentName.nutrition,
                restoreBefore: { try restoreNutrition(decodeRequired(ArchiveNutritionImage.self, $0), diary: diary, goals: goals) },
                verifyBefore: { guard try readNutritionImage(diary: diary, goals: goals) == decodeRequired(ArchiveNutritionImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } },
                verifyAfter: { guard try readNutritionImage(diary: diary, goals: goals) == decodeRequired(ArchiveNutritionImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } }),
            ArchiveStartupRecovery.Handler(
                component: ArchiveComponentName.defaults,
                restoreBefore: { try restoreDefaults(decodeRequired(ArchiveDefaultsImage.self, $0), defaults: defaults) },
                verifyBefore: { guard readDefaultsImage(defaults: defaults) == decodeRequired(ArchiveDefaultsImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } },
                verifyAfter: { guard readDefaultsImage(defaults: defaults) == decodeRequired(ArchiveDefaultsImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } }),
            ArchiveStartupRecovery.Handler(
                component: ArchiveComponentName.recipeShopping,
                restoreBefore: { try restoreRecipeShopping(decodeRequired(ArchiveRecipeShoppingImage.self, $0), container: recipeContainer) },
                verifyBefore: { guard try UnifiedArchiveImportBinding.snapshotRecipeShopping(recipeContainer) == decodeRequired(ArchiveRecipeShoppingImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } },
                verifyAfter: { guard try UnifiedArchiveImportBinding.snapshotRecipeShopping(recipeContainer) == decodeRequired(ArchiveRecipeShoppingImage.self, $0) else { throw ArchiveRestoreFailure.verificationFailed } }),
        ], journalMedia: ArchiveStartupRecovery.JournalMediaHandler(
            compensate: { try compensateJournalAndMedia($0, journalContainer: sharedJournalContainer, mediaDirectory: mediaDirectory) },
            verifyBefore: { try verifyJournalBefore($0, journalContainer: sharedJournalContainer, mediaDirectory: mediaDirectory) },
            verifyAfter: { try verifyJournalAfter($0, journalContainer: sharedJournalContainer, mediaDirectory: mediaDirectory) },
            finishCommitted: { _ in try removeStagingDirectories(in: mediaDirectory) }))
    }

    /// Opens the Journal store directly, WITHOUT StoreRecovery's move-aside path: archive
    /// startup recovery must never relocate store files while restoring exact before-images.
    /// A damaged store throws here and blocks admission visibly instead.
    /// nonisolated: it touches no actor state (a plain ModelContainer init), and the
    /// journalContainer default-argument closures are evaluated in a nonisolated context.
    nonisolated static func openJournalContainer() throws -> ModelContainer {
        try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                           configurations: ModelConfiguration("AteJournal"))
    }

    // MARK: - image decoding

    private static func decodeRequired<T: Decodable>(_ type: T.Type, _ data: Data?) throws -> T {
        guard let data else { throw Failure.invalidRecoveryImage }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - nutrition component

    static func readNutritionImage(diary: NutritionDiaryRepository,
                                   goals: NutritionGoalsRepository) throws -> ArchiveNutritionImage {
        ArchiveNutritionImage(diary: diary.defaults.data(forKey: NutritionDiaryRepository.storageKey),
                              goalFile: try goals.storage.read(),
                              legacyGoals: goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey))
    }

    /// Byte-exact restoration of the before-image. Runs under the held lease before ordinary
    /// writers exist, so direct byte writes are the correct primitive here.
    static func restoreNutrition(_ image: ArchiveNutritionImage, diary: NutritionDiaryRepository,
                                 goals: NutritionGoalsRepository) throws {
        if let diaryBytes = image.diary {
            diary.defaults.set(diaryBytes, forKey: NutritionDiaryRepository.storageKey)
        } else {
            diary.defaults.removeObject(forKey: NutritionDiaryRepository.storageKey)
        }
        if let goalFile = image.goalFile { try goals.storage.write(goalFile) } else { try goals.storage.remove() }
        if let legacyGoals = image.legacyGoals {
            goals.defaults.set(legacyGoals, forKey: DailyNutritionGoals.defaultsKey)
        } else {
            goals.defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
        }
    }

    // MARK: - defaults component

    static func readDefaultsImage(defaults: UserDefaults) -> ArchiveDefaultsImage {
        ArchiveDefaultsImage(settings: defaults.data(forKey: ArchiveDefaultsParticipant.settingsKey),
                             timer: defaults.data(forKey: ArchiveDefaultsParticipant.timerKey),
                             syncMeta: defaults.data(forKey: ArchiveDefaultsParticipant.syncMetaKey))
    }

    /// Restores settings and timer bytes. syncMeta is never written: it is snapshot-guarded
    /// only, and verify compares it against the recorded image.
    static func restoreDefaults(_ image: ArchiveDefaultsImage, defaults: UserDefaults) throws {
        if let settings = image.settings {
            defaults.set(settings, forKey: ArchiveDefaultsParticipant.settingsKey)
        } else {
            defaults.removeObject(forKey: ArchiveDefaultsParticipant.settingsKey)
        }
        if let timer = image.timer {
            defaults.set(timer, forKey: ArchiveDefaultsParticipant.timerKey)
        } else {
            defaults.removeObject(forKey: ArchiveDefaultsParticipant.timerKey)
        }
    }

    // MARK: - recipes/shopping component

    /// Reconciles the store to the recorded image: existing rows update in place under the
    /// same unique identity, only missing identities insert, only extra identities delete,
    /// one throwing save. json bytes are restored verbatim.
    static func restoreRecipeShopping(_ image: ArchiveRecipeShoppingImage, container: ModelContainer) throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let recipeRows = try ctx.fetch(FetchDescriptor<RecipeEntity>())
        let recipeByID = Dictionary(uniqueKeysWithValues: recipeRows.map { ($0.id, $0) })
        let keepRecipes = Set(image.recipes.map(\.id))
        for r in image.recipes {
            if let row = recipeByID[r.id] {
                row.createdAt = r.createdAt; row.position = r.position; row.json = r.json
            } else {
                ctx.insert(RecipeEntity(id: r.id, createdAt: r.createdAt, position: r.position, json: r.json))
            }
        }
        for row in recipeRows where !keepRecipes.contains(row.id) { ctx.delete(row) }
        let shoppingRows = try ctx.fetch(FetchDescriptor<ShoppingEntity>())
        let shoppingByID = Dictionary(uniqueKeysWithValues: shoppingRows.map { ($0.id, $0) })
        let keepShopping = Set(image.shopping.map(\.id))
        for s in image.shopping {
            if let row = shoppingByID[s.id] {
                row.position = s.position; row.json = s.json
            } else {
                ctx.insert(ShoppingEntity(id: s.id, position: s.position, json: s.json))
            }
        }
        for row in shoppingRows where !keepShopping.contains(row.id) { ctx.delete(row) }
        try ctx.save()
    }

    // MARK: - journal + media

    /// Row-to-value mapping lives in ArchiveJournalRowMapping (ArchiveComponentImage.swift),
    /// identical to JournalArchiveCapture/JournalArchiveRestore: every raw field is copied
    /// verbatim, never normalized.
    static func journalValue(_ row: JournalEntry, meal: NutritionDiaryEntry?) -> JournalArchiveEntry {
        ArchiveJournalRowMapping.value(row, meal: meal)
    }

    /// Uncommitted transaction: remove exactly what the transaction inserted, and only while
    /// it still matches the recorded insertion verbatim. A foreign edit is preserved and
    /// surfaced, never overwritten. Media destinations are removed only when their bytes
    /// hash to the recorded digest (exclusive-create publish proves ownership).
    static func compensateJournalAndMedia(_ data: Data, journalContainer: () throws -> ModelContainer,
                                          mediaDirectory: URL) throws {
        let payload = try JSONDecoder().decode(JournalMediaRecoveryPayload.self, from: data)
        var failures: [String] = []
        do { try compensateJournalEntries(payload.entries, container: journalContainer()) }
        catch { failures.append("journal entries: \(error)") }
        do { try compensateMedia(payload.media, directory: mediaDirectory) }
        catch { failures.append("media: \(error)") }
        // Staging holds recovery receipts; only clean it when ownership is fully resolved.
        if failures.isEmpty {
            do { try removeStagingDirectories(in: mediaDirectory) }
            catch { failures.append("staging: \(error)") }
        }
        if !failures.isEmpty {
            throw ArchiveRestoreFailure.recoveryRequired(original: "journal/media startup compensation",
                                                         compensationFailures: failures)
        }
    }

    static func compensateJournalEntries(_ entries: [JournalArchiveEntry], container: ModelContainer) throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        // A tampered record must fail visibly, never trap on duplicate identities.
        guard Set(entries.map(\.id)).count == entries.count else { throw ArchiveRestoreFailure.verificationFailed }
        let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>()).filter { expected[$0.id] != nil }
        let payloads = try ctx.fetch(FetchDescriptor<JournalMealPayload>()).filter { expected[$0.entryID] != nil }
        let meals = Dictionary(uniqueKeysWithValues: try FoodJournalStore(container: container).readMeals()
            .map { ($0.id.uuidString, $0) })
        // Refuse to erase another writer's edits, even while compensating.
        guard rows.allSatisfy({ journalValue($0, meal: meals[$0.id]) == expected[$0.id] }) else {
            throw ArchiveRestoreFailure.changedDuringRestore
        }
        for row in rows { ctx.delete(row) }
        for payload in payloads { ctx.delete(payload) }
        try ctx.save()
        let check = ModelContext(container)
        guard try check.fetch(FetchDescriptor<JournalEntry>()).allSatisfy({ expected[$0.id] == nil }),
              try check.fetch(FetchDescriptor<JournalMealPayload>()).allSatisfy({ expected[$0.entryID] == nil }) else {
            throw ArchiveRestoreFailure.verificationFailed
        }
    }

    static func compensateMedia(_ media: [String: String], directory: URL) throws {
        var failures: [String] = []
        for name in media.keys.sorted() {
            guard JournalArchiveValidation.safeMediaName(name) else {
                failures.append("\(name): unsafe recorded name")
                continue
            }
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else {
                continue // never published or already gone: both are the intended before-state.
            }
            guard values.isSymbolicLink == false, values.isRegularFile == true else {
                failures.append("\(name): unexpected file type, preserved")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                guard sha256Hex(data) == media[name] else {
                    // Content this transaction did not write: preserve it, surface it.
                    throw ArchiveRestoreFailure.changedDuringRestore
                }
                try FileManager.default.removeItem(at: url)
            } catch { failures.append("\(name): \(error)") }
        }
        if !failures.isEmpty {
            throw ArchiveRestoreFailure.recoveryRequired(original: "media startup compensation",
                                                         compensationFailures: failures)
        }
    }

    /// Before-state: none of the recorded entries or media names exist.
    static func verifyJournalBefore(_ data: Data, journalContainer: () throws -> ModelContainer,
                                    mediaDirectory: URL) throws {
        let payload = try JSONDecoder().decode(JournalMediaRecoveryPayload.self, from: data)
        let container = try journalContainer()
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let expected = Set(payload.entries.map(\.id))
        guard try ctx.fetch(FetchDescriptor<JournalEntry>()).allSatisfy({ !expected.contains($0.id) }),
              try ctx.fetch(FetchDescriptor<JournalMealPayload>()).allSatisfy({ !expected.contains($0.entryID) }) else {
            throw ArchiveRestoreFailure.verificationFailed
        }
        for name in payload.media.keys
        where FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent(name).path) {
            throw ArchiveRestoreFailure.verificationFailed
        }
    }

    /// After-state: every recorded entry is present verbatim and every media file exists
    /// with its recorded digest.
    static func verifyJournalAfter(_ data: Data, journalContainer: () throws -> ModelContainer,
                                   mediaDirectory: URL) throws {
        let payload = try JSONDecoder().decode(JournalMediaRecoveryPayload.self, from: data)
        let container = try journalContainer()
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let rows = Dictionary(uniqueKeysWithValues: try ctx.fetch(FetchDescriptor<JournalEntry>()).map { ($0.id, $0) })
        let meals = Dictionary(uniqueKeysWithValues: try FoodJournalStore(container: container).readMeals()
            .map { ($0.id.uuidString, $0) })
        for entry in payload.entries {
            guard let row = rows[entry.id], journalValue(row, meal: meals[entry.id]) == entry else {
                throw ArchiveRestoreFailure.verificationFailed
            }
        }
        for (name, digest) in payload.media {
            let url = mediaDirectory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
                  values.isSymbolicLink == false, values.isRegularFile == true,
                  let data = try? Data(contentsOf: url), sha256Hex(data) == digest else {
                throw ArchiveRestoreFailure.verificationFailed
            }
        }
    }

    /// Removes leftover restore staging directories. Sound because DiskArchiveRecoveryJournal
    /// admits at most one unresolved transaction and this prefix is created only by the
    /// restore path: when startup recovery runs, any `.ate-restore-*` directory belongs to
    /// the transaction being recovered.
    static func removeStagingDirectories(in directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where name.hasPrefix(".ate-restore-") {
            var isDirectory: ObjCBool = false
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
