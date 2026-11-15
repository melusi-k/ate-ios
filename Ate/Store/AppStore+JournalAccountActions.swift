import Foundation

/// Unified-graph account actions (#245, slice B). AppStore routes clear-library,
/// sign-out-remove, delete-account and Settings import/export here ONLY when
/// foodJournalRuntime != nil; the legacy paths are unchanged while it is nil.
///
/// Mutations run inside AppStore.journalWriterEffect - the composed writer boundary
/// central binds at activation (JournalWriterBoundaryComposition over
/// FoodJournalWriterBoundary) - and re-prove it through AppStore.journalWriterValidator
/// (gate.validateWriter only, never a generation-committing empty effect). While those
/// bindings are nil these actions keep refusing, so no ungated wipe or transfer of the
/// unified Journal can happen.
///
/// Unified export/import do NOT live here: the archive format, capture discipline and
/// the standalone import session are A's services (UnifiedArchiveCapture,
/// ArchiveStandaloneImportSession), injected as journalArchiveExport/journalArchiveImport.
/// AppStore only routes to them; with no callbacks injected the canonical refusal stands.
@MainActor
extension AppStore {
    private enum JournalAccountActionError: Error { case localWipeNotPerformed }

    /// Unified "Clear all" (Settings): recipes plus the cook-completion context and
    /// cooking history THROUGH the runtime's stores - never the legacy singletons.
    /// Parity with the legacy action: diary/Journal meals are NOT cleared by it.
    /// The account-wide Clear-all inventory (journal rows, media, goals, backups,
    /// adoption-preservation copies) is installed separately: central binds
    /// JournalLocalReset.components(validateWriterGate:) into the Clear-all coordinator.
    @discardableResult
    func clearLibraryUnified() -> Bool {
        guard let runtime = foodJournalRuntime, let effect = journalWriterEffect else {
            show("The unified Journal reset is not ready. Nothing was cleared.", error: true)
            return false
        }
        var performed = false
        do {
            try effect {
                performed = true
                self.clearCookCompletionContext()   // cookJournalDefaults is runtime-aware
                runtime.cookingHistory.clear()
                self.recipes = []
                self.path = []; self.shoppingPath = []; self.settingsPath = []
                self.morePath = []; self.searchPath = []
                self.persistRecipes()
            }
            guard performed else { throw JournalAccountActionError.localWipeNotPerformed }
            return true
        } catch {
            // The boundary refused or failed mid-effect; never claim a clean wipe either way.
            show("ate couldn't clear the library safely. Try again in a moment.", error: true)
            return false
        }
    }

    /// Unified local wipe for sign-out-remove and delete-account. The legacy non-journal
    /// wipes (recipes/shopping/sync meta/timers/insights) still run; the unified Journal
    /// stores are erased and verified component-by-component through JournalLocalReset.
    /// Per-component re-proof uses journalWriterValidator (gate.validateWriter only) -
    /// an empty composed effect would commit an archive generation per component and a
    /// nested validation inside the held outer lease could stamp a second generation
    /// and go stale. Never throws into the UI: outcomes are the component report.
    @discardableResult
    func wipeLocalDataUnified() -> ClearAllLocalData.Report {
        guard let runtime = foodJournalRuntime,
              let effect = journalWriterEffect,
              let validate = journalWriterValidator else {
            return ClearAllLocalData.Report(verifiedEmpty: [], failures: [
                ClearAllLocalData.Failure(component: "writer-boundary", operation: "acquire",
                                          detail: "unified writer boundary is not bound")])
        }
        guard let inventory = journalLocalResetInventory,
              inventory.journal === runtime.journal, inventory.defaults === runtime.defaults,
              inventory.mediaDirectory == runtime.journal.mediaDirectory else {
            return ClearAllLocalData.Report(verifiedEmpty: [], failures: [
                ClearAllLocalData.Failure(component: "reset-inventory", operation: "preflight",
                    detail: "retained graph reset participants are not bound")])
        }
        var report: ClearAllLocalData.Report?
        do {
            try effect {
                guard self.wipeLocalData() else { throw JournalAccountActionError.localWipeNotPerformed }
                // legacy stores + non-journal surfaces completed under the outer effect
                runtime.cookingHistory.clear()  // the unified history, not the legacy singleton
                report = try inventory.eraseAll(validateWriterGate: validate)
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

    /// Canonical export entry point (Settings export button awaits this). Unified graph:
    /// the injected A UnifiedArchiveCapture callback (snapshot() + finish(stillCurrent:)
    /// before any bytes are published); a nil callback refuses. Legacy graph: today's
    /// legacy exportJSON, unchanged.
    func exportUserData() async throws -> Data {
        if foodJournalRuntime != nil {
            guard let export = journalArchiveExport else {
                throw CanonicalConsumerBindingError.archiveBindingRequired
            }
            return try await export()
        }
        return try exportJSON()
    }

    /// Sync exportJSON can never serve the unified graph: the capture callback is async,
    /// and falling back to a locally assembled v1 archive would duplicate (and silently
    /// diverge from) A's archive path. It refuses unconditionally; exportUserData() is
    /// the canonical route.
    func exportJSONUnified() throws -> Data {
        throw CanonicalConsumerBindingError.archiveBindingRequired
    }

    /// Unified Settings import routes whole-file to A's standalone
    /// ArchiveStandaloneImportSession (injected as journalArchiveImport): validation,
    /// barriered migration, per-store ordering and the covered writer effect all live
    /// in that session. AppStore deliberately keeps no journal import sequence of its
    /// own. A nil callback refuses with the canonical error.
    func importJSONUnified(_ data: Data) throws -> DataImportSummary {
        guard foodJournalRuntime != nil, let importSession = journalArchiveImport else {
            throw CanonicalConsumerBindingError.archiveBindingRequired
        }
        return try importSession(data)
    }
}
