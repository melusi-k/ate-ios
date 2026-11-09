import Foundation
import SwiftData

/// Production binding: journaled unified-archive import against the real stores (#245 slice A).
/// NOT wired to AppStore or Settings: activation calls this inside the composed writer
/// boundary (account gate OUTER, archive INNER). The lease is always injected, already
/// acquired by the caller's mode:
///  - standalone import session: lifetime flock on the shared writer-gate-v1.lock
///    (ArchiveStandaloneImportSession), or
///  - nested per-effect boundary (ArchiveNestedGenerationBoundary) for ordinary effects.
///
/// This binding NEVER advances the writer generation itself: the enclosing boundary advances
/// exactly once after a successful committed unit, so a throwing import commits nothing.
/// On any failure the recovery transaction stays durably on disk for startup recovery;
/// retained guards elsewhere are not weakened to force partial activation.
@MainActor
final class UnifiedArchiveImportBinding {
    struct Result: Equatable {
        let journalEntriesAdded: Int
        let journalEntriesSkippedExisting: Int
    }

    enum Failure: LocalizedError {
        case emptyOwnerIdentity
        case unsupportedFormat
        case unsupportedVersion(Int)
        /// A version-2 archive without its Journal section is torn, not a v1 archive.
        case journalSectionMissing

        var errorDescription: String? {
            switch self {
            case .emptyOwnerIdentity: "The archive import has no owner identity."
            case .unsupportedFormat: "This file is not a supported ate data export."
            case .unsupportedVersion(let version): "This export (version \(version)) is newer than this version of ate can read."
            case .journalSectionMissing: "This export is incomplete: its Journal section is missing. Nothing was imported."
            }
        }
    }

    let lease: POSIXArchiveWriterLease
    let recoveryJournal: DiskArchiveRecoveryJournal
    let ownerIdentity: String
    let journal: JournalStore
    let recipeContainer: ModelContainer
    let diary: NutritionDiaryRepository
    let goals: NutritionGoalsRepository
    let defaults: UserDefaults
    let mediaDirectory: URL

    init(lease: POSIXArchiveWriterLease, recoveryJournal: DiskArchiveRecoveryJournal,
         ownerIdentity: String, journal: JournalStore, recipeContainer: ModelContainer,
         diary: NutritionDiaryRepository, goals: NutritionGoalsRepository,
         defaults: UserDefaults, mediaDirectory: URL) throws {
        guard !ownerIdentity.isEmpty else { throw Failure.emptyOwnerIdentity }
        try lease.validate()
        self.lease = lease
        self.recoveryJournal = recoveryJournal
        self.ownerIdentity = ownerIdentity
        self.journal = journal
        self.recipeContainer = recipeContainer
        self.diary = diary
        self.goals = goals
        self.defaults = defaults
        self.mediaDirectory = mediaDirectory
    }

    static func validate(_ archive: AteUnifiedArchive) throws {
        guard archive.format == AteUnifiedArchive.formatName else { throw Failure.unsupportedFormat }
        guard archive.version == 1 || archive.version == AteUnifiedArchive.currentVersion else {
            throw Failure.unsupportedVersion(archive.version)
        }
        if archive.version == AteUnifiedArchive.currentVersion, archive.journal == nil {
            throw Failure.journalSectionMissing
        }
        guard archive.nutritionDiaryEntries.allSatisfy(NutritionDiaryValidation.isValid) else {
            throw AteDataArchiveError.invalidNutritionEntry
        }
    }

    /// Decodes and validates an export. Legacy recipe-card arrays are NOT accepted here:
    /// activation decides whether the legacy cards path remains; this route imports the
    /// versioned archive only.
    func decode(_ data: Data) throws -> AteUnifiedArchive {
        let archive = try JSONDecoder().decode(AteUnifiedArchive.self, from: data)
        try Self.validate(archive)
        return archive
    }

    /// Imports additively (existing identity wins everywhere) under the durable recovery
    /// journal: prepare -> applying -> execute -> committed -> retire. The generation
    /// advance is deliberately left to the enclosing boundary.
    func importArchive(_ archive: AteUnifiedArchive,
                       checkpoint: (ArchiveRestoreBoundary) throws -> Void = { _ in }) throws -> Result {
        try lease.validate()
        try Self.validate(archive)

        // Participants snapshot exact before-images and precompute planned writes. Their
        // initializers throw on corrupt existing data BEFORE any recovery record or store
        // mutation exists, so a corrupt local state can never be overwritten by an import.
        let nutrition = try ArchiveNutritionParticipant(diary: diary, goals: goals,
            incomingDiary: archive.nutritionDiaryEntries, incomingGoals: archive.nutritionGoals,
            validateLease: { [lease] in try lease.validate() })
        let defaultsParticipant = try ArchiveDefaultsParticipant(defaults: defaults,
            settings: archive.appSettings, timerPrefs: archive.timerPreferences,
            validate: { [lease] in try lease.validate() })
        let recipeShopping = try ArchiveRecipeShoppingParticipant(container: recipeContainer,
            incomingRecipes: archive.recipes, incomingShopping: archive.shoppingItems,
            validate: { [lease] in try lease.validate() })
        let outer = ArchiveOuterComposite(components: [nutrition.participant(),
            defaultsParticipant.participant(), recipeShopping.participant()])

        // A version-1 archive carries no Journal section: import its outer sections with an
        // empty Journal plan, exactly the legacy outer semantics on the new journaled path.
        let journalSection = archive.journal ?? JournalArchive(entries: [], media: [:])
        let plan = try JournalArchiveRestore.prepare(journalSection, journal: journal)

        // Recovery images. Before: exact raw bytes. After: the planned write, re-derived here
        // from the same inputs and then verified against the ACTUAL store bytes at the
        // afterVerification checkpoint, before the transaction can be marked committed.
        let nutritionBefore = try readNutritionImage()
        let nutritionAfter = try Self.plannedNutritionImage(before: nutritionBefore,
            incomingDiary: archive.nutritionDiaryEntries, incomingGoals: archive.nutritionGoals)
        let defaultsBefore = readDefaultsImage()
        let defaultsAfter = try Self.plannedDefaultsImage(before: defaultsBefore,
            settings: archive.appSettings, timerPrefs: archive.timerPreferences)
        let recipesBefore = try Self.snapshotRecipeShopping(recipeContainer)
        let recipesAfter = try Self.plannedRecipeShoppingImage(before: recipesBefore,
            incomingRecipes: archive.recipes, incomingShopping: archive.shoppingItems)

        let payload = JournalMediaRecoveryPayload(version: 1, entries: plan.archive.entries,
                                                  media: plan.archive.mediaSHA256)
        let record = ArchiveRecoveryRecord(version: 1, transactionID: UUID(),
            ownerIdentity: ownerIdentity, storeGeneration: lease.generation,
            images: [
                ArchiveRecoveryImage(component: ArchiveComponentName.nutrition,
                    before: try JSONEncoder().encode(nutritionBefore),
                    after: try JSONEncoder().encode(nutritionAfter)),
                ArchiveRecoveryImage(component: ArchiveComponentName.defaults,
                    before: try JSONEncoder().encode(defaultsBefore),
                    after: try JSONEncoder().encode(defaultsAfter)),
                ArchiveRecoveryImage(component: ArchiveComponentName.recipeShopping,
                    before: try JSONEncoder().encode(recipesBefore),
                    after: try JSONEncoder().encode(recipesAfter)),
            ],
            journalAndMediaRecovery: try JSONEncoder().encode(payload))

        try recoveryJournal.prepare(record)
        try recoveryJournal.transition(record.transactionID, to: .applying)

        // JournalArchiveFilesystemMedia requires the destination directory to exist.
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let media = try JournalArchiveFilesystemMedia(directory: mediaDirectory,
            validateLease: { [lease] in try lease.validate() })

        let added = try JournalArchiveRestore.execute(plan, journal: journal, media: media,
            outer: outer.participant(),
            beforeCompensation: { [recoveryJournal] in
                // Durable undo intent BEFORE any compensation can run, including after a
                // failed finish. This is the production beforeCompensation wiring.
                try recoveryJournal.transition(record.transactionID, to: .compensating)
            },
            checkpoint: { [self] boundary in
                try checkpoint(boundary)
                if boundary == .afterVerification {
                    try self.verifyAfterImages(nutrition: nutritionAfter,
                                               defaults: defaultsAfter, recipes: recipesAfter)
                }
            })
        try recoveryJournal.transition(record.transactionID, to: .committed)
        // Retirement is an atomic namespace move only, so it is safe to finish before the
        // enclosing boundary advances the generation.
        try recoveryJournal.retire(record.transactionID)
        return Result(journalEntriesAdded: added, journalEntriesSkippedExisting: plan.skippedExisting)
    }

    // MARK: - recovery images

    func readNutritionImage() throws -> ArchiveNutritionImage {
        ArchiveNutritionImage(diary: diary.defaults.data(forKey: NutritionDiaryRepository.storageKey),
                              goalFile: try goals.storage.read(),
                              legacyGoals: goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey))
    }

    func readDefaultsImage() -> ArchiveDefaultsImage {
        ArchiveDefaultsImage(settings: defaults.data(forKey: ArchiveDefaultsParticipant.settingsKey),
                             timer: defaults.data(forKey: ArchiveDefaultsParticipant.timerKey),
                             syncMeta: defaults.data(forKey: ArchiveDefaultsParticipant.syncMetaKey))
    }

    /// Mirrors ArchiveNutritionParticipant's planned write exactly: existing entries decode
    /// without migration, additions are new identities only, one plain JSONEncoder pass.
    static func plannedNutritionImage(before: ArchiveNutritionImage,
                                      incomingDiary: [NutritionDiaryEntry],
                                      incomingGoals: DailyNutritionGoals) throws -> ArchiveNutritionImage {
        let existing = try before.diary.map { try JSONDecoder().decode([NutritionDiaryEntry].self, from: $0) } ?? []
        var ids = Set(existing.map(\.id))
        let additions = incomingDiary.filter { ids.insert($0.id).inserted }
        let newDiary = try JSONEncoder().encode(existing + additions)
        let newGoalFile = incomingGoals.isEmpty ? nil : try JSONEncoder().encode(incomingGoals)
        // The participant always removes the legacy goals key.
        return ArchiveNutritionImage(diary: newDiary, goalFile: newGoalFile, legacyGoals: nil)
    }

    static func plannedDefaultsImage(before: ArchiveDefaultsImage, settings: AppSettings,
                                     timerPrefs: TimerPrefs) throws -> ArchiveDefaultsImage {
        ArchiveDefaultsImage(settings: try JSONEncoder().encode(settings),
                             timer: try JSONEncoder().encode(timerPrefs),
                             syncMeta: before.syncMeta)
    }

    /// Exact raw store snapshot in canonical order, mirroring the participant's reads.
    static func snapshotRecipeShopping(_ container: ModelContainer) throws -> ArchiveRecipeShoppingImage {
        let read = ModelContext(container)
        read.autosaveEnabled = false
        let recipeRows = try read.fetch(FetchDescriptor<RecipeEntity>())
        let recipes = recipeRows.map {
            ArchiveRawRecipeImage(id: $0.id, createdAt: $0.createdAt, position: $0.position, json: $0.json)
        }.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
        let shoppingRows = try read.fetch(FetchDescriptor<ShoppingEntity>())
        let shopping = shoppingRows.map {
            ArchiveRawShoppingImage(id: $0.id, position: $0.position, json: $0.json)
        }.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
        return ArchiveRecipeShoppingImage(recipes: recipes, shopping: shopping)
    }

    /// Mirrors ArchiveRecipeShoppingParticipant's merge exactly: existing identity wins and
    /// is never re-encoded, contentless recipes are skipped, new recipes prepend as a
    /// reversed batch with reindexed positions, new shopping items append.
    static func plannedRecipeShoppingImage(before: ArchiveRecipeShoppingImage,
                                           incomingRecipes: [RecipeCard],
                                           incomingShopping: [ShoppingItem]) throws -> ArchiveRecipeShoppingImage {
        var recipeIDs = Set(before.recipes.map(\.id))
        let freshRecipes = incomingRecipes.filter { recipeIDs.insert($0.id).inserted }
        let importable = freshRecipes
            .filter { !($0.ingredients.isEmpty && $0.steps.isEmpty) }
            .map(RecipeLogic.normalize)
        var shopIDs = Set(before.shopping.map(\.id))
        let freshShopping = incomingShopping.filter { shopIDs.insert($0.id).inserted }

        let enc = JSONEncoder()
        var plannedRecipes: [ArchiveRawRecipeImage] = try importable.reversed().map {
            ArchiveRawRecipeImage(id: $0.id, createdAt: $0.createdAt, position: 0, json: try enc.encode($0))
        }
        plannedRecipes.append(contentsOf: before.recipes.map {
            ArchiveRawRecipeImage(id: $0.id, createdAt: $0.createdAt, position: 0, json: $0.json)
        })
        for i in plannedRecipes.indices {
            plannedRecipes[i] = ArchiveRawRecipeImage(id: plannedRecipes[i].id,
                createdAt: plannedRecipes[i].createdAt, position: i, json: plannedRecipes[i].json)
        }
        var plannedShopping = before.shopping
        for item in freshShopping {
            plannedShopping.append(ArchiveRawShoppingImage(id: item.id,
                position: plannedShopping.count, json: try enc.encode(item)))
        }
        return ArchiveRecipeShoppingImage(recipes: plannedRecipes, shopping: plannedShopping)
    }

    /// Runs at the afterVerification checkpoint, inside execute's compensation scope: any
    /// divergence between the recorded after-images and the actual store fails the restore
    /// and triggers compensation, never a committed mismatch.
    private func verifyAfterImages(nutrition: ArchiveNutritionImage, defaults expectedDefaults: ArchiveDefaultsImage,
                                   recipes: ArchiveRecipeShoppingImage) throws {
        guard try readNutritionImage() == nutrition,
              readDefaultsImage() == expectedDefaults,
              try Self.snapshotRecipeShopping(recipeContainer) == recipes else {
            throw ArchiveRestoreFailure.verificationFailed
        }
    }
}
