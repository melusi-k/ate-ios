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
