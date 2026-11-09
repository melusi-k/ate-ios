import Foundation
import SwiftData

/// Unified-graph account actions (#245, slice B). AppStore routes clear-library,
/// sign-out-remove, delete-account and Settings import/export here ONLY when
/// foodJournalRuntime != nil; the legacy paths are unchanged while it is nil.
///
/// Every mutation runs inside AppStore.journalWriterEffect - the composed writer
/// boundary central binds at activation (JournalWriterBoundaryComposition over
/// FoodJournalWriterBoundary). While that binding is nil these actions keep refusing,
/// so no ungated wipe or transfer of the unified Journal can happen.
@MainActor
extension AppStore {

    /// Unified "Clear all" (Settings): recipes plus the cook-completion context and
    /// cooking history THROUGH the runtime's stores - never the legacy singletons.
    /// Parity with the legacy action: diary/Journal meals are NOT cleared by it.
    func clearLibraryUnified() {
        guard let runtime = foodJournalRuntime, let effect = journalWriterEffect else {
            show("The unified Journal reset is not ready. Nothing was cleared.", error: true)
            return
        }
        do {
            try effect {
                self.clearCookCompletionContext()   // cookJournalDefaults is runtime-aware
                runtime.cookingHistory.clear()
                self.recipes = []
                self.path = []; self.shoppingPath = []; self.settingsPath = []
                self.morePath = []; self.searchPath = []
                self.persistRecipes()
            }
        } catch {
            // The boundary refused or failed mid-effect; never claim a clean wipe either way.
            show("ate couldn't clear the library safely. Try again in a moment.", error: true)
        }
    }

    /// Unified local wipe for sign-out-remove and delete-account. The legacy non-journal
    /// wipes (recipes/shopping/sync meta/timers/insights) still run; the unified Journal
    /// stores are erased and verified component-by-component through JournalLocalReset.
    /// Never throws into the UI: outcomes are the component report.
    @discardableResult
    func wipeLocalDataUnified() -> ClearAllLocalData.Report {
        guard let runtime = foodJournalRuntime, let effect = journalWriterEffect else {
            return ClearAllLocalData.Report(verifiedEmpty: [], failures: [
                ClearAllLocalData.Failure(component: "writer-boundary", operation: "acquire",
                                          detail: "unified writer boundary is not bound")])
        }
        var report: ClearAllLocalData.Report?
        do {
            try effect {
                self.wipeLocalData()            // legacy stores + non-journal surfaces
                runtime.cookingHistory.clear()  // the unified history, not the legacy singleton
                report = try JournalLocalReset(runtime: runtime,
                                               preservationDirectory: self.journalResetPreservationDirectory)
                    .eraseAll(validateWriterGate: { try effect({}) })
            }
        } catch {
            return ClearAllLocalData.Report(verifiedEmpty: [], failures: [
                ClearAllLocalData.Failure(component: "writer-boundary", operation: "effect",
                                          detail: String(describing: error))])
        }
        return report ?? ClearAllLocalData.Report(verifiedEmpty: [], failures: [
            ClearAllLocalData.Failure(component: "journal-components", operation: "erase",
                                      detail: "no component report produced")])
    }

    /// Unified Settings export. Format stays AteDataArchive v1 (diary parity only;
    /// reflections/media are slice A's v2 archive path). Meals come through the
    /// runtime's migration barrier; a non-durable or failed read THROWS - an unreadable
    /// unified store is never exported as an ordinary empty diary.
    func exportJSONUnified() throws -> Data {
        guard let runtime = foodJournalRuntime else {
            throw CanonicalConsumerBindingError.archiveBindingRequired
        }
        switch runtime.journal.openState {
        case .ok, .recovered: break
        case .inMemoryFallback, .unavailable: throw AteDataArchiveError.localDiaryUnreadableOnExport
        }
        let meals = try runtime.readMeals()   // barriered; throws on corrupt/failed
        let goals = try runtime.goalsRepository.load()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let archive = AteDataArchive(recipes: recipes, shoppingItems: shopping,
                                     nutritionDiaryEntries: meals,
                                     nutritionGoals: goals,
                                     appSettings: settings, timerPreferences: timerPrefs)
        return try enc.encode(archive)
    }

    /// Unified Settings import. Same validation and additive local-wins merge as the
    /// legacy path, but diary entries land in the unified store through the migration
    /// barrier and goals through the runtime's repository. Legacy diary bytes are never
    /// recreated. Requires the bound writer boundary (meals/goals are covered writes).
    func importJSONUnified(_ data: Data) throws -> DataImportSummary {
        guard let runtime = foodJournalRuntime, let effect = journalWriterEffect else {
            throw CanonicalConsumerBindingError.archiveBindingRequired
        }
        let decoder = JSONDecoder()
        if let legacyCards = try? decoder.decode([RecipeCard].self, from: data) {
            let result = importRecipesPreservingExisting(legacyCards)
            recipes = result.result.map(RecipeLogic.normalize)
            persistRecipes()
            return DataImportSummary(recipesAdded: result.added)
        }

        let archive = try decoder.decode(AteDataArchive.self, from: data)
        guard archive.format == AteDataArchive.formatName else { throw AteDataArchiveError.unsupportedFormat }
        guard archive.version == AteDataArchive.currentVersion else {
            throw AteDataArchiveError.unsupportedVersion(archive.version)
        }
        guard archive.nutritionDiaryEntries.allSatisfy(NutritionDiaryValidation.isValid) else {
            throw AteDataArchiveError.invalidNutritionEntry
        }
        // A non-durable unified store must refuse the whole import before anything is
        // written - the same fail-closed rule as the legacy corrupt-diary refusal.
        switch runtime.journal.openState {
        case .ok, .recovered: break
        case .inMemoryFallback, .unavailable: throw AteDataArchiveError.localDiaryUnreadable
        }
        guard let container = runtime.journal.container else {
            throw AteDataArchiveError.localDiaryUnreadable
        }

        let recipeResult = importRecipesPreservingExisting(archive.recipes)
        var shoppingIDs = Set(shopping.map(\.id))
        let newShoppingItems = archive.shoppingItems.filter { shoppingIDs.insert($0.id).inserted }
        // Barriered read migrates any remaining legacy diary first; a failed barrier
        // refuses the import. Additive merge: a matching ID on this device wins.
        let existingIDs = Set(try runtime.readMeals().map(\.id))
        let newMeals = archive.nutritionDiaryEntries.filter { !existingIDs.contains($0.id) }

        try effect {
            try runtime.goalsRepository.save(archive.nutritionGoals)
            if !newMeals.isEmpty {
                // Batch-atomic with conflict proof: a cross-kind identity clash fails the
                // whole batch instead of silently changing either record.
                try FoodJournalStore(container: container).importMeals(newMeals)
            }
            self.recipes = recipeResult.result.map(RecipeLogic.normalize)
            self.shopping.append(contentsOf: newShoppingItems)
            self.settings = archive.appSettings
            self.timerPrefs = archive.timerPreferences
            self.persistRecipes()
            self.persistShopping()
        }
        return DataImportSummary(recipesAdded: recipeResult.added,
                                 shoppingItemsAdded: newShoppingItems.count,
                                 nutritionEntriesAdded: newMeals.count)
    }
}
