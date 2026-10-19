# Expandable recipe-detail sheet prototype (#101)

## Decision and scope

The prototype is intentionally limited to **recipe cards in the Library's grid layout** (landscape iPhone and regular-width layouts). A card in this layout already behaves like a visual preview, so a compact glance followed by native sheet expansion is a natural interaction to evaluate.

The Library's single-column list, Explore destinations, and existing route-based recipe-detail entry points remain unchanged. This avoids converting every destination to a modal, keeps the current navigation stack as the default, and leaves Explore presentation decisions coordinated with #83.

## Interaction

- Selecting a Library grid card opens a native SwiftUI sheet at a 220-point compact detent.
- The compact preview shows the recipe cover, title, ingredient count, step count, and preparation time when available.
- The user can drag the sheet or choose **Expand recipe details** to move to the medium detent; medium and large reuse the existing `RecipeDetailView` inside a `NavigationStack`.
- The existing detail view continues to own servings, ingredients, steps, shopping-list handoff, recipe actions, and Cook Mode. No second detail implementation or duplicate recipe data state is introduced.
- The sheet supports the system drag indicator and resizable content interaction. Dismissing it leaves the Library's `SceneStorage` search query and existing Library view/scroll state in place.

## Automated evidence

`AteUITests/CoverageUITests.swift::test32c_ExpandableRecipeSheetOpensExpandsAndDismisses` covers opening the compact preview from the grid, expanding into the existing detail screen, scrolling, and returning to the grid. CI results must be recorded against the exact PR head SHA before treating this acceptance as verified.

## Still requiring device/accessibility review

Simulator UI automation does not establish physical-device behavior. Record separate evidence for VoiceOver focus during detent changes, largest Dynamic Type, Reduce Motion, landscape and compact-width behavior, and interactive dismissal/scroll handoff on a physical iPhone. No device-only checks are claimed complete by this prototype.
