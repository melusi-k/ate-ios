# All UI Add Prompt source fixtures

Base: 428a25f8760ca19145cc26d252f56ca1987f54ef, product branch after verified-heading correction.
Focused descendant adaptation of the earlier unintegrated aeeac631 packet. Do not stack both fixture packets. No hosted branch, runtime, backend, workflow,
quarantine, requirement ID or qa_results mutation.

## Evidence and classification

The supplied account job log for this head records:
- AteUITests.swift:119: test06_CookMode,
  testCookModeCompletionRecordsCookingDay, testCookModeExitDoesNotRecordCookingDay.
- CoverageUITests.swift:119: testBottomBarsDoNotOverlapRecipeDetail.
- CookIngredientsUITests.swift:51: testCookIngredientSheetNormalTextAccessibilityAndImperial,
  testCookIngredientSheetScalesChecksAndPersists, testCookTimerCardNormalText.
- KeyFlowsQATests.swift:72: testQA7_SyncAccount.

Each location is a Review your card existence wait reached through a name-only
Prompt setup. AddPromptSourceImport now rejects extraction.none before any
backend. That source-level incompatibility is confirmed, not an About, Cook,
ingredient scaling or sync-state assertion failure. The KeyFlows trace shows
launch, Add button discovery and the line72 review failure at70.74s, case failed
72.133s. The printed account job excerpt omits native trace lines41-104, including
the Generate-to-error interval. The actual refusal text is not visible in the
supplied evidence. Do not claim it was photographed or observed there.

KeyFlows testQA7 first calls addPrompt("Synced stew"), then edit, sign-in,
server sync and second-device pull. Its failing line72 belongs to review(), not
any of the sync assertions. This run did not exercise those later checks.
The #76 quarantine remains unchanged and NOT PASSED. A source fixture repair
cannot establish whether its older independent sync problem is fixed.

## Complete setup inventory

Audited every UI promptEditor reference, Prompt selection/openAdd call,
generateButton tap, text-view input, and direct backend request in AteUITests.
17 input sites across11 existing files need source to reach their intended UI:

| File | Input sites | Preserved purpose |
| --- | ---: | --- |
| AccessibilityAuditUITests | 1 | Saved recipe accessibility setup |
| AteUITests | 6 | Common add, provenance, named rows, expiry/account switch, Search describe-save |
| CookIngredientsUITests | 1 | Ingredient sheet/scaling/timer setup |
| CookReflectionUITests | 1 | Finish/reflection setup |
| CookSharedStepUITests | 1 | External current-step update setup |
| CoverageUITests | 1 | Shared startPrompt, including outage/retry and About/Timer consumers |
| DraftQualityRepairUITests | 1 | Explicit missing-bread repair wiring |
| ExploreUITests | 1 | Existing saved recipe for retention/search tests |
| InsightsAcceptanceUITests | 1 | Cook completion for insights |
| InsightsPresentationUITests | 1 | Cook completion for insights presentation |
| KeyFlowsQATests | 2 | Shared addPrompt and direct edit setup, including sync/timers |

Intentionally unchanged: empty Link validation, private-mode blocked Generate,
image/OCR/food-photo imports, social-caption-to-Prompt prefill with no Generate,
first-recipe mode selection/cancel, widget Prompt deep-link selection, and all
unit/model backend requests. The latter do not pass through the Add UI boundary.
No new-source fixture is substituted into any intentional no-source refusal test.

## What changes

One shared test-only PromptRecipeFixture supplies measured Ingredients/Method
for the existing deterministic salmon mock. Caller titles remain first, as
navigation labels. Existing MockBackend is unchanged and still truncates its
seed-derived title to80chars, so full title may now contain source text. These
mock UI cases do not qualify model generation or fidelity to a differently named
dish. All original title/content assertions remain to catch regressions natively.

DraftQualityRepair gets its own bread-salad source including measured bread,
not an unrelated salmon recipe. The special backend still returns the original
incomplete card, so missing bread must block Save until the original explicit
repair action succeeds. No confirm-to-save workaround.

Search describe-save still asserts the original zzz prefill first, then appends
the measured source before its original single Generate tap. The preserved
search query, result-match and Back assertions are unchanged. This is the only
additional UI action: focusing the editor to add the required source.

The exact fixture file compiles into both UI and unit test targets, never the
application. project.yml adds only that file to AteTests sources. Two new native
unit tests use the real SourceRecipeFidelity recognizer and AddPromptSourceImport
boundary on these exact fixtures, require verified measured contracts, require
bread, and prove the bare Synced stew still cannot invoke the backend. They are
UNRUN locally, not claimed passing.

All existing XCTest assertions, wait budgets, launch arguments, Generate/Save
and repair actions remain byte-carried. No retry, timeout increase, fallback,
product guard weakening or mock change. An exact checksum-pinned inverse
reconstructs all11 modified original UI files and project.yml to428a25f8 bytes.
Historical whole-file pins use it before their older inverse layers; none of the
old expected hashes or inverse fixtures changed. Missing/duplicate/unrelated
source mutants are rejected.

## Checks and remaining qualification

Current adaptation checks are recorded in the packet README and logs; original fixture packet had 376 Python checks.
Four new Python tests cover exact inverses/mutants, preservation of every
assertion/wait/launch/Generate/Save line, the17-site inventory, Search ordering,
and exact fixture test-only target membership/native test wiring.

Native Swift compile, new unit tests, UI review, About/Timer/export/ingredient/
sync results and pixels UNRUN. Python is not native qualification. Re-run the
original required suites against the integrated exact head with unchanged gates;
include PromptRecipeFixtureTests in unit execution. Do not clear current red or
call #76 a pass based on this packet. Any new qa_results row still needs its own
source-grounded exact-head consent; no row was written here.

## Packet contents

Patch, incremental git bundle, this README, Python log, source-site audit and
head/tree/diff/bundle hashes. Repository change is22 files:11 original UI source
files, shared UI fixture, new native unit test, project.yml, one exact inverse
module+JSON, four historical normalizer/check entrypoints, new Python test, and
this document. No Journal fresh-query or other pending packet is mixed in.

## Current #631 failure grounding

The supplied d2438e15 Dogfood native log records QA3 typing Lemon chicken traybake then Generate, followed by missing Review your card at KeyFlowsQATests:72. QA4, QA5 and QA8 use that same review helper after addPrompt with Pea risotto, Shareable soup and Timer test salmon. These bare-name inputs are now intentionally refused before any backend. They are stale setup fixtures, not evidence that a streaming partial card blocked review. This adaptation supplies actual measured source to those original Generate actions.

All UI files were scanned again, including promptEditor, typeText, Prompt entry and shared generation helpers. The inventory above is unchanged: 17 generation input sites in 11 UI files. Widget/mode selection, no-Generate caption prefill, query-prefill assertions and private-mode refusal are intentionally preserved. No deadline, wait, launch argument, assertion, Save action or retry count changed.

Group28 is separate and unchanged. Its real native log passes A-Z, Today and Under 30 min, selects None, swipes the Apple crumble StaticText, then fails waiting for Favourite. It uses saved fixtures without Add. The log alone does not establish the failed gesture's visual/container cause. No Group28 runtime or test change is included here.
