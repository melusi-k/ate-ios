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

## Results log

| Date | Build SHA | By | F1-F11 scores | Notes |
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
- **Dietary cues from long page text.** Dietary detection currently trusts only the user's own
  words, social captions and photo hints/OCR; long recipe pages mention diets descriptively
  ("make it vegan by...") and must not become hard constraints. Loosen only with fixture evidence.
