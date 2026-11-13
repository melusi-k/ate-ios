import Foundation
import SwiftData

/// Strict retained disk participants for production admission and archive recovery.
/// Never use StoreRecovery's move-aside/empty fallback while recovery evidence exists.
/// The existing store paths stay unchanged; resolving the app-group control path is
/// a separate required production dependency, never inferred from these store paths.
@MainActor
final class FoodJournalDiskResources {
    enum Failure: Error { case recoveryNotCompleted, ownerChanged }

    let controlDirectory: URL
    let defaults: UserDefaults
    let goals: NutritionGoalsRepository
    let mediaDirectory: URL
    let migrationBackupDirectory: URL
    let repairBackupDirectory: URL
    private let recipeConfiguration: ModelConfiguration
    private let journalConfiguration: ModelConfiguration
    private var recoveredGate: AccountWriterGate?
    private var recoveredLease: UUID?
    private var recoveredOwner: String?
    private var recipes: ModelContainer?
    private var journal: ModelContainer?

    init(controlDirectory: URL, defaults: UserDefaults, goals: NutritionGoalsRepository,
         mediaDirectory: URL, migrationBackupDirectory: URL, repairBackupDirectory: URL,
         recipeConfiguration: ModelConfiguration = ModelConfiguration(),
         journalConfiguration: ModelConfiguration = ModelConfiguration("AteJournal")) {
        self.controlDirectory = controlDirectory
        self.defaults = defaults
        self.goals = goals
        self.mediaDirectory = mediaDirectory
        self.migrationBackupDirectory = migrationBackupDirectory
        self.repairBackupDirectory = repairBackupDirectory
        self.recipeConfiguration = recipeConfiguration
        self.journalConfiguration = journalConfiguration
    }

    /// Called by ProductionAdmission's raw recovery closure AFTER identity/generation
    /// preflight. Reuses the original account lease, with no flock across an await.
    func recover(gate: AccountWriterGate, lease: UUID, ownerIdentity: String) throws {
        try gate.withWriterEffect(lease) {
            guard !ownerIdentity.isEmpty else { throw Failure.ownerChanged }
            if let recoveredOwner {
                guard recoveredOwner == ownerIdentity, recoveredGate === gate, recoveredLease == lease else { throw Failure.ownerChanged }
                return
            }
            let recipes = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                configurations: recipeConfiguration)
            let journal = try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                configurations: journalConfiguration)
            // Explicit-save transaction policy: no framework autosave may bypass
            // the admitted account/archive boundary. This is not a #518 crash claim.
            recipes.mainContext.autosaveEnabled = false
            journal.mainContext.autosaveEnabled = false
            try FoodJournalStartupRecovery.recover(controlDirectory: controlDirectory,
                ownerIdentity: ownerIdentity, defaults: defaults,
                diary: NutritionDiaryRepository(defaults: defaults, backupDirectory: repairBackupDirectory),
                goals: goals, recipeContainer: recipes, journalContainer: { journal },
                mediaDirectory: mediaDirectory)
            self.recipes = recipes
            self.journal = journal
            recoveredGate = gate
            recoveredLease = lease
            recoveredOwner = ownerIdentity
        }
    }

    func recipeContainer() throws -> ModelContainer {
        guard recoveredOwner != nil, let gate = recoveredGate, let lease = recoveredLease,
              let recipes else { throw Failure.recoveryNotCompleted }
        return try gate.withWriterEffect(lease) { recipes }
    }

    /// Must run in FoodJournalAppGraph's covered construction unit, after recovery.
    /// The injected JournalStore has no second disk open, seeding or recovery fallback.
    func makeResources(boundary: FoodJournalWriterBoundary,
                       afterRestoreCommit: @escaping () throws -> Void) throws -> FoodJournalAppGraph.Resources {
        guard recoveredOwner != nil, let gate = recoveredGate, let lease = recoveredLease,
              let recipes, let journal else { throw Failure.recoveryNotCompleted }
        return try gate.withWriterEffect(lease) {
            .init(recipeContext: recipes.mainContext,
            journal: JournalStore(container: journal, openState: .ok, writerBoundary: boundary),
            defaults: defaults, goals: goals,
            migrationBackupDirectory: migrationBackupDirectory,
            repairBackupDirectory: repairBackupDirectory,
            afterRestoreCommit: afterRestoreCommit)
        }
    }
}
