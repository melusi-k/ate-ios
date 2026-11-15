import Foundation
import SwiftData

/// Dormant binding seam only. No disk open, fallback, migration, seed, cleanup,
/// archive wiring or activation. Startup must independently authorize this owner.
@MainActor
enum FoodJournalRuntimeFactory {
    enum Failure: Error, Equatable {
        case unavailable, nondurable, readOnly, incompatibleSchema, pendingChanges, defaultsMismatch, invalidBackupPaths
    }

    struct Bindings {
        let defaults: UserDefaults
        let goals: NutritionGoalsRepository
        let writerBoundary: FoodJournalWriterBoundary
        let mediaDirectory: URL
        let migrationBackupDirectory: URL
        let repairBackupDirectory: URL
        let afterRestoreCommit: () throws -> Void
    }

    static func bind(container: ModelContainer?, openState: JournalOpenState,
                     bindings: Bindings) throws -> FoodJournalRuntime {
        try bindings.writerBoundary.withEffect {
            guard openState == .ok, let container else { throw Failure.unavailable }
            guard !container.configurations.isEmpty,
                  container.configurations.allSatisfy({ !$0.isStoredInMemoryOnly }) else { throw Failure.nondurable }
            guard container.configurations.allSatisfy({ $0.allowsSave }) else { throw Failure.readOnly }
            let required = Set(Schema([JournalEntry.self, JournalMealPayload.self]).entities.map(\.name))
            guard required.isSubset(of: Set(container.schema.entities.map(\.name))) else { throw Failure.incompatibleSchema }
            guard !container.mainContext.hasChanges else { throw Failure.pendingChanges }
            guard bindings.goals.defaults === bindings.defaults else { throw Failure.defaultsMismatch }
            let paths = [bindings.mediaDirectory, bindings.migrationBackupDirectory, bindings.repairBackupDirectory]
            guard paths.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") && $0.path != "/" }),
                  Set(paths.map(\.standardizedFileURL)).count == paths.count else { throw Failure.invalidBackupPaths }
            // Validate committed data through isolated readers, never save, repair or
            // clear pending work. Corrupt meal pairing must not become an empty diary.
            _ = try FoodJournalStore(container: container).readMeals()
            let journal = JournalStore(container: container, openState: .ok,
                                       writerBoundary: bindings.writerBoundary, mediaDirectory: bindings.mediaDirectory)
            _ = try journal.readReflections()
            container.mainContext.autosaveEnabled = false
            return FoodJournalRuntime(journal: journal, goalsRepository: bindings.goals,
                defaults: bindings.defaults, writerBoundary: bindings.writerBoundary,
                migrationBackupDirectory: bindings.migrationBackupDirectory,
                repairBackupDirectory: bindings.repairBackupDirectory,
                afterRestoreCommit: bindings.afterRestoreCommit)
        }
    }
}
