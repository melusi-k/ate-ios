import Foundation
import SwiftData

/// Dormant raw disk opening/recovery, before ordinary constructors. No recovery
/// move-aside, empty fallback, maintenance or implicit identity authorization.
@MainActor
final class FoodJournalDiskResources {
    enum Failure: Error { case invalidConfiguration, admissionRequired, ownerChanged }
    let defaults: UserDefaults
    let goalsStorage: NutritionGoalsStorage
    let locations: FoodJournalLocalOwner.Locations
    private let recipeConfiguration: ModelConfiguration
    private let journalConfiguration: ModelConfiguration
    private var recoveredOwner: String?
    private var recoveredGate: AccountWriterGate?
    private var recoveredLease: UUID?
    private var recipes: ModelContainer?
    private var journal: ModelContainer?

    init(defaults: UserDefaults, goalsStorage: NutritionGoalsStorage,
         locations: FoodJournalLocalOwner.Locations,
         recipeConfiguration: ModelConfiguration, journalConfiguration: ModelConfiguration) throws {
        let directories = [locations.mediaDirectory, locations.migrationBackupDirectory,
                           locations.repairBackupDirectory, locations.preservationDirectory]
        let paths = directories + [locations.storeFileURL, recipeConfiguration.url]
        guard paths.allSatisfy({ $0.isFileURL && $0.path != "/" && $0 == $0.standardizedFileURL }),
              Set(paths).count == paths.count,
              !directories.contains(where: { parent in
                  paths.contains { child in parent != child && child.path.hasPrefix(parent.path + "/") }
              }) else { throw Failure.invalidConfiguration }
        guard !recipeConfiguration.isStoredInMemoryOnly, recipeConfiguration.allowsSave,
              !journalConfiguration.isStoredInMemoryOnly, journalConfiguration.allowsSave,
              journalConfiguration.url.standardizedFileURL == locations.storeFileURL,
              recipeConfiguration.url.standardizedFileURL != journalConfiguration.url.standardizedFileURL else {
            throw Failure.invalidConfiguration
        }
        self.defaults = defaults
        self.goalsStorage = goalsStorage
        self.locations = locations
        self.recipeConfiguration = recipeConfiguration
        self.journalConfiguration = journalConfiguration
    }

    /// Mandatory preflight re-proves identity/generation BEFORE raw opens/recovery.
    /// It runs under the original account lease, must not await or stamp adoption.
    /// No resources escape until archive evidence has been recovered successfully.
    func recover(gate: AccountWriterGate, admittedLease: UUID, ownerIdentity: String,
                 authorizeRecovery: () throws -> Void) throws {
        try gate.withArchiveRecoveryLease(admittedLease) { archive in
            try authorizeRecovery()
            guard !ownerIdentity.isEmpty else { throw Failure.admissionRequired }
            if let recoveredOwner {
                guard recoveredOwner == ownerIdentity, recoveredGate === gate,
                      recoveredLease == admittedLease else { throw Failure.ownerChanged }
                return
            }
            let recipes = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                configurations: recipeConfiguration)
            let journal = try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                configurations: journalConfiguration)
            recipes.mainContext.autosaveEnabled = false
            journal.mainContext.autosaveEnabled = false
            let goals = NutritionGoalsRepository(defaults: defaults, storage: goalsStorage)
            try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: archive,
                journal: DiskArchiveRecoveryJournal(lease: archive), ownerIdentity: ownerIdentity,
                defaults: defaults, diary: NutritionDiaryRepository(defaults: defaults,
                    backupDirectory: locations.repairBackupDirectory), goals: goals,
                recipeContainer: recipes, journalContainer: { journal }, mediaDirectory: locations.mediaDirectory)
            self.recipes = recipes
            self.journal = journal
            recoveredOwner = ownerIdentity
            recoveredGate = gate
            recoveredLease = admittedLease
        }
    }

    /// No fresh open or lease capture. Admission must have finished reconciliation;
    /// the returned owner retains exactly the recovered container and original lease.
    func bindOwner(gate: AccountWriterGate, admittedLease: UUID, ownerIdentity: String,
                   archive: ArchiveNestedLeaseBoundary, authorizeBinding: () throws -> Void,
                   afterRestoreCommit: @escaping () throws -> Void,
                   validateConsumers: @escaping () throws -> Void = {}) throws -> FoodJournalLocalOwner {
        try gate.withWriterEffect(admittedLease) {
            try authorizeBinding()
            guard recoveredOwner == ownerIdentity, recoveredGate === gate,
                  recoveredLease == admittedLease, let journal else { throw Failure.admissionRequired }
            return try FoodJournalLocalOwner.bind(container: journal, openState: .ok, defaults: defaults,
                goalsStorage: goalsStorage, locations: locations, gate: gate, admittedLease: admittedLease,
                archive: archive, afterRestoreCommit: afterRestoreCommit, validateConsumers: validateConsumers)
        }
    }
    func recipeContainer(gate: AccountWriterGate, admittedLease: UUID) throws -> ModelContainer {
        try gate.withWriterEffect(admittedLease) {
            guard recoveredGate === gate, recoveredLease == admittedLease,
                  recoveredOwner != nil, let recipes else { throw Failure.admissionRequired }
            return recipes
        }
    }
}
