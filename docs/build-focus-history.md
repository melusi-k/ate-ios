# Build-focus history requirement and checkout repair

The first hosted Journal run on source d663b966 failed before compilation: XcodeGen's preGen command called gen-build-notes.py, whose strict anchor ancestry check could not find f084a9fe in a depth-one checkout. Homebrew installed successfully; native build and all Journal tests were skipped. This is a source/checkout integration defect, not a simulator test failure. The failed run remains failed.

Repair: explicit `fetch-depth: 0` on all 14 shallow XcodeGen caller jobs across 12 workflow files. The caller inventory covers 24 XcodeGen jobs, including existing full-history Build IPA release/UI, Dogfood and retained branch workflows. Their existing full-history settings are unchanged. Compile, Journal, nightly, preproduction, CodeQL Swift and optional/manual callers now retain history too. Workflow names, job IDs, selectors, budgets, triggers, gate predicates and source refs do not change. More history transfer is a cost of preserving ancestry validation, not a performance claim.

The build-focus helper is unchanged: no unverifiable-ancestry fallback, guessed focus, implicit network fetch, or weakened blob check. Real depth-one fixtures reproduce rejection with no focus emitted, then prove unshallowing restores the same strict path. A caller-inventory test rejects a future shallow XcodeGen job.

Local builds also invoke the same preGen command through scripts/prepare-local-build.sh. Use a normal full-history checkout. If working from a shallow clone, fetch its history (`git fetch --unshallow`) before building. No runtime self-fetch is added to the notes generator. Missing or unverifiable source ancestry still stops the build rather than claiming a feature.

Evidence:
- https://github.com/melusi-k/ate-ios/actions/runs/42658425792
- https://github.com/melusi-k/ate-ios/commit/d663b966457a632b4a43460f14fe2a253d2adb99/checks/129303228594/logs/6

Offline tests do not establish a hosted repaired build, native About rendering, or device acceptance. Ordinary CI on the repair's final head is still required. No manual dispatch or retry is part of this repair.

## Reflection deletion review on the dormant Journal branch

Source a6e45b5a2a57942b76a6fb54512eb5b29cdc2d36 changes the guarded JournalViews source:
confirmed reflection deletion now refreshes retained history only after a successful save,
and failed deletion keeps detail visible with an error. The existing Journal navigation
and cooking-reflection focus remains accurate; its title and summary are unchanged.
The focus record is re-anchored to that source with exact current blobs after this review.
No dormant unified-store activation, native test pass or device acceptance is claimed.
The strict ancestry/blob validator and all qualification requirements remain unchanged.

This split re-anchors the reviewed focus to the destination runtime commit above,
not to the frozen aggregate branch. Activation remains OFF.

## Bundle B exact source fold

Reviewed runtime 539f721d19f8547787335433c30384cbae4ece7c folds #524bb7812e4 and #496c4cfa1b1 as merge commits onto #4974b376243. Only compile-check artifact-path conflicts needed manual union; both Shopping and Explore paths are retained. Strict source ancestry/blob validation is unchanged. No native, pixel or device acceptance. SharedInbox pushImage and its failing FJ-union regression are absent on all three source heads, so no speculative path patch was injected. Nutrition passed on retained #497/#522 artifacts; that is not a pass on this new combined head.
## Shared Cook state and bottom actions on #518

Reviewed source d488db36ee4095c05e807d60fa9f5a456d491188 changes the guarded
AteApp.swift: the pushed Resume and timer siblings now form one VStack. The
unchanged renderer rejects that source because its old evidence blob no longer
matches. CookModeView reads/writes the matching shared session step, no longer
restores an older parallel timer step over that session, and reserves measured
bottom chrome. RecipeDetailView reserves measured chrome for its Cook action.

The focus now names those source changes. Its anchor is that exact runtime
commit, its evidence covers all three changed app paths, and unchanged
JournalViews evidence remains to support the retained Journal wording. Strict
source ancestry and exact blob validation remain unchanged. No runtime,
workflow, selector, timeout, assertion or activation switch is changed here.

The original source still fails the guard. The docs-only child passes it and
can render build notes. Neither result is a native build/test pass or proof of
spacing, reachability, physical widget behavior or native About rendering.
Portrait/landscape Resume+timer pixels and exact-head native checks remain
required. Unified Food Journal activation stays OFF.

Comparison: #517 source 7ee50cada9f61832385dfa2cc335dfbebc2f8658 passes the
existing guard because neither of its two listed evidence paths changed. That
is not generation-quality qualification, and its old Journal focus does not
describe that PR's new generation paths. No rerun or record update on #517 is
part of this #518 repair.

## Cook and reflection edit union (#482 on #518)

Reviewed hosted runtime 144b076bb313ac42c98270d08543c8d3632cf195 preserves all four Cook/shared-step evidence paths and adds JournalSuggestionService for committed reflection edits. JournalViews has its freshly reviewed edit blob. This record unions the focus, never replaces Cook work with reflection-only claims. Native save-failure, Resume/timer spacing, widget, physical-device and pixel evidence remain pending. Strict ancestry/blob validation is unchanged; Food Journal remains OFF.

## Confirmed deletion and reflection retry union (#527)

Reviewed hosted runtime d88f6cad310226aa8f32ba69d45009a428d2b50d preserves all four Cook/shared-step evidence paths. JournalViews and JournalSuggestionService have freshly reviewed combined edit/delete blobs. Failed edits keep the exact raw draft; successful retry uses the existing committed trim contract. Stable-identity deletion verifies committed absence before detail retires and parent history reloads. Reminder verification and bounded cleanup are present, but this record guards only its listed paths. Native checks and post-tap/history/Resume/timer pixels must qualify the exact final union. Physical-device, widget and Files-picker behavior remain pending. No activation or release approval is implied; Food Journal remains OFF.

## Journal action uniqueness metadata repair (#527)

Reviewed source e68a017f265b20a0e2ace03d3c3ba3a3ca97aca1 contains the action
uniqueness correction: Journal detail's full-size VStack owns one alert, editor
Save/Cancel use dedicated IDs, and delete confirmation queries target unique alert
actions. The previous focus anchor retained an older JournalViews blob, so hosted
run 43366560488 stopped in metadata before compilation. No native tests ran there.

The refreshed record names Journal action uniqueness and retains the included Cook,
reflection retry and committed deletion work. Exact current blobs for all five
existing runtime evidence paths are anchored to the corrected source. The renderer,
strict ancestry/blob checks, runtime, tests, workflow and timeout budgets are
unchanged. A successful metadata render is not a native pass or pixel acceptance.
## Confirmed delete evidence refresh on #526

Reviewed runtime2534358fdbd207813504d33934dd0eb826cc7676 changes JournalViews
for stable-identity deletion, committed-reader absence verification and retained
failed-delete detail/error/retry. The old focus record still named its prior
JournalViews blob. XcodeGen correctly rejected it before any native execution.
Both Journal and Dogfood failures remain recorded as source/metadata integration
failures, not runner stalls or product assertion passes. This docs-only refresh
anchors the exact hosted runtime above and its unchanged AteApp plus current
JournalViews blobs. Strict ancestry and blob validation stay unchanged. Native
post-tap, delete error/retry/history pixels and normal qualification remain
pending. Food Journal activation is a separate reviewed composition change,
not implied by this source record.

## Bundle A exact-head source fold

Reviewed runtime 984b07a2385e278b35544eab3ed56aa910e72144 is the merge-commit union of #529 root32fe54fd, #518cfa8cd58, #525121ea356, #52299731deb and #5263a0b1afa. The later #518/#527 native Journal presenter and all exact uniqueness/error/history assertions are retained rather than reverting to #526's older projection. The record guards all previously listed evidence paths from both focus records, plus input/onboarding entry points. Metadata validation is not a native, pixel or device pass. Nutrition terminate remains unclassified pending fresh exact-head CI. OCR and all timeout budgets are unchanged. No activation change is made.
