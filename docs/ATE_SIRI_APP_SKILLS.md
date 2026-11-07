# Ate Siri App Skills integration

## Status

Implementation foundation and rollout design for Apple's app-specific Siri skills preview. This document is intentionally a preparation step: it does not claim that the app-specific skill resource is already packaged, that existing intents are Tool Intents, or that Siri AI is available to production users.

**Parent:** PR #317 — `docs: add project Agent Skills foundation`  
**Stack:** `feat/ate-siri-app-skills` is based on `docs/ate-agent-skills-foundation`.

## Purpose

Give Siri AI app-specific guidance for multi-step Ate workflows while preserving a strict separation between:

- **Coding-agent skills** in `.agents/skills/`: instructions for agents that develop and maintain Ate.
- **Apple app-specific Siri skills**: runtime guidance delivered in the Ate app target so Siri can choose and coordinate Ate's system-facing capabilities.
- **App Intents / Tool Intents**: the executable, typed capabilities Siri can invoke.

The existing coding-agent skill files do not become Siri resources and must not be copied into the app target.

## Current Ate foundation (repository audit)

The app already has a substantial App Intents implementation in `Ate/Intents/AteAppIntents.swift`:

- `RecipeAppEntity` is an `AppEntity` and `IndexedEntity`, with a string query and recipe metadata.
- `GroceryEntity` and `GroceryQuery` expose shopping-item values.
- `AteJournalEntryEntity` adopts Apple's Journal entry entity schema.
- Existing actions include opening a recipe, starting cook mode, adding one shopping-list item, tonight's pick, importing a recipe URL, searching recipes, creating an Ate journal entry, and opening a journal entry.
- `AteShortcuts` publishes App Shortcuts for cook mode, shopping, dinner suggestions, timers, importing and adding recipes. Some shortcut actions are implemented in other files and need a complete inventory before migration.

The repository currently targets iOS 18.0 and uses XcodeGen (`project.yml`). The main app target includes `Ate/Resources/BuildNotes.md` as a resource. This matters because the new Apple skill resource must be represented correctly in the generated Xcode project, not merely committed as an arbitrary Markdown file.

### Important migration rule

Do not mechanically convert every existing `AppIntent` or every App Shortcut into a Tool Intent. First decide whether each action is a useful, independently safe tool for Siri AI. Preserve the current Siri, Shortcuts, Spotlight, widget and app-routing behavior while introducing any new tool surface.

## Target architecture

1. **Domain capabilities** remain in Ate's existing stores and services. Intent implementations should be thin adapters; do not move business logic into skill Markdown.
2. **Tool Intents** expose small, well-described actions with typed parameters and results. Their descriptions should explain the user-facing action and the meaning of each parameter in natural language.
3. **Entities and queries** provide stable identity, useful display metadata and deliberate disambiguation. Avoid exposing private or unnecessary model fields.
4. **App-specific skills** explain when a multi-step workflow is appropriate, which tools are relevant, how to resolve ambiguity, what order is normally useful, and which actions require user confirmation.
5. **Siri evaluations and device tests** measure whether the system chooses appropriate tools and asks for missing information. Skills guide the planner; they do not enforce a deterministic sequence or replace validation in each intent.

## Proposed first workflows

Start with a read-oriented workflow and only add write steps when the underlying tools are independently safe.

### 1. Find and cook a saved recipe

**User goal:** “Find a quick chicken recipe and start cook mode.”

Candidate capabilities already present:
- Search saved recipes / resolve a `RecipeAppEntity`.
- Disambiguate close recipe matches.
- Open a recipe or start cook mode.

Skill guidance should prefer a confident exact match, ask the user to choose when results are ambiguous, and never substitute an unrelated recipe. If no suitable recipe exists, explain that and stop rather than inventing one.

This is the best first evaluation workflow because it composes existing recipe discovery and navigation without introducing a new bulk-write action.

### 2. Turn a saved recipe into a shopping-list update

**User goal:** “Add the ingredients I’m missing for this recipe to my Ate list.”

Before enabling this workflow, verify that the tool surface can:
- Read the selected recipe's complete ingredient list (the current Siri entity intentionally exposes only a limited ingredient projection).
- Read the current shopping list reliably.
- Compare equivalent ingredient names without silently treating different quantities or units as interchangeable.
- Add missing items safely, with clear confirmation before a multi-item write.

The current `AddToShoppingListIntent` adds one item. Do not describe it as a batch-add capability or assume a shopping-list read tool exists until the source is inspected and tested.

### 3. Save a user-requested journal reflection

**User goal:** “Save this reflection in my Ate journal.”

The existing Journal schema intent validates empty content and image-prompt-like text before saving. A skill may explain when to use it, but must not silently create, rewrite or attach content the user did not ask to save. Treat journal text and media as private user content; do not expose it as incidental context for unrelated workflows.

## Skill authoring contract

Use the Apple app-specific skill resource template supplied by the exact supported Xcode / SDK preview. The expected Markdown entry point is `SKILL.md` with YAML front matter containing a stable skill name and a concise description, followed by natural-language workflow guidance.

Example content shape (illustrative only; final resource wrapper and packaging must come from Xcode's template):

```markdown
---
name: find-and-cook-recipe
description: Find a saved recipe in Ate, resolve which recipe the person means, and open it or start cook mode.
---

# Find and cook a saved recipe

Use this guidance when a request combines recipe discovery with opening or cooking a saved recipe.

- Search Ate's saved recipes before suggesting a recipe.
- Prefer an exact, high-confidence match.
- If multiple recipes are plausible, ask which one the person means.
- Use the open-recipe action when the person wants to view a recipe.
- Use cook mode only when the person asks to start cooking.
- If no suitable recipe exists, explain that and stop.
- Never claim that a recipe was cooked, changed, or saved unless the relevant action reports success.
```

Author tool references using natural-language descriptions of the capability, not Swift type names. Swift names can change and are implementation details; user-facing descriptions are the semantic contract.

Keep skill descriptions specific to the workflow they match. The description is the discovery surface; the body should contain only the additional guidance needed once Siri selects the skill.

## Resource packaging and XcodeGen

Do not guess the bundle extension, directory nesting, build phase or target membership from the generic Agent Skills convention.

Implementation must:
1. Create a throwaway skill using the app-specific resource template in the target Xcode preview.
2. Inspect the generated project and built product to establish the exact resource wrapper and folder layout.
3. Reproduce that structure in the repository's XcodeGen `project.yml` so a fresh `xcodegen generate` preserves it.
4. Confirm the skill is embedded in the main Ate app target and is not accidentally copied into extensions, tests or the coding-agent skill tree.
5. Verify the packaged resource can be discovered by Siri on a supported development device.

If XcodeGen cannot express the template's resource structure faithfully, document the smallest deterministic generation step and test it in CI. Do not hand-edit the generated `.xcodeproj` as the source of truth.

## Safety and privacy requirements

- Every Tool Intent validates its own parameters, authorization, current app state and side effects. A skill is not a permission boundary.
- Read operations should remain read-only.
- Ask for clarification when recipe identity, ingredient equivalence, list destination or requested outcome is ambiguous.
- Require explicit user confirmation before multi-item shopping-list changes, destructive operations, or any externally visible action.
- Never silently create or alter Journal entries. Journal writes must be explicitly requested and validated.
- Do not infer permission to use HealthKit-derived context from a general meal-planning request. Health context remains out of the initial skill scope unless its use is separately justified, disclosed and permission-checked.
- Do not expose private journal text, health data, account data, or unrelated recipe content in tool descriptions or skill examples.
- Report partial success accurately; do not claim that a whole workflow completed when one of its actions failed.

## Evaluation plan

Create a version-controlled evaluation set alongside the first implementation. For each workflow include:

- Direct and indirect natural-language phrasings.
- Ambiguous entity names and multiple plausible matches.
- Missing required parameters.
- Empty libraries and empty shopping lists.
- Requests that should stop rather than take action.
- Confirmation-required and denied-confirmation cases.
- Tool failure, stale data and partial-success cases.
- Negative cases where a similar but incorrect intent should not be selected.

Run scenarios repeatedly because planner responses can vary. Compare intent selection, parameter resolution, clarification behaviour, confirmation behaviour, side effects and final user-facing response. Supplement automated evaluations with on-device Siri testing on supported OS / language / region configurations.

Use Apple's Siri integration diagnostics and evaluation tooling when available in the selected Xcode preview. Record the exact Xcode build, OS build, device, test inputs and outcomes; do not report preview-only results as production acceptance.

## Delivery sequence and rollout gates

### Phase 0 — Preview/toolchain validation
- Confirm the exact Xcode and iOS beta versions required for app skills and Tool Intents.
- Confirm the resource template, bundle structure, API spelling, availability annotations and testing tooling from the installed SDK.
- Confirm preview eligibility, distribution restrictions, privacy terms and regional/device prerequisites.
- Record these decisions before changing `project.yml`.

### Phase 1 — Tool Intent readiness
- Inventory every existing App Intent, entity, query and App Shortcut, including implementations outside `AteAppIntents.swift`.
- Map each user goal to the smallest useful set of independently safe tools.
- Improve titles, descriptions, parameter descriptions and entity disambiguation.
- Convert or add only the tools needed for the first workflow.
- Keep existing Shortcuts and Siri behaviour covered by regression tests.

### Phase 2 — First app skill
- Package one `find-and-cook-recipe` skill using Xcode's resource template.
- Add the resource to XcodeGen's main app target.
- Validate discovery and execution on a supported development device.
- Add the initial Siri evaluation cases and record results.

### Phase 3 — Additional workflows
- Add recipe-to-shopping-list only after list-read and multi-item write safety are proven.
- Add Journal workflow only with explicit save semantics and privacy tests.
- Add further skills only when a real multi-tool workflow benefits from extra guidance; do not create a skill for every intent.

### Phase 4 — Release readiness
- Re-run the evaluation suite after changes to tools, entity metadata or skill descriptions.
- Verify supported OS, device, language and region behaviour.
- Confirm Apple's current preview and distribution terms before enabling or advertising the capability.
- Keep production rollout disabled until Apple's distribution and review requirements permit it.
- Document rollback by removing the app-specific skill resource / feature exposure while retaining the established App Intents used by other system surfaces.

## Acceptance criteria

- [ ] Exact app-skill resource format and bundle structure verified from the selected Xcode template.
- [ ] XcodeGen reproduces the resource packaging from a clean project generation.
- [ ] Existing App Intents and App Shortcuts are inventoried and regression-tested.
- [ ] At least one independently safe Tool Intent workflow is verified end to end.
- [ ] First app-specific skill is discovered by Siri on a supported development device.
- [ ] Ambiguity, missing data, denial, failure and partial-success scenarios are evaluated.
- [ ] No unrequested Journal writes, bulk shopping-list changes or Health data disclosure occur.
- [ ] Preview-only constraints and release eligibility are documented; no production availability is implied.

## References

- Apple, App Intents overview: https://developer.apple.com/documentation/appintents
- Apple, App Intents and Apple Intelligence discovery: https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence
- Apple, creating an App Intent: https://developer.apple.com/documentation/appintents/creating-your-first-app-intent
- Apple, App Intents system experiences: https://developer.apple.com/documentation/appintents/adopting-app-intents-to-support-system-experiences
- Apple Xcode help, Siri configuration: https://help.apple.com/xcode/mac/current/en.lproj/devb1fc06729.html
