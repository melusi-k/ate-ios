#if DEBUG
import SwiftUI

/// DEBUG-only hermetic route for canonical nutrition diary UI tests (issue #179 candidate
/// qualification). Compiled out of release builds and additionally gated on -UITesting at
/// runtime, so it cannot affect production: without BOTH the DEBUG build and the launch
/// argument this type does nothing.
///
/// Hermetic contract: everything the canonical diary can touch is per-launch ephemeral -
/// a UUID-named UserDefaults suite (never .standard), an in-memory journal container,
/// temp-directory goals storage and fresh backup directories. Concurrent processes never
/// share a suite or directory. Cleanup runs when the QA root disappears and before another
/// preparation in the same process. Forced process termination may leave QA-only residue;
/// another process never deletes it or consumes it as fixture truth.
@MainActor
enum CanonicalNutritionQARoute {
    static let flag = "-qaCanonicalNutrition"
    /// Variant that seeds a valid link and then overwrites the link store with undecodable
    /// bytes, so the "links unavailable" state is verifiable through the running app while
    /// the seeded entries still render.
    static let corruptLinksFlag = "-qaCanonicalNutritionCorruptLinks"
    private static var activeSuiteName: String?
    private static var activeDefaults: UserDefaults?
    private static var activeTempRoot: URL?

    static var isRequested: Bool {
        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains(flag)
    }
    private static var corruptLinksRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(corruptLinksFlag)
    }

    // MARK: - Fixture contract (central-owned; extend only with the named qualification set)

    /// Primary entry. Starts UNLINKED: the link, inspect and unlink journey runs on it.
    static let primaryEntryID = UUID(uuidString: "17900000-0000-4000-8000-000000000001")!
    /// Prior-day Pap: gives the frequent-foods suggestion a second logging of the same food.
    static let priorPapEntryID = UUID(uuidString: "17900000-0000-4000-8000-000000000003")!
    static let linkedRecipeID = "qa-nutrition-recipe"
    static let linkedRecipeTitle = "Miso salmon"

    private static var coordinator: FoodJournalCoordinator?
    private static var associationStore: NutritionRecipeAssociationStore?
    private static var goalsRepository: NutritionGoalsRepository?
    private static var repair: LegacyDiaryRepair?

    /// Builds the ephemeral world and seeds the fixtures. Call once from AteApp.init after
    /// the AppStore exists. No-op unless the flag is present.
    static func prepareIfRequested(store: AppStore) {
        guard isRequested else { return }
        cleanup()
        let identity = UUID().uuidString
        let suiteName = "ate.qa.canonical-nutrition.\(identity)"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ate-qa-canonical-nutrition-\(identity)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true) }
        catch { preconditionFailure("QA nutrition temporary directory unavailable: \(error)") }
        guard let qa = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("QA nutrition defaults suite unavailable")
        }
        activeSuiteName = suiteName
        activeDefaults = qa
        activeTempRoot = temp
        let journal = JournalStore(inMemory: true)
        let legacy = NutritionDiaryRepository(
            defaults: qa, backupDirectory: temp.appendingPathComponent("legacy-backups", isDirectory: true))
        let coord = FoodJournalCoordinator(journal: journal, legacy: legacy, markerDefaults: qa,
            backupDirectory: temp.appendingPathComponent("migration-backups", isDirectory: true))
        let goals = NutritionGoalsRepository(
            defaults: qa,
            storage: FileNutritionGoalsStorage(fileURL: temp.appendingPathComponent("nutrition-goals-v1.json")))
        let assoc = NutritionRecipeAssociationStore(defaults: qa)
        let rep = LegacyDiaryRepair(
            repository: legacy, backupDirectory: temp.appendingPathComponent("repair-backups", isDirectory: true))

        // Library: the recipe the journey links to resolves by exact id.
        if !store.recipes.contains(where: { $0.id == linkedRecipeID }) {
            store.recipes.append(RecipeCard(id: linkedRecipeID, title: linkedRecipeTitle))
        }

        // Entries: day keys derive from now, so the diary shows them without date navigation.
        // The primary entry starts UNLINKED on the ordinary route - the UI journey links it.
        let now = Date()
        let yesterday = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: now) ?? now
        let pap = NutritionDiaryEntry(
            id: primaryEntryID, foodName: "Pap", date: now, meal: .lunch,
            quantity: 2, quantityUnit: "portion", servings: 1.5,
            source: .externalFoodRecord, sourceName: "External record", sourceIdentifier: "ext-99",
            verificationNote: "From a label photo",
            nutrientsPerServing: NutritionSnapshot(
                energyKcal: 200, proteinGrams: 10, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        let priorPap = NutritionDiaryEntry(
            id: priorPapEntryID, foodName: "Pap", date: yesterday, meal: .dinner,
            quantity: 1, quantityUnit: "portion", servings: 1,
            source: .userProvided, sourceName: "Entered by you",
            verificationNote: "",
            nutrientsPerServing: NutritionSnapshot(
                energyKcal: 200, proteinGrams: 10, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil))
        for entry in [pap, priorPap] {
            do { try coord.saveMeal(entry) } catch {
                assertionFailure("QA canonical-nutrition seed failed to save \(entry.foodName): \(error)")
            }
        }
        if corruptLinksRequested {
            // Seed a valid link, then poison the store: entries must still render while the
            // link UI reports unavailable instead of pretending no links exist.
            do {
                try assoc.associate(entryID: primaryEntryID, recipeID: linkedRecipeID, recipeName: linkedRecipeTitle)
            } catch {
                assertionFailure("QA canonical-nutrition seed failed to link the fixture recipe: \(error)")
            }
            qa.set(Data("not a valid association payload".utf8), forKey: NutritionRecipeAssociationStore.storageKey)
        }

        coordinator = coord
        associationStore = assoc
        goalsRepository = goals
        repair = rep
    }

    /// The hermetic root content, or nil when the route is not requested. The shared
    /// .environment(store) modifier in AteApp.body applies to this content unchanged.
    static func rootView(store: AppStore) -> AnyView? {
        guard isRequested, let coordinator, let repair, let goalsRepository, let associationStore else { return nil }
        return AnyView(
            NavigationStack {
                CanonicalNutritionDiaryView(
                    coordinator: coordinator,
                    goalsRepository: goalsRepository,
                    repair: repair,
                    associationStore: associationStore)
            }
            .onDisappear { cleanup() }
        )
    }

    /// Deletes only this process's own QA namespace, never another launch's suite or files.
    static func cleanup() {
        if let activeSuiteName { activeDefaults?.removePersistentDomain(forName: activeSuiteName) }
        if let activeTempRoot { try? FileManager.default.removeItem(at: activeTempRoot) }
        activeSuiteName = nil
        activeDefaults = nil
        activeTempRoot = nil
        coordinator = nil
        associationStore = nil
        goalsRepository = nil
        repair = nil
    }
}
#endif
