# Ate Design Token Foundation

## Status

**Phase:** 1 — Token foundation  
**Status:** Provisional baseline; not yet approved as the canonical design system  
**Source baseline:** Existing SwiftUI implementation on `main`  
**Figma reconciliation:** Pending access to the canonical Figma file/library and Variables.

This phase establishes a safe, reviewable token contract without changing the app's appearance or mass-refactoring consumers. The current repository is the evidence baseline, not a substitute for the design source of truth.

## Ownership and flow

1. Figma Variables will own approved design intent once the canonical file/library is confirmed.
2. `design-tokens/tokens.json` is the version-controlled export/snapshot reviewed in GitHub.
3. Generated Swift token definitions will be derived from the reviewed JSON; generated files must be marked and never hand-edited.
4. SwiftUI components own behaviour, accessibility, interaction and layout composition. They consume semantic tokens rather than inventing new brand values.
5. CI validates the snapshot and generated output. CI must not require a live Figma session or network access.

Until the Figma connection and export contract are verified, the JSON is explicitly a **provisional implementation baseline**.

## Current implementation findings

### Existing foundations

- `Ate/Design/Theme.swift` already contains `Theme`, `Palette` and `AteFont`.
- The app has light/dark semantic colours and high-contrast variants for selected muted text and borders.
- Contrast ratios are calculated in `Palette`; `AccessibilityTests` exercises the palette.
- Typography uses bundled Fraunces for display and DM Sans for body, with system fallbacks and Dynamic Type-relative sizing.
- A shared card surface, button style, icon button, motion helper and page-width helper already exist.
- `Theme.maxWidth` is 672pt and the primary card radius is 20pt.

### Known divergence / gaps

- `AteWidgets/HomeWidgets.swift` defines an independent `WTheme` palette (including primary `#C95028`) which differs from the app's accessible primary colour (`#B9481F`). Treat this as a platform exception requiring explicit design/contrast review, not silently overwrite it.
- `Ate/Views/Components.swift` contains reusable components but is not yet a separately governed component package/module.
- Spacing values are used inline across views; observed values are recorded in JSON for audit only. They are not yet a canonical spacing scale.
- Radius values vary by component and some are hard-coded at call sites.
- The PRD contains intended visual specifications; reconcile those with the live Figma library and current implementation before declaring a token canonical.

## Token conventions

- Prefer semantic names (`action.primary`, `text.muted`, `surface.card`) over names tied to a screen or component.
- Store colours as explicit light/dark values. Keep alpha-bearing values explicit.
- Keep accessibility/high-contrast variants explicit where they exist.
- Use points for native layout dimensions.
- Do not infer missing tokens or normalize existing values without design approval.
- Preserve platform-specific exceptions (app, widgets, watch, share extension) until parity is deliberately designed and tested.
- Token changes must include affected-platform review and accessibility/contrast evidence.

## Phase 1 acceptance

- [x] Inventory existing app theme, typography and key geometry primitives.
- [x] Record the current implementation values in `design-tokens/tokens.json`.
- [x] Record known divergence and non-standardized areas.
- [ ] Confirm canonical Figma file/library and Variables ownership.
- [ ] Agree token naming, mode/collection structure and export format with the design source.
- [ ] Validate the exported token snapshot against the agreed schema.
- [ ] Decide and implement deterministic JSON-to-Swift generation.
- [ ] Add CI drift/schema validation after the export contract is stable.
- [ ] Verify app, widget and accessibility behaviour before migrating consumers.

## Explicit non-goals for this phase

- No visual redesign.
- No mass replacement of inline spacing or corner radii.
- No change to production colours or typography.
- No Figma MCP-driven code generation into the app.
- No new component library or component rewrite.
- No requirement for CI to contact Figma.

## Next decision

Connect the Figma integration and identify the canonical Ate design file/library. Then compare its Variables and component conventions against this provisional baseline and produce a reviewed mapping before code generation is enabled.
