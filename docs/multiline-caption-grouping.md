# Build456 multiline-caption grouping

20 November 2026. Branch-only on exact PR639/build456 source cef39066d83b49718a6d72cca5897617dee1e93a. Native final-head UNRUN.

## Device evidence and source cause

Owner screenshots from16:49–16:51 show the garlic-butter-chicken caption imported with exact facts and unspecified servings, but incomplete Ingredients grouping. With the pasted sample framing line, only chicken and butter are Ingredients; framing, garlic, paprika and salt/pepper appear in Steps. Without framing, chicken/butter/garlic are Ingredients; paprika and salt/pepper remain Steps. All five screenshots supplied by Main were visually inspected. The changed input means these are two differing classification results, not proof of nondeterminism for identical input bytes.

Source: the existing inline converter requires a you-need comma list, and structured verification requires an Ingredients heading. This caption has neither, so OnDeviceBackend.importSource reaches model source-line classification. SourceDraftImport.card trusts the selected ingredient indices and puts every other unassigned row into Steps. That mapping was introduced by c1267c757. It preserves text but confuses unclassified source with cooking directions. There is no two-row cap in this code. The exact model indices were not logged, so the screenshots establish the result, not the internal classifier response. The correct title and partial list are consistent with incomplete model selection, not the fallback grouping alone.

Original sample provenance: conversation message phonemsg-01M7WPS7A0KFJP6DYXQEGV84GJ; first screenshot message phonemsg-01M7WPZR8D7D73Z9M823CMM7TH. Second run supplied by Main as phonemsg-01M7WQ2MR1NEFFAFZKK0DW3G50. Exact caption is embedded in MultilineCaptionImportTests, including the framing line, blank line, emoji and entire Method text.

## Narrow deterministic grouping

MultilineCaptionImport recognizes a short title, an explicit line-delimited list beginning with two measured source rows, then exactly one anchored Method:/Directions:/Instructions: boundary and written cooking action. Later unmeasured list rows remain whole and unspecified. It does not infer sentence boundaries, ingredients, quantities, units, servings, timers or total time. Conservative punctuation/action checks decline ambiguous shapes to the unchanged path rather than partially grouping a list.

The optional explicit sample-caption/recipe paste-as-is framing line is kept in raw source but not rendered as a cooking step. Unknown preambles are not silently stripped. Each ingredient row is retained as its exact full source string, quantity0/unit blank, matching the existing source-classification representation. Thus 4 chicken thighs, 2 tbsp butter, 3 cloves garlic comma minced, 1 tsp paprika and salt and pepper remain exactly five displayed ingredient rows. No second structured amount is invented alongside an amount already embedded in the row. Method text, including its written times, stays one exact step; per-step timer and total-time fields are not inferred. Raw source survives Codable round-trip.

The route runs before model allocation in existing source import. Recognized captions therefore cannot change grouping with model availability or partial classifier selection. This is not a general recipe parser or a change to creative Explore/Rerun. Existing verified inline/headered routes, common food-content gate, cancellation checks and60s budget remain unchanged.

## Regression evidence and delivery boundary

Three new required native methods cover:
- Exact framed and unframed paste, all five ordered rows, only written Method, exact title/raw source, unspecified fields and Codable round-trip.
- Both paste forms crossed with2-row and3-row truncated classifier stubs and available/unavailable models. Exact output is required and classifier/model call counts must be zero.
- Missing/duplicate method boundaries, prose inside the list, missing measured anchor, bare dish name and non-food text do not enter this deterministic route.

Existing native tests are unchanged. The required-name ledger adds these three methods,147→156, never removes a check. Exact additive backend inverse composes before frozen source guards; historical hashes are unchanged. Static guards cover route order, fact-preserving representation, inverse/mutants and ledger coverage. Python is not Swift/native evidence.

Reviewer must compile and run the new native methods on the exact final head, then the existing source/streaming/full-unit contracts. Repeat the real Add paste journey with and without framing and visually inspect that all five rows are Ingredients, only Method is Steps, framing is raw-source-only and no fact was filled in. Retain screenshots immediately. No final-head screenshots exist in this packet, and no native qualification or fixed-device claim is made. No remote publication, dispatch/rerun, merge, build cut, timeout change, model retry or paused UI work is included.


## Saved-row servings icon addendum

Owner's follow-up screenshot message phonemsg-01M7WQ713HJH7N6WHXQZARY1SX was visually inspected: saved row has a people icon with no text. Components.swift already supplies Unspecified for zero servings, so missing model value is not the source explanation. RecipeRowMetadataItem uses an unstyled native Label inside button rows, making inherited/adaptive icon-only label presentation the source-supported suspect. No final-head native reproduction pins that style as the actual device cause yet.

Small presentation correction: explicitly use titleAndIcon style for shared metadata Labels. Keep existing Unspecified/known numeric text, no serving value invented. Two additional required native methods compare normal versus inherited iconOnly metadata width, require space beyond the bare icon, and retain rendered saved-caption row screenshots at326/393pt with normal text size. Native pixels must be inspected before calling the device symptom fixed. Existing row/layout tests remain unchanged. This adds a second exact source inverse for the one-line style change; no historical hash is replaced.


## Saved detail: source gaps, Repair eligibility and Nutrition

Owner detail screenshots at16:54 were inspected. RecipeQuality's main-dish count checks structured positive quantity for all sources, incorrectly reporting zero measured ingredients for source text stored losslessly in names. The count demand now excludes SourceDraft.applies imports; generated/non-source count and structural checks remain intact. No quantity parsing or conversion is introduced.

RecipeDetailView offered Repair for any issues while RecipeDraftRepair accepted only generated cards with shortfall. Both now use the same canRepair predicate for eligibility, and the backend instruction still fails closed for imported cards. The button is not offered for a card the backend cannot repair. Genuine generated gaps remain repairable with the existing constraints.

RecipeNutritionCalculator called every nonpositive serving count invalid. It now distinguishes0 on an editable draft as servings needed; negative/non-draft invalid states retain invalid wording. RecipeNutritionView asks for a serving count without guessing one and avoids presenting the serving-state marker as an ingredient problem. Calculation remains unavailable, with no totals/contributions or default serving count. Supplying servings alone still cannot invent missing structured ingredient quantities or verified nutrients.

Three additional required exact-caption native cases cover source-quality/repair versus generated behavior, unspecified versus invalid Nutrition and native Nutrition message pixels. Source inverses prove exact limited runtime changes; no historical hash is replaced. Final-head native compile, behavior and screenshots remain UNRUN.


## Refusal wording only

Following owner-approved wording direction relayed by Main, the Add import refusal now describes text that does not look like a recipe source, rather than assuming every failed paste is a dish name or idea. It still directs the user to recipe source, link/screenshot/manual entry and explicitly says Nothing was generated. Ingredient-only or written-method source wording does not imply both must be supplied.

Only the missingSourceMessage constant changes. The refusal condition, routing, timing and no-generation behavior are unchanged, proven by an exact one-line inverse. A required native test covers both Beef stroganoff and the exact quarterly-report non-food text, requiring refusal and zero model-availability probes/model calls. No accepted source boundary is widened.


The later build456 navigation check established that Library Explore is offline saved-recipe rediscovery, not creative generation. The refusal therefore no longer promises Explore as a universal destination. Exact source routes creative suggestions conditionally through Journal → Insights & Cooking History → Recipe & cooking insights → Explore new recipes, when an eligible recipe insight exists. There is no pilot on/off flag for this view, and no always-visible entry if those candidates are absent. Actual AI availability/private-mode/device state was not inspected. No navigation or eligibility change is part of this packet.
