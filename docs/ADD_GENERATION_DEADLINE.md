## Forward stack revision

This revision descends from local merge 2e29ba0c46cd62e3ed7c43f79a6dc7898ad88b95,
whose first parent is #628 hosted head fb0b0da15186123830dcf1b39fab218c0b7496fd
and second parent is #627 hosted head 5c2f86228f46d404e8e4a5d082de32d4daedf4ac.
Those hosted heads are siblings, not descendants. No replay of an older packet. Both existing inverse JSON fixtures AND helpers are
byte-carried. New deadline inverse first restores the exact combined merge source. An additive sibling composition inverse then
restores the selected exact hosted parent before its unchanged original inverse
restores454. Six new
native required names append to the parent union. Both parents' 361 Python checks plus six new deadline checks run here.

Typed Explore creative path, source-bound Add behavior, title-only confirmation,
oven-removal correction, no raw preview channel and all quality/source guards
remain intact. New first-snapshot timing drains the same private stream and never
publishes its contents. Named Prompt assertions remain intact after exact inverse
of the local diagnostic delta; raw production source still asserts no preview.

The original branch-only proposal below was off build454. Runtime intent and
cause evidence stay the same, but only this forward-composed revision is suitable
for stacking after #628. Native/device/pixel acceptance remains UNRUN.

# Add generation: a terminal deadline, not a model-speed claim

## Device result

Build454 trifle Link import was still Cooking up your card in screenshots at20:04
and20:05, with no result or error. The supplied source is:
https://lancewood.co.za/recipes/nespresso-hazelnut-coffee-and-chocolate-trifle-recipe/
The pixels were inspected. They do not contain the start timestamp or stage logs,
so they cannot identify which await was pending or prove an infinite model loop.

## Proven hang mechanism and450->454comparison

DraftGenerationAttempt and GenerationCancellation are byte-identical450->454.
The Add primary attempt has no wall-clock deadline. Its loading state clears in
post-await/defer cleanup only when the backend returns, or when the user discards/
leaves. A suspended backend can therefore leave the spinner up indefinitely.
Task cancellation alone is not a terminal UI outcome if an await ignores it.
Explore already uses a separate60-second deadline and revokes its attempt token.

Ordinary trifle URL stage map:
1. fetchHTML loads once. URLRequest has10s timeout. Net uses request20s/resource40s
   session limits and one pre-existing retry for networkConnectionLost after400ms.
   This is not an unlimited retry loop. HTTP503 is thrown before recipe parsing.
2. JSONLD extraction is synchronous. Current fetched Recipe schema has title/
   image/yield but no ingredient/instruction fields, so it cannot make a card.
   #608 title/description cleanup is synchronous on a usable JSON-LD card. It adds
   no async wait and is not the explanation for this trifle fallback spinner.
3. htmlToText and source verification run before model generation. There is no OCR
   on this plain URL path. No Vision or photo-label await can explain it.
4. generate awaits a FoundationModels stream, then collect. Cancellation is
   checked when the stream yields/await returns, but no wall-clock owner aborts it.
5. Genuine quality/fidelity gaps can cause ONE optional repair generation. It may
   reuse the recipe's existing model session. There is no while/retry recursion.
   That second generation also lacks an Add deadline. Its failure may retain the
   first card, but an await that never returns never reaches that fallback.
6. Final normalization/fidelity checks return a card or throw. Add admits only the
   current token, asks the dish question if needed, or assigns the review draft.

#607/build452 changes work size and whether source extraction is reachable:
- The old3500-character page head becomes full-page recognition.
- The model page is the verified contract's text prefix6000, or an unverified
  page head prefix6000, rather than3500.
- Generated schema permits60ingredient rows/40steps instead of30/20.
- Repair admission still allows one pass; source-fidelity gaps join its conditions.
These can increase runtime and expose the pre-existing no-deadline defect. The
screenshots do not prove a particular one caused the stuck await. Do not claim a
new unbounded repair loop or that source fidelity itself timed out.

The current read-only fetch returned200in0.817s from another network/HTTP client;
its HTML is871292bytes, below the app1.5MBbody bound. Python reproduction of the
repo text conversion yields9190characters, actual Ingredients around2491and
Method around3124. The native full-page extraction fixture is separately covered
by existing source tests. An HTTP200probe is not live iPhone model acceptance.

## Minimal repair

DraftGenerationAttempt.start accepts an optional deadline, defaultnil for its
other callers. Add passes60seconds, matching Explore's product bound. The timer
runs independently of the work task, verifies the same token and an active
primary, then invalidates BEFORE invoking the timeout callback. Invalidation
revokes publication, cancels work and spread children, and releases the owner.
It does not await the cancelled backend and is not a structured task-group race
that would still wait for an uncooperative child at scope exit.

Add's timeout callback clears loading/live preview through invalidateGeneration
and presents a clear error through its EXISTING ErrorRetryCard/Try again action.
DraftStore.pending is not deleted. A pre-existing dish question does not hide
the timeout error; its answer stays available for explicit retry. Nothing is
saved on this path. A late card,
preview, error or old completion cannot publish or stop the explicit retry.
Normal completion cancels the deadline while preserving existing spread-child
admission. Discard/disappear/new attempts cancel any obsolete deadline.

No model/network timeout is raised. No new retry, model parameter, prompt, source
import recognizer, quality/save gate, CI budget or allowance changes. No workflows
or existing native tests changed. This branch is separate off cce94c10, not the
Explore/Prompt repair or four-screen stack.

The deadline bounds primary Add work, including its optional automatic repair.
Explicit Repair these gaps uses DraftRepairAttempt and is not changed here. A
cancelled backend may continue consuming resources until it honors cancellation;
the new guarantee is revoked UI/persistence admission, not forced model death.
Timers also need foreground execution/main-actor scheduling; this is not a promise
to run during app suspension or a synchronously blocked UI actor.

## Exact owner paste: test4

Recovered message phonemsg-01M7TFY0VP95JFHB8HB5A8Z1TQ is3779characters, below6000.
Its SHA256 is d127a6184d6fb9cd232e86f6798bd7362723f089b7a6b309611d0584db719490.
It equals the existing native MultiPartPastedRecipeContracts paste fixture except
for that fixture's final newline. Recognizer trimming removes this difference.

The actual native test testFullPasteVerifiesAsOneWholeRecipe passed in retained
622repair evidence0.017s, NBSP variant0.006s. Provider artifact metadata binds that
run to e858daecde255e0f4b809d8d0a6a949e68ea3d6e. Recognizer, IngredientParser in
JSONLD.swift, RecipePrompt, CuisineGlossary, GeneratedStepQuality, Durations,
GeneratedRecipeConsistency, Models and native fixture are byte-identical to454.
https://github.com/melusi-k/ate-ios/actions/runs/44568752959/artifacts/14555204122

That real boundary verifies28ingredient rows, retained component/unmeasured rows,
30/55cocoa quantities,190C and the1-2hour assembly instruction, and extraction is
verified. The earlier whole native suite had unrelated failures; this is a named
boundary pass, not a claim the suite was green or a fresh local native run.

Thus the owner paste should enter source-bound model extraction, not clarity
refusal. RecipePrompt.social carries the whole under6000paste; no clipping needed.
Its later model/repair work can also exceed60seconds on454. The same Add repair
covers that dead end. No new paste parser defect or fix is established here.

## Follow-up device Paste evidence and local stage history

The owner's20:09/20:10screenshots confirm the same trifle pasted into Add's Prompt
is also stuck loading, not a mere copy of the text in iMessage. These pixels were
inspected. This reproduction has no URL fetch; together with the matching fast
native recognizer pass, it points more strongly to model/repair processing than
networking. It still does not identify first-token versus collect versus repair.

Routing full recipe pastes through source-bound extraction is deliberate and
correct. The Prompt tab handles both short creative ideas and existing recipe
text; provided quantities/method must not become a creative substitution. The
Generate-from-your-idea help is incomplete about this dual behavior, but this
packet does not change tab copy, reinterpret pasted recipes, or relax source gates.

New typed local diagnostic stages use the existing DiagnosticHistory categories
and timestamps: attempt start, page fetch start/return, prompt built, model start,
first model snapshot, model return, automatic repair start/return, attempt return/
error, and timeout. The first-snapshot event is written once per generation, not
per token. It means the first response snapshot, not guaranteed first text token.
Model stages repeat for the optional repair, bracketed by its start/return events.
A missing return after one of these stages narrows the next investigation.

A separate recordLocal method uses the existing200entry rolling local store and
export format, with NO call to TelemetryClient. Existing record behavior is
untouched. No prompts, recipe text, URLs, ingredient counts, account data, raw
errors, payload fields or request identifiers are added. Timestamp gaps give stage
timing without turning user content into diagnostics. Independent attempts can
interleave; a final stage is evidence, not proof of a particular deadlock. Abrupt
termination, suspension or clock changes can limit the record. No wait/retry/model
choice is controlled by diagnostics. New stage labels/rendering remain unverified
on a device.

## Tests and remaining qualification

Four new deadline native tests use the real DraftGenerationAttempt with deliberately
uncooperative checked-continuation work, actual DraftStore recovery input, and
late delivery during explicit retry. They cover release-before-return, refusal
of late writes/cleanup, normal completion preserving spread admission, discard
cancelling the timer and the production60second constant. All four are required
by name in the existing full-unit union. Two more native tests cover stage Codable
labels, the unchanged three-field event schema, persistence/export/clear and the
rolling bound. All six are required. No production timeout is made configurable.

Six Python source/inverse/mutation checks supplement them, including local-only
stage routing and a single first-snapshot write. A checksum-pinned exact inverse
reconstructs all four runtime parents; every unrelated byte remains pinned.
Existing deadline-free callers keep their old behavior by default.

Native build/unit/UI, timeout-message pixels and real device/model acceptance of
trifle Link/Paste remain UNRUN for this branch. Python is not native proof. A later
60second error establishes total attempt duration, not which stage consumed it.
Stage timing or on-device model diagnostics would be needed for that attribution.
