# Bounded design-to-code drift audit, 2026-11-05

Status: Source inspection only. No code or runtime claim. Baseline: main `351c7f18170272112dfaf1a609b8519c31205008`. Scope: Food Journal's implementation baseline/migration contract, CI AI-lane policy and Intelligence Foundation issue #316 current-state inventory, checked against named Swift files and workflows. This is not an all-documents audit. Preserve historical records; propose a dated addendum rather than rewriting what was known on a prior date.

## Findings

### D1: Historical Journal-open baseline no longer describes current production code

- Document: [FOOD_JOURNAL.md](../product/FOOD_JOURNAL.md), section 10.1, dated 2026-10-31: the container opens with `try?` and silently degrades to empty.
- Source: `Ate/Services/JournalSuggestionService.swift`, `JournalStore.init(inMemory:)`: production calls `StoreRecovery.open`, includes `JournalMealPayload` in the schema, and records `openState`. Only the test in-memory initializer uses `try?` for opening.
- Disposition: PROPOSE FIX, Major documentation drift. Add a dated current-state note; retain the historical audit and do not claim recovery/UI acceptance from source inspection. Current draft qualification work remains independent.

### D2: Migration retirement differs from the documented contract

- Document: FOOD_JOURNAL section 10.3 says the legacy UserDefaults payload is left in place as a read-only backup behind a marker.
- Source: `Ate/Store/FoodJournalStore.swift`, `FoodJournalMigration.migrateIfNeeded`: verifies imported records, writes and reads back a file backup under `NutritionDiaryLegacyBackups`, then calls `legacy.clear()` and sets the migration marker.
- Disposition: ESCALATE, Major contract divergence. A verified backup file is not the same as keeping the original key. Decide whether the documented contract should follow the reviewed implementation or retirement must change. This audit authorizes neither a data mutation nor a code change. Do not call it data loss based on this source difference alone.

### D3: The current Foundation architecture inventory has no canonical repository design yet

- Source of intent: [issue #316](https://github.com/melusi-k/ate-ios/issues/316) asks for a current-state map, target architecture, ADRs, capability register, threat/data-flow review and evaluation plan before implementation.
- Repository: no `docs/architecture/ATE_INTELLIGENCE_FOUNDATION.md` or equivalent shared-platform design exists at the baseline. Existing source has App Intents and separate model call sites, not proof of the proposed shared context/model-service architecture.
- Disposition: PROPOSE FIX, Major documentation gap, not a missing feature regression. Create the proposed pilot design with unknowns explicit. Do not mark the shared platform implemented.

## Coverage and limits

Checked: `PRODUCT_LIFECYCLE.md`, `PRODUCT_OUTCOMES.md`, `docs/STACKED_PULL_REQUESTS.md`, `docs/CI.md`, `docs/product/FOOD_JOURNAL.md`; `JournalStore`, `FoodJournalStore`, `FoodJournalMigration`, `NutritionDiaryRepository`, `CookingHistory`, `OnDeviceBackend`, `JournalSuggestionService`, bounded model use in `InsightsView`, and issue #316. AI lane policy remains explicitly separate from ordinary CI and device quality; absence of a new drift finding is not proof that an eligible model device exists.

Not checked: every document, every App Intent/device surface, all privacy/export/reset paths, all dynamic consumers, real inference or native runtime behavior. Open PRs are not main. This report does not turn planned/unchecked requirements into drift defects automatically, and does not claim all unspecified code is wrong. Follow-up correction proposals need independent review and human decisions.
