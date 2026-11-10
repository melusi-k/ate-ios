import Foundation
import Darwin
import SwiftData

/// Production reset/writer-lifecycle service for the unified Food Journal graph
/// (#245, slice B). One canonical component list shared by the Clear-all coordinator
/// binding and the direct account-action wipes (sign-out-remove, delete-account).
///
/// Erase semantics: every component independently erases and then verifies empty; a
/// nil/unopened container is a FAILURE, never reported empty; there is deliberately no
/// rollback backup of personal bytes. Migration/cleanup lifecycle markers
/// (ate.foodJournal.diaryMigration.v1, ate.journal.imagePromptCleanup.v1) are PRESERVED:
/// they are non-personal control state whose loss could re-trigger legacy import.
/// Sync metadata/tombstones and credentials are NOT on this list (separate ownership).
///
/// Gate discipline: callers run eraseAll inside the composed writer boundary
/// (JournalWriterBoundaryComposition) and pass its re-validation closure as
/// validateWriterGate. Directory removal relies on that cooperative gate, not on
/// hostile same-UID race safety (carried from the K810 source-review limitations).
@MainActor
struct JournalLocalReset {
    /// Journal/diary/cook-scoped defaults keys this service erases. Lifecycle markers,
    /// sync metadata/tombstones and credentials are deliberately absent.
    static let journalDefaultsKeys: Set<String> = [
        "ate.nutritionDiary.v1",
        "ate.nutritionGoals.v1",
        "ate.nutritionRecipeAssociations.v1",
        "ate.cooking.history.v1",
        "ate.cook.reflectionOffer.v1",
        "ate.cook.completionOutbox.v1",
        // Obsolete cooking-candidate key (V6 removed CookSessionToken). Retained only to
        // erase copies an earlier candidate iteration may already have written.
        "ate.cook.sessionToken.v1",
    ]
    static let journalDefaultsPrefixes: [String] = ["ate.cook.completionOutbox.v1.unreadable."]

    let journal: JournalStore
    let defaults: UserDefaults
    let goalsStorage: NutritionGoalsStorage
    let mediaDirectory: URL
    let migrationBackupDirectory: URL
    let repairBackupDirectory: URL
    /// Adoption-preservation copies (JournalInstallReconciliation) are personal data and
    /// join the erase inventory. Nil until central binds the directory at composition.
    let preservationDirectory: URL?
    let storeFileURL: URL

    static var defaultMigrationBackupDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(FoodJournalMigration.legacyBackupDirectoryName, isDirectory: true)
    }
    static var defaultRepairBackupDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(NutritionDiaryRepository.corruptBackupDirectoryName, isDirectory: true)
    }
    /// Matches JournalStore's durable open path ("AteJournal" in the default directory).
    static var defaultStoreFileURL: URL { ModelConfiguration("AteJournal").url }

    init(journal: JournalStore, defaults: UserDefaults, goalsStorage: NutritionGoalsStorage,
         mediaDirectory: URL, migrationBackupDirectory: URL, repairBackupDirectory: URL,
         preservationDirectory: URL?, storeFileURL: URL) {
        self.journal = journal
        self.defaults = defaults
        self.goalsStorage = goalsStorage
        self.mediaDirectory = mediaDirectory
        self.migrationBackupDirectory = migrationBackupDirectory
        self.repairBackupDirectory = repairBackupDirectory
        self.preservationDirectory = preservationDirectory
        self.storeFileURL = storeFileURL
    }

    init(runtime: FoodJournalRuntime, preservationDirectory: URL? = nil) {
        self.init(journal: runtime.journal, defaults: runtime.defaults,
                  goalsStorage: runtime.goalsRepository.storage,
                  mediaDirectory: JournalStore.mediaDir,
                  migrationBackupDirectory: Self.defaultMigrationBackupDirectory,
                  repairBackupDirectory: Self.defaultRepairBackupDirectory,
                  preservationDirectory: preservationDirectory,
                  storeFileURL: Self.defaultStoreFileURL)
    }

    /// The same list feeds ClearAllResetCoordinator's components closure and direct wipes,
    /// so the two paths can never drift apart.
    func components(validateWriterGate: @escaping () throws -> Void) throws -> ([ClearAllLocalData.Component], Set<String>) {
        var list: [ClearAllLocalData.Component] = []
        switch journal.openState {
        case .ok, .recovered:
            // Raw fetches delete corrupt/future rows too; never filtered reads. A nil
            // container here is a contradiction and fails the component, never passes.
            list.append(ClearAllLocalData.journal(container: journal.container,
                                                  validateWriterGate: validateWriterGate))
        case .inMemoryFallback:
            // The live container is in-memory: erase its rows for THIS session AND delete
            // the durable store files - row erasure through an in-memory container proves
            // nothing about the bytes on disk.
            list.append(ClearAllLocalData.journal(container: journal.container,
                                                  validateWriterGate: validateWriterGate))
            list.append(Self.storeFilesComponent(storeFileURL: storeFileURL,
                                                 validateWriterGate: validateWriterGate))
        case .unavailable:
            // No container can erase rows: remove the durable store files directly. Absent
            // files verify empty (absence is the goal); present files are deleted.
            list.append(Self.storeFilesComponent(storeFileURL: storeFileURL,
                                                 validateWriterGate: validateWriterGate))
        }
        list.append(ClearAllLocalData.directory(name: "journal-media", url: mediaDirectory,
                                                validateWriterGate: validateWriterGate))
        list.append(ClearAllLocalData.defaults(name: "journal-diary-cook-defaults", store: defaults,
                                               keys: Self.journalDefaultsKeys,
                                               prefixes: Self.journalDefaultsPrefixes,
                                               validateWriterGate: validateWriterGate))
        list.append(ClearAllLocalData.nutritionGoals(storage: goalsStorage,
                                                     validateWriterGate: validateWriterGate))
        list.append(ClearAllLocalData.directory(name: "nutrition-diary-legacy-backups",
                                                url: migrationBackupDirectory,
                                                validateWriterGate: validateWriterGate))
        list.append(ClearAllLocalData.directory(name: "nutrition-diary-corrupt-backups",
                                                url: repairBackupDirectory,
                                                validateWriterGate: validateWriterGate))
        if let preservationDirectory {
            list.append(ClearAllLocalData.directory(name: "adoption-preservation",
                                                    url: preservationDirectory,
                                                    validateWriterGate: validateWriterGate))
        }
        return (list, Set(list.map(\.name)))
    }

    /// Executes and independently verifies every component. Structural misuse throws;
    /// per-component failures come back in the report, never hidden.
    @discardableResult
    func eraseAll(validateWriterGate: @escaping () throws -> Void) throws -> ClearAllLocalData.Report {
        let (components, required) = try components(validateWriterGate: validateWriterGate)
        return try ClearAllLocalData.execute(components, requiredNames: required,
                                             validateWriterGate: validateWriterGate)
    }

    /// Deletes exactly the app-owned AteJournal store files (x.store, x.store-wal,
    /// x.store-shm) for states where no container can erase rows. Only regular files at
    /// the expected paths are touched; a symlink or non-regular entry refuses.
    static func storeFilesComponent(storeFileURL: URL,
                                    validateWriterGate: @escaping () throws -> Void,
                                    fileManager fm: FileManager = .default) -> ClearAllLocalData.Component {
        func paths() throws -> [String] {
            guard storeFileURL.isFileURL, storeFileURL.path.hasPrefix("/"),
                  storeFileURL.lastPathComponent.hasSuffix(".store") else {
                throw ClearAllLocalData.Error.unsafeDirectory
            }
            return ["", "-wal", "-shm"].map { storeFileURL.path + $0 }
        }
        return ClearAllLocalData.Component(name: "journal-store-files", erase: {
            for path in try paths() {
                try validateWriterGate()
                var metadata = stat()
                guard lstat(path, &metadata) == 0 else { continue }   // absent is the goal
                guard (metadata.st_mode & S_IFMT) == S_IFREG else {
                    throw ClearAllLocalData.Error.unsafeDirectory
                }
                try fm.removeItem(atPath: path)
            }
        }, verifyEmpty: {
            for path in try paths() {
                guard !fm.fileExists(atPath: path) else { throw ClearAllLocalData.Error.notEmpty }
            }
        })
    }
}
