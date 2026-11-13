import Foundation
import SwiftData

/// Concrete archive capabilities for an admitted canonical graph. The account gate
/// holds the ONE flock; archive work uses no-flock nested leases inside that gate.
/// No lifetime lock survives an await, and no ordinary boundary stamps an import's
/// generation in addition to the import transaction's own completion.
@MainActor
final class FoodJournalArchiveConsumers {
    enum Failure: Error { case ownerMissing, changedDuringExport }
    let gate: AccountWriterGate
    let writerLease: UUID
    let controlDirectory: URL
    let runtime: FoodJournalRuntime
    let recipeContainer: ModelContainer
    let mediaDirectory: URL
    let preservationDirectory: URL
    private let ownerIdentity: () throws -> String
    private let validateOwner: () throws -> Void

    init(gate: AccountWriterGate, writerLease: UUID, controlDirectory: URL,
         runtime: FoodJournalRuntime, recipeContainer: ModelContainer,
         mediaDirectory: URL, preservationDirectory: URL,
         ownerIdentity: @escaping () throws -> String,
         validateOwner: @escaping () throws -> Void) {
        self.gate = gate
        self.writerLease = writerLease
        self.controlDirectory = controlDirectory
        self.runtime = runtime
        self.recipeContainer = recipeContainer
        self.mediaDirectory = mediaDirectory
        self.preservationDirectory = preservationDirectory
        self.ownerIdentity = ownerIdentity
        self.validateOwner = validateOwner
    }

    private var diary: NutritionDiaryRepository {
        NutritionDiaryRepository(defaults: runtime.defaults)
    }
    private var capture: UnifiedArchiveCapture {
        UnifiedArchiveCapture(journal: runtime.journal, recipeContainer: recipeContainer,
            diary: diary, goals: runtime.goalsRepository, defaults: runtime.defaults,
            mediaDirectory: mediaDirectory)
    }

    func bindings() -> FoodJournalConsumerBindings {
        .init(exportArchive: { [self] in try await exportArchive() },
            importArchive: { [self] in try importArchive($0) },
            preservationDirectory: preservationDirectory)
    }

    func exportArchive() async throws -> Data {
        // Migration is an actual covered write and must finish BEFORE no-write capture.
        _ = try runtime.readMeals()
        _ = try runtime.writerBoundary.withEffect { try runtime.goalsRepository.load() }
        let (snapshot, generation) = try gate.withWriterEffect(writerLease) {
            try validateOwner()
            let lease = try POSIXArchiveWriterLease(nestedDirectory: controlDirectory)
            defer { lease.release() }
            guard try !DiskArchiveRecoveryJournal(lease: lease).hasUnresolvedTransactions() else {
                throw ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction
            }
            return (try capture.snapshot(), lease.generation)
        }
        let archive = try await capture.finish(snapshot) { [self] in
            try gate.withWriterEffect(writerLease) {
                try validateOwner()
                let lease = try POSIXArchiveWriterLease(nestedDirectory: controlDirectory)
                defer { lease.release() }
                guard lease.generation == generation,
                      try !DiskArchiveRecoveryJournal(lease: lease).hasUnresolvedTransactions() else {
                    throw Failure.changedDuringExport
                }
            }
        }
        return try JSONEncoder().encode(archive)
    }

    func importArchive(_ data: Data) throws -> DataImportSummary {
        // Refuse unsupported/torn files BEFORE the migration barrier can mutate data.
        let archive = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
        try UnifiedArchiveImportBinding.validate(archive)
        _ = try runtime.readMeals()
        _ = try runtime.writerBoundary.withEffect { try runtime.goalsRepository.load() }
        return try gate.withWriterEffect(writerLease) {
            try validateOwner()
            let owner = try ownerIdentity()
            guard !owner.isEmpty else { throw Failure.ownerMissing }
            let lease = try POSIXArchiveWriterLease(nestedDirectory: controlDirectory)
            defer { lease.release() }
            let journal = DiskArchiveRecoveryJournal(lease: lease)
            guard try !journal.hasUnresolvedTransactions() else {
                throw ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction
            }
            let binding = try UnifiedArchiveImportBinding(lease: lease, recoveryJournal: journal,
                ownerIdentity: owner, journal: runtime.journal, recipeContainer: recipeContainer,
                diary: diary, goals: runtime.goalsRepository, defaults: runtime.defaults,
                mediaDirectory: mediaDirectory)
            let before = try capture.snapshot()
            let result = try binding.importArchive(archive)
            // Same completion protocol as ArchiveStandaloneImportSession, but the
            // already-held account gate owns the flock. Never reacquire that flock.
            try lease.commitGeneration(lease.generation + 1)
            try journal.retire(result.committedTransactionID)
            let after = try capture.snapshot()
            let oldRecipes = Set(before.recipes.map(\.id))
            let oldShopping = Set(before.shoppingItems.map(\.id))
            let oldDiary = Set(before.nutritionDiaryEntries.map(\.id))
            return DataImportSummary(
                recipesAdded: Set(after.recipes.map(\.id)).subtracting(oldRecipes).count,
                shoppingItemsAdded: Set(after.shoppingItems.map(\.id)).subtracting(oldShopping).count,
                nutritionEntriesAdded: Set(after.nutritionDiaryEntries.map(\.id)).subtracting(oldDiary).count,
                journalEntriesAdded: result.journalEntriesAdded)
        }
    }
}
