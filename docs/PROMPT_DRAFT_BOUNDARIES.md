# Prompt draft boundaries, build 454

## Device evidence and scope

The 19 Nov 19:54-19:57 screenshots show Add recipe -> Prompt with Escargot with
cheese. The first partial card shows Mogodu with the exact ingredient quantities
of GenRecipe.exampleMogodu. A later partial title matches the input but has ribs,
bread and cheese. The final card is Unknown dish, cheese bread, South African,
confidence20%, with a Step5 oven-temperature warning. These pixels were inspected.
They are not model-session logs and do not establish whether the owner confirmed
a dish between screenshots, which generation/repair produced which snapshot,
or whether this was a stale request. No repaired device pixels are available.

## Findings

1. Initial input is not lost by request construction. Add sends prompt unchanged;
   RecipePrompt.prompt includes the whole input on454. On450 it included the first
   500characters, which also includes both this short input and the normal control
   A quick weeknight miso salmon for two. Neither short idea has Ingredients/Method
   structure. The backend chooses unbound creative generation, not source import.
   We have NOT run either input on a live model here and do not call initial-model
   drift a proven450->454 regression.

2. A distinct confirmed-name regression IS visible in source. Build450 made the
   dish-question answer part of the regeneration text. #607/build452 changes the
   unbound branch to original text plus dishHint. Backend consumption of dishHint
   was implemented for bound/social paths but not the unbound .prompt branch.
   Thus a normal confirmed salmon name can be dropped just like escargot. The UI
   records confirmedDish and may then skip its low-confidence question. This is a
   deterministic missing handoff; it is not proof the owner used that path here.

3. The partialSink published every raw snapshot before final checks, including
   the hidden repair pass. Example-echo rejection and repair selection happen only
   after generation completes. Therefore an unaccepted/rejected card could be on
   screen while loading even though it never becomes the final card. The first
   screenshot matches the embedded Mogodu example. The later ribs also resemble
   the shared ribs example, but exact causal model behavior cannot be recovered
   from screenshots alone. A changed partial card does not prove a saved-card
   mutation or accepted cross-dish repair. The raw-preview exposure predates450.

4. Unknown dish and20% are generated fields, not text replacement by normalize.
   Cuisine comes from generated dish.cuisine, not a forced UI constant. The shared
   South African persona, ZA-locality context and examples can bias output, but
   were already present on450. This repair neither changes that persona nor
   relabels the cheese bread as Escargot. Quality remains low-confidence Draft.

5. The oven warning is deterministic and old: any step containing oven/bake/roast
   without a temperature is flagged independently. Remove from oven is therefore
   incorrectly counted as heating, even with180C in the actual baking step. We
   remove only the removal/take-out phrase before checking the rest of THAT step.
   Actual bake/roast/preheat/return-to-oven still requires a temperature. We do not
   globally borrow a previous step's temperature or weaken the other quality gates.

6.42minutes is not a demonstrated error: screenshot timed steps are5+2+25minutes,
   plus the explicit Prep:10min note. That is42. Source normalization uses this
   exact rule. A native screenshot-shaped fixture pins the arithmetic and leaves
   Unknown dish/20% and needs-input intact. Untimed slicing/cooling realism remains
   model quality to assess, not proof the displayed arithmetic is wrong.

7. Disabled Save is expected at20% confidence or other real quality gaps. Seasoning
   advisory handling and explicit Repair these gaps are not changed by this patch.
   The445 family does not justify bypassing the80% rule or auto-confirming output.

## Repair

- RecipeIdeaPrompt.build is called only by the existing unbound .prompt branch.
  Ordinary unconfirmed ideas keep byte-identical assembled prompt text. An actual
  dishHint conditions a new generation and joins its attribution context. No
  output title/ingredients/confidence are rewritten to pretend it succeeded.
- Remove partialSink and the Add live partial-card binding. The model still drains
  its stream and checks cancellation. Both generation and repair remain private
  until backend selection, normalization, echo/fidelity checks and UI question/
  review admission complete. A simple checking-before-review message accompanies
  the existing progress indicator. This removes raw partial cards for all Add
  input tabs, since they shared the unsafe channel. It is not a model-speed fix.
- RecipeQuality.requiresOvenTemperature handles the bounded removal action false
  positive, while preserving checks on any heating clause remaining in the step.

No retry count, model options/schema/examples, deadline, gate, allowance, CI job or
budget changes. SourceRecipeFidelity and source-import facts remain unchanged.
This branch is independent off cce94c10, not stacked with Explore or screen work.

## Tests and qualification

Five new native tests are added to the required full-unit named union. They cover
actual deterministic prompt construction and source recognition for odd AND normal
ideas, the actual oven/quality path with negative heating cases, screenshot-shaped
42minute normalization and low confidence, and rejection of unrelated repairs.
They do not stub a live model and claim successful generation.

Four new Python source/inverse/mutation tests pin routing, the absence of a raw
snapshot publication channel, unchanged cancellation and final gates, step-local
oven checks and required native tests. The original historical backend/quality
hashes are unchanged; a new checksum-pinned exact inverse reconstructs the main
sources before their older inverse/hash assertions. Missing, changed or duplicated
fragments fail. The Add inverse also pins all unrelated view bytes.

Native compile, unit/UI runs, new loading-message layout and live-model output
for both prompts remain UNRUN. Python green is not Swift or device qualification.
Reviewer owns publication; owner device acceptance remains necessary.
