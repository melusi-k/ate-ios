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
