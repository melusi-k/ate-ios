# Ordinary Food diary: log again (#179)

## Feature boundary

`NutritionDiaryView` now passes its already-loaded local entries through the existing `NutritionFrequentFoods.topFoods` helper to its add form. The collapsed "Log again" disclosure offers up to five previously logged foods. It is absent for an empty history and when editing an existing entry. No new storage, API, catalogue rows or canonical-diary activation is introduced.

Selecting a food fills name, quantity/unit, servings and the last logged nutrient snapshot. Unknown values remain blank, explicit zero remains zero. Values are labelled as the person's own prior input, not verified nutrition. External source IDs and verification notes are cleared. Date, selected calendar day and current meal stay with the new form. The original entry is not changed. Selection never saves, and Cancel never creates an entry. Only the existing explicit Save path allocates the new identity and persists; its existing validation and failed-save behavior are unchanged.

The disclosure starts collapsed to avoid putting five suggested rows above every existing form journey. Opening it and choosing a suggestion deliberately replaces the current editable values. The person can edit them before saving.

## Verification

- Python source suite: 243 tests PASS in working checkout and fresh depth-1 checkout.
- Three changed/added Swift files: tree-sitter Swift grammar PASS. This is not an Apple compiler/typecheck or XCTest execution.
- `git diff --check`: PASS.
- Added two XCTest unit cases for new identity/day/provenance/unknown values and local-history/deleted-row selection.
- Added separate ordinary-route UI journey `NutritionLogAgainUITests/testOrdinaryRepeatRequiresSaveCancelKeepsOneAndRelaunchKeepsTwo`. It requests four retained screenshots: offer, prefilled form, two saved rows and post-relaunch rows. It uses Settings > Food diary, not canonical fixture launch arguments.
- Existing native tests, source/helper behavior, CI selectors and timeout allowances are unchanged. Native tests, build/typecheck, simulator/device journey and actual pixel inspection are **UNRUN** here. No screenshots from this feature are claimed.

## Reviewer qualification still required

Run the two new unit cases, the named UI journey and the existing ordinary Diary add/edit/save-failure/recovery suite on the integrated exact candidate. The new UI class must be selected explicitly if the focused workflow uses a frozen selector list. Inspect the four actual images at normal text on iPhone 18 Pro, including the expanded suggestions, amount fields and Save/Cancel visibility. Check that the disclosure is a tappable, correctly labelled accessibility element, and that label/quantity text wraps without covering its neighbor. A static grammar/source pass cannot establish any of these.

Also inspect selection after typing a draft, switching source, failed Save then selection, selected-day changes, and an edit form with no reuse controls. Do not mark #179 complete or activate the canonical Journal paths from this bounded source delivery.
