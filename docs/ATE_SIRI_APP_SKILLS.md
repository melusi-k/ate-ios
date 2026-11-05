# Ate Siri App Skills integration

## Purpose and separation of concerns

Ate now has three distinct layers:

- **Coding-agent skills** in `.agents/skills/`: repository guidance for agents that develop and maintain Ate.
- **App Intents / Tool Intents**: typed, executable capabilities that Ate deliberately exposes to Apple system experiences.
- **App-specific Siri skills** in `Skills.skillsbundle`: concise natural-language guidance that helps Siri AI decide when and how multiple tools fit a user workflow.

The coding-agent skills do not get copied into the app bundle. Apple's app-skill format is a constrained subset: each skill is one `SKILL.md`; only `name` and `description` front matter are supported; scripts, references and companion files are not supported.

## Repository audit

The existing `Ate/Intents/AteAppIntents.swift` already contains useful foundations:

- `RecipeAppEntity` is an `AppEntity` and `IndexedEntity`, with recipe title, time, cuisine, favourite and ingredient metadata.
- `RecipeEntityQuery` resolves recipe identifiers and fuzzy title matches using `RecipeMatcher`.
- `SearchRecipesIntent` adopts Apple's `.system.search` schema and should remain a schema intent rather than being redundantly marked as a custom tool.
- Existing custom actions include opening a recipe, starting cook mode, adding a single shopping-list item, suggesting tonight's pick, importing a URL, creating an Ate Journal entry and other widget/Shortcuts actions.
- `AteShortcuts` publishes a curated set of App Shortcuts.

The app's deployment target remains iOS 18.0. Siri's new custom Tool Intent API is guarded with `@available(iOS 27.3, *)`; the CI toolchain is pinned to Xcode 27.3 for the preview SDK.

## First implemented workflow: find and cook a saved recipe

The first workflow deliberately stays read-first and avoids shopping-list or Journal side effects.

### Tool 1 — Find saved recipes

Implemented by `FindSavedRecipesToolIntent`:

- Accepts search words from a saved recipe title, ingredients or cuisine.
- Uses the existing `RecipeMatcher` ranking logic.
- Returns up to five matching saved recipe titles.
- Returns no match rather than inventing a recipe.
- Requires device authentication because recipe titles are private library content.
- Opens Ate before execution so the app's existing `AppStore` is available.

### Tool 2 — Start cook mode for a saved recipe

Implemented by `StartCookModeForRecipeToolIntent`:

- Requires a specific recipe name.
- Starts cook mode only when `RecipeMatcher` returns one confident match.
- If no recipe matches or multiple results remain plausible, it returns a clarification and performs no navigation.
- Requires device authentication.
- Does not fall back to tonight's pick and does not read Health-derived context.

This is intentionally separate from the existing `StartCookModeIntent`, which remains unchanged for current Shortcuts compatibility and retains its existing no-parameter "tonight's pick" behaviour. Siri's new multi-step workflow must not accidentally invoke that health-informed fallback when the person has not selected a recipe.

### App skill

The canonical runtime resource is:

```text
Skills.skillsbundle/
└── Skills/
    └── find-and-cook-recipe/
        └── SKILL.md
```

The skill references tool capabilities by their natural-language titles, not Swift type names. It instructs Siri to search first, ask the person to choose if multiple recipes match, and only then invoke the cook-mode tool with the selected title.

Siri skills are guidance, not a deterministic workflow engine. Each Tool Intent independently validates its inputs, authorization and side effects. No security boundary or mandatory sequence is delegated to Markdown.

## XcodeGen packaging

The root `Skills.skillsbundle` is added to the main `Ate` target as a folder reference resource:

```yaml
sources:
  - path: Skills.skillsbundle
    type: folder
    buildPhase: resources
```

Keeping the bundle at the repository root avoids XcodeGen's nested-folder-reference path issue and preserves the bundle's directory structure. It is included only in the main Ate app target, not the widgets, share extension, watch app, App Clip or test bundles.

The generated `.xcodeproj` is not the source of truth; `project.yml` remains authoritative.

## Apple's app-skill format contract

The validator in `scripts/validate-siri-skills.py` enforces the constraints used by this bundle:

- One `SKILL.md` per skill directory under `Skills.skillsbundle/Skills/`.
- Front matter contains exactly `name` and `description`.
- `name` is 1–64 lowercase letters, digits or hyphens and matches the skill directory.
- `description` is a single line no longer than 1,024 characters.
- Markdown body is no longer than 10,000 characters.
- No extra files are allowed inside a skill directory.

The validator is exercised by Python unit tests and runs in both PR compile validation and the release build workflow.

## Safety and privacy requirements

- Every Tool Intent validates its own parameters, current app state and authorization. Skill instructions are not a permission boundary.
- Recipe-library reads require local-device authentication; do not expose saved recipe titles on a locked device.
- The first workflow does not access HealthKit context, write to Journal, modify recipes or change shopping-list contents.
- Never infer permission to use HealthKit-derived context from a general recipe search or cooking request.
- Do not treat fuzzy matches as a selection when more than one plausible recipe remains.
- Do not claim cook mode started unless the tool reports success.
- Future write tools must separately define confirmation, authentication, idempotency and failure behaviour before a skill references them.

## Evaluation and rollout

### Automated checks

- XcodeGen must preserve the folder reference and copy the complete `Skills.skillsbundle` into `Ate.app`.
- The iOS 27.3 SDK must compile the availability-guarded Tool Intents.
- Unit tests cover exact matching, ambiguous matches and no-match behaviour.
- The skill validator checks Apple's metadata and content limits.
- Existing App Intents, App Shortcuts, Spotlight and widget behaviours must remain covered by regression tests.

### Device evaluation still required

Siri skill discovery and execution require a supported physical device; a Simulator build alone is not acceptance evidence. On a development-signed build with the supported iOS 27.3 preview:

1. Ask for a uniquely named saved recipe and confirm the search tool is selected.
2. Ask for a common term with two similarly ranked recipes and confirm Siri asks which one.
3. Choose one result and confirm only that recipe starts cook mode.
4. Ask to search without cooking and confirm no cook mode navigation occurs.
5. Ask for a nonexistent recipe and confirm no fallback or side effect occurs.
6. Repeat with the device locked and confirm authentication is required before recipe titles are returned or cook mode starts.
7. Confirm current Shortcuts phrases still behave as before.

Repeat natural-language evaluations because planner behaviour can vary. Record device model, OS build, Xcode build, phrases, selected tools, authentication outcomes and observed side effects.

### Preview distribution constraints

This is developer-preview integration work. Per Apple's current preview guidance, validate with development-signed builds and eligible internal TestFlight builds. Do not claim availability to external TestFlight testers or App Store users until Apple opens distribution and publishes the applicable submission terms. Keep customer-facing launch and release claims gated separately from code merge.

## Delivery status

- [x] Audit existing App Intents and preserve the system search schema.
- [x] Add narrowly scoped recipe search and cook-mode Tool Intents.
- [x] Add the first app skill using Apple's constrained `SKILL.md` format.
- [x] Embed the bundle in the main Ate target through XcodeGen.
- [x] Add a static skill-format validator and unit tests.
- [x] Pin PR and release CI to Xcode 27.3 for the preview APIs.
- [ ] Confirm clean XcodeGen output and successful simulator build/tests in CI.
- [ ] Verify Siri discovers the skill on a supported physical device.
- [ ] Complete repeated Siri evaluations, including ambiguity and lock-screen cases.
- [ ] Verify current App Shortcuts and existing system integrations on device.
- [ ] Reassess Apple's preview terms before any external or App Store distribution.

## References

- Apple, [Bringing custom actions and content to Siri](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri)
- Apple, [Orchestrating complex actions with app skills](https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills)
- Apple, [Making actions and content discoverable by Apple Intelligence](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence)
- Apple, [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy)
- Apple WWDC, [Secure your app: mitigate risks to agentic features](https://developer.apple.com/videos/play/wwdc2026/347/)
- XcodeGen, [Project specification](https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html)
