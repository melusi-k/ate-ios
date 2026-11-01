# Food Journal — product and implementation contract

**Status:** Proposed implementation contract for [#245](https://github.com/melusi-k/ate-ios/issues/245)  
**Decision:** Unify Food Diary and Ate Journal into one chronological Journal experience.  
**Scope note:** This document defines the product contract and safe implementation sequence. It does not claim that the app, persistence layer, Supabase schema, or migration has already been changed.

## 1. Product intent

Ate's Journal should tell the story of what someone ate, cooked and wants to remember. Food tracking and reflection belong in one timeline, but they must remain independently useful.

Every successfully saved food diary meal is represented in the Journal automatically. A user never has to write anything to complete a food log. Standalone reflections are also supported.

The primary destination is **Journal** (working product concept: **Food Journal**). Avoid retaining two competing top-level destinations for the same history once parity and migration are proven.

## 2. Core user journeys

### Log a meal

1. User records a meal using the existing fast diary flow.
2. The meal and its structured nutrition details save using the existing diary persistence contract.
3. The saved meal appears exactly once in the Journal timeline.
4. Writing a note, adding a photo or recording context is optional and can happen immediately or later.
5. Editing the meal updates the same logical entry; it must not create a duplicate or change its original local-day identity unexpectedly.

### Write a standalone reflection

1. User chooses **New journal entry**.
2. User writes a reflection and may add supported media/context.
3. The entry appears in the same chronological timeline without fabricated meal or nutrition data.
4. Editing, cancellation and deletion follow the existing safe journal interaction contract.

### Reflect on a cooked recipe

1. User explicitly completes cooking using the existing cooking-history semantics.
2. Ate may offer a small, dismissible invitation to write about the experience.
3. The prompt can suggest questions such as what worked, what was changed, whether the user would cook it again, or who they shared it with.
4. The user may write now, dismiss, or return later. Cooking completion must never depend on writing.
5. The journal entry links to the cooked recipe and preserves enough historical recipe context to remain useful if the recipe is later edited or deleted.

Prompt frequency and dismissal persistence must be deterministic, respectful and covered by tests. Do not repeatedly interrupt the user.

## 3. Unified entry contract

The user-facing timeline is unified; the underlying data remains typed and structured. Do not store nutrition as prose or make a reflection mandatory.

Conceptual shape (not a prescription to duplicate existing persisted models):

- Stable entry identity and owner.
- Original event date/time and the local-day/time-zone semantics already used by diary aggregation.
- Entry kind: meal or reflection.
- Optional reflection content and supported media.
- Optional structured meal payload/reference containing meal type, food items, quantities/portions, nutrient values and provenance.
- Optional cooked-recipe association with a historical snapshot or equivalent durable representation.
- Optional user-provided context such as mood, energy or tags only where already supported and explicitly entered by the user.
- Created/updated metadata and any prompt-dismissal state needed for non-intrusive UX.

Before implementing this shape, audit the existing SwiftData JournalEntry, food diary model/store, recipe/cooking-history identifiers, and Supabase schema. Reuse or evolve existing canonical models where possible. Do not introduce a second source of truth.

## 4. Persistence, privacy and migration guardrails

- Preserve existing local-first and signed-out behavior.
- The current journal's local-only privacy promise remains in force unless a separate, explicit product decision changes it.
- Do not move journal content to Supabase merely because the feature is being unified.
- If cloud persistence or sync is proposed, document the user value, conflict semantics, retention/deletion/export behavior and privacy impact first; implement only through an additive, reviewed schema change.
- Every new Supabase table/policy must be user-scoped, least-privilege and covered by RLS tests. Never ship a service-role key in the app.
- Migration must be additive, idempotent, recoverable and tested against populated legacy stores.
- Preserve stable IDs, timestamps, timezone/day keys, food-item details, quantities, nutrient provenance and totals.
- Preserve existing journal text, media, location metadata and local-only behavior.
- Never silently replace malformed records with an empty collection or discard data that cannot be migrated. Keep recoverable backups and surface partial failures truthfully.
- Recipe deletion or unavailability must not leave an opaque/broken historical entry.

## 5. Timeline and interaction requirements

- Chronological, date-grouped Journal timeline with meal entries and standalone reflections.
- Meal cards show meal type, time, food summary and relevant nutrition; reflection text/media is optional.
- Reflection-only cards are visually distinct but belong to the same timeline.
- Entry detail, edit and safe delete confirmation.
- Calendar/date navigation and deterministic filters for meal type, recipe-linked entries and reflections.
- Search should cover supported user-authored content without exposing private data.
- Clear loading, empty, offline, failed-save and recovery states.
- VoiceOver, Dynamic Type, accessible tap targets and responsive layout are required.
- Food logging remains a short, low-friction flow; do not turn every meal into a mandatory multi-step journal form.

## 6. Delivery sequence

1. **Audit and design:** inspect current Food Diary work (#179 and its active PR stack), Journal (#38/#66/#67), cooking history (#31), SwiftData stores and Supabase schema. Record the canonical model, privacy boundary and migration plan.
2. **Persistence foundation:** implement the smallest safe shared domain/persistence change and migration. Add round-trip, duplicate prevention, legacy-data, corrupt-store and recovery tests.
3. **Unified timeline:** show meal and reflection entries together; preserve current nutrition and journal capabilities. Add focused UI/accessibility tests.
4. **Entry composition and editing:** optional reflection on meals plus standalone reflections; preserve entry identity and meal-day semantics.
5. **Cooked-recipe prompts:** link completed cooking events to journal entries, retain recipe context, and add dismissible prompt behavior.
6. **Navigation retirement:** remove the duplicate destination only after feature parity, migration and regression acceptance are demonstrated.

Do not destabilize or duplicate the in-flight #179 nutrition stack. Coordinate changes that overlap its diary model rather than building a competing parallel implementation.

## 7. Acceptance checklist

- [ ] Each successfully saved meal appears exactly once in Journal without requiring text.
- [ ] Editing a meal updates the same logical entry and preserves its original local-day semantics.
- [ ] Standalone reflections can be created, cancelled, edited and safely deleted.
- [ ] Meal reflections can be added/edited independently of nutrition fields.
- [ ] Cooked recipes can be linked to entries and offer an optional, dismissible writing prompt.
- [ ] Prompt dismissal/frequency is persisted and deterministic; cooking completion is never blocked.
- [ ] Historical recipe context remains understandable after recipe edits/deletion.
- [ ] Existing diary totals, calculations, food details and historical records are unchanged.
- [ ] Existing journal text, photos/location metadata and local-only privacy behavior are preserved.
- [ ] Timeline, detail, calendar, filters, search, empty/error/offline states and accessibility are covered.
- [ ] Migration is idempotent, recoverable and tested against populated and malformed legacy data.
- [ ] No unapproved cloud sync or privacy-boundary change is introduced.
- [ ] If Supabase is changed, additive migrations, RLS/ownership tests and deletion/retention behavior are reviewed.
- [ ] Exact-head unit, persistence/migration, focused UI/accessibility and applicable backend tests pass; skipped or quarantined tests are not counted as passes.

## 8. Ownership map

- [#245](https://github.com/melusi-k/ate-ios/issues/245): unified Food Journal product contract and integration.
- [#179](https://github.com/melusi-k/ate-ios/issues/179): nutrition calculations, food diary and optional goals.
- [#38](https://github.com/melusi-k/ate-ios/issues/38), [#66](https://github.com/melusi-k/ate-ios/pull/66), [#67](https://github.com/melusi-k/ate-ios/issues/67): existing journal/Health acceptance and deferred device evidence.
- [#31](https://github.com/melusi-k/ate-ios/issues/31): cooking completion and history semantics.
- [#37](https://github.com/melusi-k/ate-ios/issues/37): shared navigation, accessibility and responsive regressions.

## 9. Non-goals for the first delivery

- Mandatory journaling or ratings after meals.
- AI-generated emotional/health interpretations or nutrition judgement.
- Replacing or weakening existing nutrition calculations and provenance.
- Automatically syncing currently local-only journal content to a cloud service.
- Writing entries into Apple's Journal app; Ate's Journal remains its own experience.

## 10. Implementation audit and canonical design (recorded 2026-10-31)

This section records the step-1 audit required by the delivery sequence, the canonical model decision, the privacy boundary and the migration plan. File references are against `main` at the time of writing; the in-flight #179 PR stack (#239/#240/#241) extends the diary files noted below.

### 10.1 Current state audit

**Ate Journal (#38 foundation).** `JournalEntry` is a SwiftData `@Model` (Ate/Models/HealthModels.swift) persisted in its own `ModelContainer` (configuration `AteJournal`) owned by `JournalStore` (Ate/Services/JournalSuggestionService.swift). It is local-only by design and code comment ("Never synced or sent anywhere"), matching the #38 privacy invariants in docs/HEALTH_JOURNAL_TRACKER_HUB.md. Fields: stable string `id`, `createdAt`, `prompt`, `text`, `stateRaw` (HealthState), `recipeIDs`, Journaling Suggestions provenance (`journalingSuggestionTitle`, `momentDate`, `sourceRaw`), location (`locationName`/coordinates), `mediaFileNames` (bytes in Application Support/JournalMedia) and `editedAt`. UI is `JournalListView`/`JournalEntryDetailView` (Ate/Views/JournalViews.swift) with search, edit, share and confirmed delete; entry points are the Insights hub preview and the Library explore sheet; Siri/Shortcuts and Journaling Suggestions write through `JournalStore`.

**Food Diary (#179).** `NutritionDiaryEntry` is a Codable struct array in UserDefaults (`ate.nutritionDiary.v1`) behind `NutritionDiaryRepository` (Ate/Logic/NutritionDiary.swift), which distinguishes absent/corrupt payloads, never overwrites unreadable data and backs up before reset. Entries carry stable UUIDs, `date` plus a persisted local `dayKey` (YYYY-MM-DD), meal type, quantity/unit/servings, structured `NutritionSnapshot` (nil means unknown, never estimated) and full provenance (`source`, `sourceName`, `sourceIdentifier`, `verificationNote`). Goals live in a separate repository. UI is `NutritionDiaryView`/`NutritionGoalsView`, entered from Settings > Food diary. PRs #239-#241 (in flight) extend exactly `NutritionDiary.swift`, `NutritionDiaryView.swift`, `NutritionGoalsView.swift` and their tests (CI coverage, entry editing, weekly totals).

**Cooking history (#31).** `CookingHistory` (Ate/Logic/CookingHistory.swift) stores day-key to recipe-ID sets in UserDefaults with explicit Finish-cooking completion semantics. It stays owned by #31; the Food Journal reads it and does not change its semantics.

**Sync boundary.** Supabase sync covers recipes only (last-write-wins via `SyncService`); journal, diary, goals and cooking history are all local today. No Supabase journal/diary tables exist, and this design introduces none.

**Gaps found.** (1) The journal container opens with `try?` and silently degrades to an empty list on store corruption, while the recipes container has `StoreRecovery` move-aside backup semantics; the unified store must not keep that silent-empty behavior. (2) Journal media files have no backup/export path. (3) With diary in UserDefaults and journal in SwiftData, a meal and its reflection have no shared identity, which is the structural problem this initiative removes.

### 10.2 Canonical model decision

One local SwiftData journal store (the evolved `AteJournal` container) is the canonical store. A unified entry has a stable identity, original event `date` plus preserved local `dayKey`, created/updated metadata, and a `kind` of `meal` or `reflection`.

- **Reflection entries** keep every existing `JournalEntry` field and behavior (prompt, text, state, moment provenance, location, media, source).
- **Meal entries** carry an optional structured meal payload as a typed child model - never prose: meal type, food name, quantity/unit/servings, nutrient snapshot (nullable values; nil stays unknown) and the existing provenance fields verbatim. An optional reflection (text/media) attaches to the same entry identity.
- **Recipe association** stores the recipe ID plus a durable snapshot (at minimum title and cooked date/day) so the entry remains understandable after the recipe is edited or deleted.
- Nutrition values remain structured and queryable; diary totals and calculations keep operating on the same typed fields they use today.

Rationale: one identity per meal (editing updates the same entry; no duplicates), one timeline query for the unified view, no second source of truth for diary records, and the local-only privacy promise is preserved because the store is the existing local SwiftData container.

### 10.3 Migration plan

1. `NutritionDiaryRepository` keeps its current API shape (load/save/corrupt-recovery semantics) but becomes a facade over the unified store, so #179 views, calculations and tests keep working unchanged.
2. A one-time idempotent migrator copies UserDefaults diary records into meal entries keyed by their existing UUIDs. Re-runs skip already-migrated IDs; original `date`, `dayKey`, quantities, nutrients and provenance are preserved verbatim.
3. The legacy UserDefaults payload is left in place (read-only backup) behind a migrated marker; it is never silently deleted. Malformed or unconvertible records are backed up first and surfaced as an honest recovery state, never dropped.
4. The unified journal container opens through move-aside backup recovery equivalent to `StoreRecovery` (R-DATA-01), closing the silent-empty gap. Save failures go through the same retry/report path as the rest of the app (R-DATA-02).
5. Diary corruption handling is preserved through migration: an unreadable legacy payload is backed up before any reset, and saving is disabled until recovery, exactly as today.

### 10.4 Privacy boundary (unchanged)

Journal and meal data remain local-only. No Supabase tables, columns or policies are introduced; no sync behavior changes; signed-out/local-first behavior is untouched. Any future cloud persistence proposal is a separate, explicitly reviewed product decision per section 4.

### 10.5 Sequencing with the in-flight #179 stack

Phase 2 (persistence facade re-point) touches files owned by the active #239-#241 stack. To avoid destabilizing that work: the unified store, migrator and their tests are built as new files in parallel, and the facade re-point lands only after the #179 stack merges. Timeline, composition, prompts and navigation retirement follow the section 6 sequence on top.

### 10.6 Test plan (phase 2 minimum)

Round-trip save/load of both entry kinds; idempotent migration over a populated legacy store (second run creates nothing); stable IDs and day keys across time-zone changes; totals identical before/after migration on fixture data; corrupt legacy payload backed up and surfaced, never discarded; corrupt unified store moved aside with honest recovery state; failed-save reporting; duplicate-prevention when a meal save races migration. UI/accessibility coverage for timeline, detail, edit, filters and states lands with phases 3-5 per section 7.
