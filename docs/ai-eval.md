# On-device generation eval

ate's recipe and reflection generation runs on Apple Foundation Models on-device. CI uses the mock
backend, so unit tests prove prompt *construction* (snapshots, exactly-once rules, size guards,
context detection) but can never prove generated-output *quality*. A prompt change is only an
improvement when this golden set says so.

## How to run

1. Install the build under test on an Apple Intelligence device (iOS 26+).
2. Run each fixture through Add recipe (or "Reflect on your day" for F11) and record the result.
3. Score each fixture: automated `RecipeQuality.issues` count (target 0) plus a human 1-5 rating
   ("would you cook from this card?"). Note confidence calibration and whether the glossary tool
   fired for regional dishes.
4. Log the run in the table below (build SHA, scores, notes). A prompt change merges as an
   improvement only with equal-or-better totals; a regression means revert or iterate.

## Fixtures

| # | Mode | Input | Pass looks like |
|---|------|-------|-----------------|
| F1 | social | Full recipe caption (`RecipePromptTests.recipeCaption`: chakalaka with ingredients + method) | Title Chakalaka, ingredients copied verbatim, promo words never become ingredients |
| F2 | social | Delivery advert naming no dish (`midrandAd` fixture) | Rejected as ungrounded promo; no invented recipe |
| F3 | social | Menu/advert naming dishes, no recipe (`mogoduMenu` fixture) | Best-effort traditional recipe for the NAMED dish; note says so; R85/WhatsApp never become ingredients |
| F4 | photo | Clear single-dish photo (e.g. a plate of mogodu) | Dish identified or the user is asked; structural components (wrapper, filling) are measured ingredients |
| F5 | photo | Ambiguous drink (orange liquid in a glass) | No invented spirit/liqueur; Unknown dish under 0.2 confidence or the user is asked |
| F6 | screenshot | Recipe screenshot OCR | Original quantities and order preserved |
| F7 | prompt | "vegan chakalaka for 6" | Every ingredient vegan; servings 6 |
| F8 | prompt | "sticky oven ribs" | Oven steps carry °C; timeMinutes = step sum + prep; no step says just "cook the ribs" |
| F9 | rewrite | Existing card + "make it vegan" | Only the asked change; id/createdAt/favorite preserved |
| F10 | retry | An input known to fail the quality bar once (thin card) | The retry repairs the listed gaps instead of re-rolling; second card passes `shortfall` with fewer gaps |
| F11 | journal reflection | "Reflect on your day" on a day with health data | Generated prompt is under 25 words and ends with a question mark; otherwise templates show |
| F12 | prompt, then screenshot-regression review | "Mutton bunny chow for 6"; compare with Melusi's 11 Nov 2026 screenshot (1.5 kg mutton, 2 onions, 3 cloves garlic, 2 tsp curry powder, 500 ml stock; salted-water simmer 150 min, fry 8 min, sauce simmer 30 min; total 198) | Curry served inside measured hollowed bread portions, not kota or curry with pap; every used staple listed; coherent cooking order with pre-boil liquid handling if used; total equals step sum plus explicit Prep: N min (198 may be valid as 188 + 10 prep); varied spice blends allowed, no forced browning. Human reviewer checks taste, portions and food safety. |

## Results log

| Date | Build SHA | By | F1-F12 scores | Notes |
|------|-----------|----|---------------|-------|
| pending | baseline on main before the generation-pipeline PR | | | First run establishes the baseline |

## Eval-gated proposals (do not ship without a passing before/after run)

- **Timing facts to glossary.** Move dish-specific timing facts (tripe 2 to 3 h, steamed bread over
  1 h, samp and beans 2 to 3 h) out of shared rule 6 into `CuisineGlossary`, which already holds
  them. Only after confirming `lookupRegionalDish` actually fires on those paths (name match or
  tool call) and generated times stay realistic without the always-on hint.
- **Prose examples.** Drop Example 1 and Example 2 from the shared instructions, keeping the
  structured one-shot (`exampleMogodu`), behind the `-qaIncludeSchema`-style A/B flag with an eval
  comparison - not deletion on principle.
- **Dietary cues from long page text.** Stated-identity/requirement cues from long pages now ship
  (a title like "Vegan Mac and Cheese", or "This recipe is gluten-free"); descriptive adaptations
  ("make it vegan by...") and negations never become hard constraints, and an explicit user
  instruction overrides a conflicting scraped identity. Loosening beyond stated identity needs
  fixture evidence.

## F12 regression provenance and status

- Screenshot was inspected, not executed as a model eval. The deterministic regression is
  `GeneratedRecipeConsistencyTests.screenshot`. It is a failing-output fixture, not the desired
  answer, and no private image is bundled. Its cooked timings sum to 188 minutes; an unexplained
  extra 10 minutes is a transparency gap, not proof that 198 is wrong.
- The old structured Mogodu example reproduced the screenshot's ingredients and 150/8/30
  sequence with missing staples. The revised example lists its staples, explains draining,
  removes the unlisted pap serving claim and states Prep: 12 min for its 200-minute total.
- Before/after device F12 plus F1-F11 regression review: NOT RUN. Prompt construction and
  deterministic gap checks do not prove better live model output. Preserve source quantities
  and order for extraction; do not silently add a guessed source ingredient to pass a check.

## Step-completeness review (12 November follow-up)

F12 and F8 before/after device runs must now include ingredient-to-step tracing: mark where each
listed ingredient is prepared and used, and check every named step food against the list.
Cooking actions need a time/range, heat guidance and a doneness cue, with any drain/retain
transition explained. Check serving/assembly and rest only when the dish needs them. More
numbered steps alone earns no credit; a cold salad should not gain a cooking/resting step.
Do not invent missing source details during extraction. Record an unresolved source gap instead.

`GeneratedStepQuality` supplies bounded repair hints for known food nouns and explicit thermal
actions. It handles common plurals and explicit collective usage, but is NOT a general ingredient
parser, dependency planner, food-safety verifier or proof every ingredient/heat level is correct.
Unknown names, aliases, pronouns, and complex sequencing require model/human review.
The same one-repair limit and remaining-quality draft review stay in place.

The structured Mogodu example now shows prep and serving explicitly without changing its
188-minute timed cooking sum plus 12-minute prep. Deterministic tests cover missing ingredients
in both directions, absent time/cue, oven-setting versus checked internal temperature, collective
usage, cold dishes, source exclusions and the screenshot regression. Native tests and actual
F1-F12 before/after device outputs: NOT RUN for this step-quality slice.

Step-quality review revision: ingredient head aliases accept ribs/wings/stock without requiring
full compound names, and the full instruction is scanned for later heat actions (including
cover-and-bake). Existing native good-ribs acceptance with time + oven temperature stays accepted;
explicit doneness is still requested by the prompt. A bare oven setting without time still fails.
The validator cannot disambiguate a separate meat use from a stock descriptor; human review remains
required. Existing prompt phrase "at least 4 real ingredients" is preserved without changing tests.
