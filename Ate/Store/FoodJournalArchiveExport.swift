import Foundation
import SwiftData

/// Dormant export capability using one admitted owner and the account gate's own
/// archive root. No lock survives media loading; no partial archive escapes.
@MainActor
final class FoodJournalArchiveExport {
    enum Failure: Error, Equatable { case ownerChanged, generationChanged, recipeLinksNotArchived }
    private let owner: FoodJournalLocalOwner
    private let recipes: ModelContainer
    private let gate: AccountWriterGate
    private let admittedLease: UUID
    private let validateOwner: () throws -> Void

    init(owner: FoodJournalLocalOwner, recipes: ModelContainer, gate: AccountWriterGate,
         admittedLease: UUID, validateOwner: @escaping () throws -> Void) {
        self.owner = owner; self.recipes = recipes; self.gate = gate
        self.admittedLease = admittedLease; self.validateOwner = validateOwner
    }
    private var capture: UnifiedArchiveCapture {
        UnifiedArchiveCapture(journal: owner.runtime.journal, recipeContainer: recipes,
            diary: NutritionDiaryRepository(defaults: owner.runtime.defaults,
                backupDirectory: owner.locations.repairBackupDirectory),
            goals: owner.runtime.goalsRepository, defaults: owner.runtime.defaults,
            mediaDirectory: owner.locations.mediaDirectory)
    }
    private func validate() throws {
        try owner.validate()
        try validateOwner()
        // Recipe-link sidecars have no lossless archive contract on main. Refuse
        // rather than offer a falsely complete backup while those personal bytes exist.
        switch NutritionRecipeAssociationStore(defaults: owner.runtime.defaults).loadState() {
        case .absent: break
        case .loaded(let links) where links.isEmpty: break
        case .loaded, .corrupt: throw Failure.recipeLinksNotArchived
        }
    }
    func export(afterSnapshot: () async throws -> Void = {}) async throws -> Data {
        try gate.withWriterEffect(admittedLease) { try validate() }
        // Actual migrating loads run through the retained ordinary writer boundary,
        // BEFORE strictly no-write capture. Corrupt data remains a visible failure.
        _ = try owner.runtime.readMeals()
        _ = try owner.runtime.goalsRepository.load()
        let (snapshot, generation) = try gate.withArchiveRecoveryLease(admittedLease) { archive in
            try validate()
            guard try !DiskArchiveRecoveryJournal(lease: archive).hasUnresolvedTransactions() else {
                throw ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction
            }
            return (try capture.snapshot(), archive.generation)
        }
        // Test seam models a real concurrent event during the unlocked async phase.
        try await afterSnapshot()
        let result = try await capture.finish(snapshot) {
            try gate.withArchiveRecoveryLease(admittedLease) { archive in
                try validate()
                guard archive.generation == generation,
                      try !DiskArchiveRecoveryJournal(lease: archive).hasUnresolvedTransactions() else {
                    throw Failure.generationChanged
                }
            }
        }
        return try JSONEncoder().encode(result)
    }
}
