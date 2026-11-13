import Foundation
import SwiftData

/// Called only after authoritative admission preflight, inside the original account
/// gate and before the ordinary archive boundary or any personal-data maintenance.
/// Raw containers must be opened strictly, without move-aside/empty-store recovery.
@MainActor
enum FoodJournalStartupRecovery {
    static func recover(controlDirectory: URL, ownerIdentity: String,
                        defaults: UserDefaults, diary: NutritionDiaryRepository,
                        goals: NutritionGoalsRepository, recipeContainer: ModelContainer,
                        journalContainer: @escaping () throws -> ModelContainer,
                        mediaDirectory: URL) throws {
        let lease = try POSIXArchiveWriterLease(nestedDirectory: controlDirectory)
        defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        try UnifiedArchiveStartupRecovery.recoverAtStartup(lease: lease, journal: journal,
            ownerIdentity: ownerIdentity, defaults: defaults, diary: diary, goals: goals,
            recipeContainer: recipeContainer, journalContainer: journalContainer,
            mediaDirectory: mediaDirectory)
    }
}
