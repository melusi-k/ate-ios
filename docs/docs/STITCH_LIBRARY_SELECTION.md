# Library multi-select, screen 1 source slice

Part of #612. This does not close the issue or qualify the feature for release.

## Implemented scope

- Explicit Select, Cancel and Deselect all. Selection is local to the Library view, not saved to disk or synced. Changing accounts cancels it. Removing saved IDs prunes the set without silently selecting replacements.
- Selected IDs are unique. Sharing resolves the latest saved cards and uses stable ID order, independent of tap, filter or display order. A hidden selected recipe remains selected until deselected, cancelled or removed from the saved Library.
- Summary counts selected saved recipes, sums positive saved servings with overflow protection, and names unknown time. Saved servings are metadata, not verified source yields. The existing RecipeCard decoder defaults missing legacy servings to 2; this slice does not invent source provenance or change that model contract.
- No aggregate cooking or active-prep time is calculated. Recipe total times cannot establish overlapping work, active prep or a batch schedule.
- A native text ShareLink joins the existing per-recipe text formatter. It does not publish recipe links, call a backend, copy to a clipboard automatically, or claim a share was delivered. The user chooses the destination in the system share sheet.
- Existing filters, collections, sort, list/grid switching, detail, native TabView, floating Search and timer surfaces remain. Selection disables card navigation, favourite/swipe/context actions and reorder while active. The summary is scrollable; the share control alone uses the bottom inset. Journal and rediscovery previews are hidden only during selection so that selectable recipe IDs appear once. Existing discovery is restored on Cancel.

## Explicitly deferred

No batch delete, batch undo, writable collection persistence, folder action or Meal Plan control is included. Current collections are derived filters, not writable folders. The existing single-recipe delete/undo contract is not wrapped in a loop. These acceptance items remain deferred, not passed. The full Stitch screen is not claimed complete.

## Flag and rollback

`StitchFeatureFlags.stitchLibraryMultiSelectEnabled` defaults ON. An explicit Boolean `StitchLibraryMultiSelectEnabled = false` in the built app's Info.plist removes entry into selection and retains the existing Library routes. There is no remote toggle or new project build-setting substitution. For DEBUG UI tests, `-UITesting -qaStitchLibraryMultiSelectOff` supplies OFF; a QA argument without UI-test mode cannot disable it. Reverting the source slice is the other rollback route. No stored selection or data migration needs cleanup.

## Verification status

Source tests and native test sources are distinct evidence. Python success does not compile Swift, run XCTest, inspect pixels or establish accessibility acceptance.

Five LibrarySelection unit tests cover explicit transitions, stable ordering/deduplication, missing IDs, invalid/unknown metadata, overflow, unchanged filter/layout/collection values, and ON/OFF defaults. Their five names are added to the existing full-unit required-pass ledger; none replaces an existing name. The existing advisory native lane selection is extended, without changing time allowances, retries, quarantine or runner budgets.

Six LibrarySelection UI test sources cover ON select/toggle/deselect/cancel/detail and native share-sheet presentation; OFF original detail; landscape grid and accessibility label/value/hit targets; filtered no-matches selection plus filter retention after Cancel; a truly empty Library, and saved-favourite/recently-cooked rediscovery hidden during grid selection. Landscape asserts the libraryGrid surface. They retain screenshots. All six are selected in the existing presentation-creation transient-generation-retry step with explicit named-pass checks and existing screenshot export. No new lane or dispatch is introduced. The existing 180/240-second test allowances and 110-minute job cap are unchanged.

## Native acceptance still required

Native compile, full unit results, mandatory Journal regressions, Library ON/OFF UI results, screenshots and device acceptance are UNRUN in the source environment. Reviewer owns publication and the existing native qualification path. Do not add a run, retry, allowance, runner budget or gate exception on the strength of this document.

On iPhone 18 Pro at normal text, inspect portrait list, landscape grid, two selected recipes, zero selected, filtered no matches, Cancel, OFF fallback and system share sheet. Confirm title/toolbar, selection summary, cards, Share, Add accessory, timer bar, tab bar and floating Search do not overlap, clip or intercept taps. Retain actual native screenshots immediately; HTML is not native visual evidence.

Manual regressions within the existing qualification path:

- Keep a selected collection, group and sort; enter/cancel selection and return from detail. Confirm all values and ordering remain. Switch to Search, type a query, return to Library and back to Search; each surface retains its own state and native tab behavior. Rotate during selection and confirm IDs/count survive.
- ON mode must toggle cards rather than open detail, favourite, reorder or delete. After Cancel and with OFF, verify list swipe/context actions, grid favourite/context actions, detail, My order drag and accessibility actions still use their original contracts. No bulk destructive control may appear.
- With the Library empty, verify no Select or Share. With filters hiding all results, retain selected count/share and allow Cancel and existing clear-filter recovery. Remove a selected recipe from another surface or sync and verify it disappears from the resolved share set. Account switch must cancel selection.
- Offline sharing must still offer the saved text without network dependence. Cancel the share sheet without a success claim. Sync/refresh failure must retain existing Library error/retry behavior and must not create fake recipes or reset query/filter/layout. This slice adds no server request and no separate loading/error placeholder.
- VoiceOver: traverse Select, each recipe, selected/not-selected value and selected trait, Deselect all, saved-servings/time text, Share and Cancel. Confirm logical order, no duplicate selectable IDs, accessible disabled Share at zero and no hidden destructive actions. Labels in source are not a VoiceOver run.
- Reduce Motion ON: repeat selection and cancellation with no added animation dependency. Normal text is the current acceptance target. Larger text is supplementary, not substituted for normal-text evidence.

No native visual result is attached to this source packet. Any overlap, missing labels, unreachable action, compile error or native regression remains a blocker to fix and recheck, not a pass inferred from source.
