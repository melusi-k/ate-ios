import Foundation
import SwiftData

/// Dormant whole-file import consumer for one retained owner. The host must close
/// visible editors and register/drain every async consumer through this lifecycle.
/// No replacement graph is published here, even after a committed import.
@MainActor
final class FoodJournalArchiveImport {
    enum Failure: Error { case recipeLinksNotArchived }
    private let owner: FoodJournalLocalOwner
    private let recipes: ModelContainer
    private let lifecycle: FoodJournalConsumerLifecycle
    private let ownerIdentity: String
    private let authorizeOperation: () throws -> Void

    init(owner: FoodJournalLocalOwner, recipes: ModelContainer,
         lifecycle: FoodJournalConsumerLifecycle, ownerIdentity: String,
         authorizeOperation: @escaping () throws -> Void) throws {
        try owner.requireLifecycle(lifecycle)
        guard !ownerIdentity.isEmpty else { throw UnifiedArchiveImportBinding.Failure.emptyOwnerIdentity }
        self.owner = owner; self.recipes = recipes; self.lifecycle = lifecycle
        self.ownerIdentity = ownerIdentity; self.authorizeOperation = authorizeOperation
    }
    private func refuseUnarchivedRecipeLinks() throws {
        switch NutritionRecipeAssociationStore(defaults: owner.runtime.defaults).loadState() {
        case .absent: break
        case .loaded(let links) where links.isEmpty: break
        case .loaded, .corrupt: throw Failure.recipeLinksNotArchived
        }
    }
    /// The returned result is not permission to reactivate the old graph. Caller
    /// must rebuild and re-admit the complete graph before presenting normal UI.
    func importData(_ data: Data,
                    checkpoint: (ArchiveRestoreBoundary) throws -> Void = { _ in }) async throws -> UnifiedArchiveImportBinding.Result {
        // Reject a malformed/incomplete file BEFORE migrations or quiescence.
        let archive = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
        try UnifiedArchiveImportBinding.validate(archive)
        try owner.validate()
        try lifecycle.validate()
        try refuseUnarchivedRecipeLinks()
        // Canonical migration barriers run under the original live writer boundary.
        _ = try owner.runtime.readMeals()
        _ = try owner.runtime.goalsRepository.load()
        try await lifecycle.quiesce()
        return try lifecycle.withQuiescedArchiveOperation(authorize: authorizeOperation) { lease in
            guard try !DiskArchiveRecoveryJournal(lease: lease).hasUnresolvedTransactions() else {
                throw ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction
            }
            try refuseUnarchivedRecipeLinks()
            let recovery = DiskArchiveRecoveryJournal(lease: lease)
            let binding = try UnifiedArchiveImportBinding(lease: lease, recoveryJournal: recovery,
                ownerIdentity: ownerIdentity, journal: owner.runtime.journal, recipeContainer: recipes,
                diary: NutritionDiaryRepository(defaults: owner.runtime.defaults,
                    backupDirectory: owner.locations.repairBackupDirectory),
                goals: owner.runtime.goalsRepository, defaults: owner.runtime.defaults,
                mediaDirectory: owner.locations.mediaDirectory)
            // Raw archive participants own this transaction. Do not enter an ordinary
            // runtime boundary with its now-revoked lease or take another flock.
            let result = try binding.importArchive(archive, checkpoint: checkpoint)
            try lease.commitGeneration(lease.generation + 1)
            try recovery.retire(result.committedTransactionID)
            return result
        }
    }
}
