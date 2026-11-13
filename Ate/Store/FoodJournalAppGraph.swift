import Foundation
import SwiftData

/// Required consumer capabilities, assembled against the graph's actual runtime.
/// No optional archive callbacks or default preservation path in an admitted graph.
@MainActor
struct FoodJournalConsumerBindings {
    let exportArchive: () async throws -> Data
    let importArchive: (Data) throws -> DataImportSummary
    let preservationDirectory: URL
}

/// Retained ordinary app graph. Creation is private: callers must pass through reset
/// resume, async reconciliation and final admission before any personal-data factory.
/// This stage assembles real capabilities; AteApp switches only after the production
/// resources, archive/reset participants and extension lifecycle have been bound.
@MainActor
final class FoodJournalAppGraph {
    struct Resources {
        let recipeContext: ModelContext?
        let journalStoreFileURL: URL
        let journal: JournalStore
        let defaults: UserDefaults
        let goals: NutritionGoalsRepository
        let migrationBackupDirectory: URL
        let repairBackupDirectory: URL
        let afterRestoreCommit: () throws -> Void
    }

    let composition: AccountResetComposition
    let writerLease: UUID
    let writerBoundary: FoodJournalWriterBoundary
    let runtime: FoodJournalRuntime
    let store: AppStore
    let syncService: GenerationFencedSyncService

    private init(composition: AccountResetComposition, writerLease: UUID,
                 writerBoundary: FoodJournalWriterBoundary, runtime: FoodJournalRuntime,
                 store: AppStore, syncService: GenerationFencedSyncService) {
        self.composition = composition
        self.writerLease = writerLease
        self.writerBoundary = writerBoundary
        self.runtime = runtime
        self.store = store
        self.syncService = syncService
    }

    /// Network reconciliation belongs to authorizeAdmission, outside the gate. Resource
    /// construction, Journal maintenance and AppStore.load run in one reentrant covered
    /// unit under the ORIGINAL admitted lease. No replacement lease after an await.
    static func startup(
        composition: AccountResetComposition,
        archive: ArchiveNestedLeaseBoundary,
        backend: BackendService,
        authorizeLocalState: @escaping (UUID, AccountResetComposition) throws -> Void,
        authorizeAdmission: @escaping (UUID) async throws -> Void,
        makeResources: @escaping (FoodJournalWriterBoundary) throws -> Resources,
        makeConsumers: @escaping (FoodJournalRuntime) throws -> FoodJournalConsumerBindings
    ) -> ResetAwareStartup<FoodJournalAppGraph> {
        composition.startup(authorizeLocalState: authorizeLocalState,
            authorizeAdmission: authorizeAdmission,
            buildGraph: { lease, composition in
                let perform = JournalWriterBoundaryComposition.makePerform(
                    gate: composition.gate, writerLease: lease, archive: archive)
                let validate = JournalWriterBoundaryComposition.makeValidator(
                    gate: composition.gate, writerLease: lease, archive: archive)
                let boundary = FoodJournalWriterBoundary(perform: perform)
                return try boundary.withEffect {
                    let resources = try makeResources(boundary)
                    let runtime = FoodJournalRuntime(journal: resources.journal,
                        goalsRepository: resources.goals, defaults: resources.defaults,
                        writerBoundary: boundary,
                        migrationBackupDirectory: resources.migrationBackupDirectory,
                        repairBackupDirectory: resources.repairBackupDirectory,
                        afterRestoreCommit: resources.afterRestoreCommit)
                    let consumers = try makeConsumers(runtime)
                    let syncService = composition.admittedSyncService(lease: lease)
                    let store = AppStore(context: resources.recipeContext, backend: backend,
                        nutritionDiaryRepository: NutritionDiaryRepository(defaults: resources.defaults,
                            backupDirectory: resources.repairBackupDirectory),
                        nutritionGoalsRepository: runtime.goalsRepository,
                        foodJournalRuntime: runtime,
                        journalWriterEffect: { effect in try boundary.withEffect(effect) },
                        journalWriterValidator: validate,
                        journalConsumerBindings: consumers, injectedSync: syncService)
                    store.journalLocalResetInventory = JournalLocalReset(journal: runtime.journal,
                        defaults: runtime.defaults, goalsStorage: runtime.goalsRepository.storage,
                        mediaDirectory: JournalStore.mediaDir,
                        migrationBackupDirectory: resources.migrationBackupDirectory,
                        repairBackupDirectory: resources.repairBackupDirectory,
                        preservationDirectory: consumers.preservationDirectory,
                        storeFileURL: resources.journalStoreFileURL)
                    return FoodJournalAppGraph(composition: composition, writerLease: lease,
                        writerBoundary: boundary, runtime: runtime, store: store, syncService: syncService)
                }
            })
    }
}
