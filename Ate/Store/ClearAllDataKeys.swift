import Foundation

/// Inventory-backed candidate lists. No auto-execution or blanket domain wipe.
/// Sync metadata/tombstones and credentials are deliberately NOT on these lists:
/// account/local scope decision and resurrection-safe protocol are unresolved.
enum ClearAllDataKeys {
    static let standard: Set<String> = [
        "ate.nutritionDiary.v1", "ate.nutritionGoals.v1", "ate.nutritionRecipeAssociations.v1", "ate.settings.v1", "ate.timerprefs.v1",
        "ate.cookSession.v1", "ate.cook.reflectionOffer.v1", "ate.cook.completionOutbox.v1",
        // Obsolete cooking-candidate key: the V6 candidate removed CookSessionToken entirely
        // (active cook session identity is central-owned AppStore state). Retained here only to
        // clean up copies an earlier candidate iteration may already have written.
        "ate.cook.sessionToken.v1", "ate.cooking.history.v1", "ate.draft.pending.v1", "ate.draft.card.v1",
        "ate.library.query", "ate.search.query", "ate.libraryFilter.v1", "ate.libraryLayout.v1",
        "ate.shopping.byAisle", "ate.sidebar.visible", "insights.tileOrder", "insights.lifecycle.v1",
        "ate.lastGeneration.v1", "ate.diagnostic-history.v1", "ate.liveactivity.log.v1",
        "ate.widgets.healthState", "ate.journalingSuggestions.enabled", "ate.ai.includeSchema",
        "ate.betaqa.v1", "ate.betaqa.magic", "ate.betaqa.lastRecipeCount",
        "ate.betaqa.history.v1", "ate.betaqa.catalogues.v1", "ate.betaqa.unreadable.backup.v1", "ate.betaqa.history.unreadable.backup.v1",
        "ate.health.asked.v1", "ate.health.lastRequestAt", "ate.health.lastRequestResult", "ate.health.mockScenario"
    ]
    static let standardPrefixes = ["insights.lifecycle.v1.account.", "ate.cover.gen.", "ate.betaqa.banner.", "ate.cook.completionOutbox.v1.unreadable."]
    static let shared: Set<String> = [
        "ate.widgets.snapshot.v1", "ate.widgets.pending.shopping.v1", "ate.widgets.pending.adds.v1",
        "ate.widgets.pending.url.v1", "ate.widgets.heartbeat.v1", "ate.inbox.v1", "ate.timers.v1", "ate.watch.timer.v1"
    ]
    // Preserve migration/cleanup markers until existing legacy backups are accounted
    // for, or they could trigger old-data import. Reset semantics need owner review.
    static let lifecycleMarkers: Set<String> = ["ate.foodJournal.diaryMigration.v1", "ate.journal.imagePromptCleanup.v1"]
    // "ate.clearAll.control.v1" is NON-personal reset control state (owner id, request
    // UUID, generation, phase) and must NEVER be erased mid-reset: it is what makes a
    // lost response recoverable and blocks resurrection. Deliberately absent above.
}
