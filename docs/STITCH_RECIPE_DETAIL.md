# Recipe Detail hierarchy, screen 3 source slice

Part of #614, not issue closure or feature acceptance.

## Scope and boundaries

`RecipeDetailFeature.stitchRecipeDetailEnabled` defaults ON. The detail shows the existing hero/source badge first, then a Yield & portions card with current scale and unchanged total time, the original scale picker, the original recipe content with ingredient/method entry counts and clearer headings, and a Cook and keep heading before the original Shopping/planning actions. All ingredient amounts, temperatures, method text, row IDs and buttons use the existing renderers and operations. Both content sections remain visible, not hidden behind a new tab. There is no model, source recipe or persisted state change.

OFF uses the original hero/picker/order and recipe content headings. RecipeCardView's new detailHierarchy option defaults false, so Add and other callers keep their original display. The flag is independent of other screens. Built Info.plist Boolean StitchRecipeDetailEnabled=false disables the new presentation; -qaStitchRecipeDetailOff only applies in UI-test mode. No remote toggle or new project-setting substitution is claimed.

Counts describe existing ingredient entries and nonblank rendered steps. Positive known total time is shown without scaling; no active-prep estimate is inferred. Positive yield scales only at 1/2/3 with overflow protection. Missing/invalid yield/time stays explicit. Legacy decoded servings can default to 2, so the display says recipe servings, not verified source yield.

No substitutions, variants/fork lineage, memo, pairing, rescue, Harmony scores or culinary approval are implemented or implied. Those acceptance items remain deferred. Existing Ask ate and repair semantics are unchanged: the current implementation can update the saved original after its existing scope/quality checks. This restyle is not a new reviewed-variant feature and does not claim that gap is solved. Source imports must retain their existing fidelity guards. No new automatic rewrite or action is introduced.

## Preserved behavior

ExpandableRecipeDetailSheet is unchanged: native detents, medium/large landscape handling, expand/collapse/dismiss, retained detail identity and Library context stay owned by it. The measured footer/timer clearance, scroll content reserve and floating Cook action are unchanged. Cook/Shopping/plan/share/favourite/edit/delete actions remain. Existing pilot nutrition hiding remains in RecipeNutritionView; no kcal/macros are added here. No backend, permissions, schema, persistence or paid service change.

## Tests and qualification

Three new unit sources cover current scaled yield/counts, unchanged time/source data, unknown/invalid values/overflow and independent flag ON/OFF. Three required unit names join the exact existing union, replacing none. Three UI sources cover ON metadata/scaling/original plan sheet, OFF original detail/footer, normal-text landscape/collapse/re-expand/return to grid. The existing saved-sheet fixture is reused without changes.

The UI class is selected and each method named-pass checked inside the existing presentation-creation transient-generation-retry step; existing xcresult attachment export carries screenshots. Existing test allowances 180/240 and job cap 110 minutes remain. No new job, dispatch, retry or gate waiver. Exact inverse restores RecipeDetailView, Components and workflow base bytes before historical guards.

Native build, XCTest/full units, mandatory Journal, UI execution, pixels and device acceptance are UNRUN here. Python is not Swift qualification. Reviewer owns publication and actual native evidence.

Within the existing qualification path, inspect normal-text iPhone 18 Pro portrait and landscape: hero/source/metadata/picker, ingredients, complete method, Shopping/plan/Ask actions, floating Cook, timers, all detents and dismissal. Verify no clipping, unreadable count, duplicate header/action, overlap or blocked tap. Keep screenshots immediately. Inspect OFF as well as ON; HTML is not native evidence.

Verify scaling 1/2/3 changes ingredients/yield but not source recipe or total time; Cook/Shopping receive the current factor. Exercise existing planning/share fallback and source recipe edit/repair error recovery without introducing a variant claim. Collapse/re-expand and rotate while scaled, then return to the original Library collection/sort/search context. Missing recipe uses the existing RecipeNotFoundView. Unknown time/empty content never gains made-up defaults in the new metadata.

Run existing full Journal and detail/timer regressions unchanged. Check offline cover/sharing/error recovery, failed repair preserving original, deleted recipe, active timer/footer clearance and no duplicate cook-start action. VoiceOver must read source, yield/time, counts, ingredient/method hierarchy and original actions in useful order at all detents. Reduce Motion must preserve expand/collapse and navigation without new animations. Larger text is supplementary; normal text remains the current acceptance target. Any visual or native regression remains blocked, not inferred green from source.
