# Ate Design Token Foundation

## Status

**Phase:** 1 — Token foundation  
**Status:** Provisional baseline; not yet approved as the canonical design system  
**Source baseline:** Existing SwiftUI implementation on `main`  
**Figma workspace:** Created — [Ate — Design System](https://www.figma.com/design/rnBsUzukcZYENdHahlj3zO) (Add Colour Agency team).  
**Figma status:** Provisional variables and foundation reference pages created; pending design/product review.

This phase establishes a safe, reviewable token contract without changing the app's appearance or mass-refactoring consumers. The current repository is the evidence baseline, not a substitute for the design source of truth.

## Ownership and flow

1. Figma Variables will own approved design intent once the canonical file/library is confirmed.
2. `design-tokens/tokens.json` is the version-controlled export/snapshot reviewed in GitHub.
3. Generated Swift token definitions will be derived from the reviewed JSON; generated files must be marked and never hand-edited.
4. SwiftUI components own behaviour, accessibility, interaction and layout composition. They consume semantic tokens rather than inventing new brand values.
5. CI will validate the snapshot and generated output after the export contract and generation are implemented. CI must not require a live Figma session or network access.

The new Figma file is the design workspace, but its initial values were transcribed from the existing SwiftUI implementation. Neither the Figma variables nor this JSON are approved design decisions yet; both remain provisional until reviewed. The JSON remains the version-controlled contract candidate.

## Figma workspace initialized

The initial Figma Design file is [Ate — Design System](https://www.figma.com/design/rnBsUzukcZYENdHahlj3zO).

Pages created:
- `00 — Overview`: ownership, governance and current scope.
- `01 — Foundations`: bound colour specimens, typography notes, geometry, layout and platform exceptions.

Provisional variable collections:
- `Color / App / Light`: 18 semantic colour variables.
- `Color / App / Dark`: 18 semantic colour variables.
- `Foundation / Core`: 7 variables covering font families, radii and content width.
- `Platform / Widgets (Legacy)`: 3 isolated widget palette variables.

All 36 app colour specimens on the foundations page are bound to Figma variables. iOS code syntax is recorded against the existing `Theme` and `WTheme` members where a direct mapping exists.

**Figma plan limitation:** this workspace currently permits one mode per variable collection. Light and Dark therefore live in separate collections instead of one collection with two modes. If multi-mode support becomes available, consolidate these collections deliberately and verify all bindings.

**Intentionally not created:** a canonical spacing scale, fixed semantic type ramp, or production component library. The codebase does not yet define enough approved information to create those without inventing design decisions. The observed spacing values remain documentation only.

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
- Radius values vary by component and some are hard-coded at call sites. The recorded 14pt button radius is an observed non-capsule variant, not the default shape: `AteButtonStyle` defaults to `capsule=true`, height 48pt and a minimum rendered height of 44pt. The 12pt field radius is also an observed component literal, not a named Swift token.
- JSON entries identify the existing Swift member where one exists; `swiftMember: null` means an observed literal or semantic description, not an exported member. Widget palette mappings use `swiftMembers`. `Theme.brown` is deliberately excluded: it is a fixed shadow colour (#311F16), not the adaptive foreground token.
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

Confirm ownership of the created Ate Figma workspace and review its provisional Variables, collection conventions and mapping against this implementation baseline. Agree the export format and schema before enabling code generation. Workspace creation is complete; design approval and an automated export are not.
