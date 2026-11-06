# QA acceptance: one device, normal text, useful user journeys

## Acceptance scope (owner decision, 2026-11-06)

This is the acceptance source of truth for current and future tests. Use **iPhone 18 Pro, iOS 27.0, default text size** (`UICTContentSizeCategoryL`). Fail device selection rather than silently substitute another model or OS. Use sample data and record the exact commit, device/OS, text size, selected tests and result.

Required feature acceptance is the ordinary happy path plus a small set of realistic failure checks. Keep checks that prevent lost data, false success or an unusable everyday action. Do not grow the merge gate into an exhaustive edge-case matrix.

| Feature | Happy-path acceptance | Small realistic-failure guard |
|---|---|---|
| Library and recipe import | Import a supported recipe link or readable recipe screenshot; review, save, find and reopen the recipe | Unreadable input or unavailable processing gives a clear result, not an invented recipe or false save |
| Generation and editing | Generate a sample recipe, edit its values, save and reopen the same recipe | Failed generation/save keeps a retry path and does not claim success |
| Food logging and goals | Log one sample meal, edit its portion without duplicating its identity, read daily/weekly totals; configure and clear goals | Invalid quantity shows an error; a failed save preserves recoverable input and unchanged saved records/totals |
| Journal | Create and read an entry, reopen/edit it, cancel or explicitly discard a draft | An unavailable store or failed save shows an honest error rather than an empty or successful state |
| Cook Mode and timers | Open a recipe, use Ingredients, start/pause/resume a timer, finish cooking and find its cooking-history entry | Exiting before Finish does not record completion; cooking does not silently log eaten food |
| Insights and Tracker | Open the hub, select a day and follow an insight action to its existing evidence without losing the destination | No-data/unavailable evidence remains honest; navigation must not silently return to the wrong screen |
| Shopping | Add a named item, find it and update its checked state | A failed write must not report the item as saved |
| Share and open shared | Open the share sheet once; open a valid sample shared recipe | An expired/invalid link has a clear unavailable result, not a different recipe |
| Settings and account sync | Reach everyday settings; when the sync fixture is qualified, save and recover the same account's change | Failed sync preserves local records; another account must not receive the previous account's private records |

These are acceptance contracts, not claims that every row currently has passing automated coverage. Keep existing quarantine status explicit and track missing coverage. Do not label a case passed because a workflow step continued after an error. A real failed journey remains a blocker unless the owner explicitly approves a scoped exception.

### Non-gating extended coverage

Large text, Dynamic Type changes, accessibility-size matrices and other device/OS classes belong to [#359](https://github.com/melusi-k/ate-ios/issues/359), outside required acceptance. They must never gate a feature merge or release under this scope. They may be run separately when deliberately requested, with their own results and cost, without being counted as normal-size acceptance. This does not cap runtime font scaling or remove accessibility behavior from the app. #359 originally recorded narrower nutrition findings; its tracking scope still needs updating to reflect this later all-feature decision, including the separate #332 question.

The workflow implementation is being aligned with this policy. Until that work is complete, a whole-class AccessibilityAudit selection in an older full-QA/IPA workflow is legacy extended coverage, not permission to treat it as a required gate. Report that mismatch instead of claiming the workflows already match this document. Unit correctness checks and the ordinary failure guards above remain in scope; this decision does not authorize deleting or weakening them.

The independent `.github/workflows/dogfood-qualification.yml` workflow runs on pull requests targeting `main`; `workflow_dispatch` remains available for explicit post-merge or release qualification, alongside the separate fast IPA build. Qualification requires the complete `AteTests` unit suite and seven stable critical flows (`testQA1`–`testQA6` and `testQA8`). The Settings/account-sync flow (`testQA7_SyncAccount`, issue #76) is still executed diagnostically, but is explicitly **QUARANTINED / NOT A QUALIFICATION PASS** until its Done-button selector is repaired; its failure cannot be counted as passing coverage. Qualification failures do not cancel or withdraw the separate fast `latest-build` IPA, which remains an engineering artifact and is never by itself a validated dogfood candidate.

All simulator-based CI checks now target the **iPhone 18 Pro simulator on iOS 27.0** using the `xcode-27` runner image; the selector fails rather than silently substituting another device. The app's minimum supported iOS version remains iOS 18. The broader `KeyFlowsQATests` suite, all UI-test shards, focused extended regressions and backend E2E remain available through `run_tests=true` / `[run tests]` and the deliberate pre-production workflow. A validated beta/TestFlight candidate must pass its required normal-size qualification and separately defined release checks before promotion. Extended font/device matrices are not release gates. The flow → pass/fail table goes into the job summary and release notes (`scripts/qa-summary.py`) where that suite is run. The UI-test launch flag enables beta diagnostics for automation; a production build must not show the Beta banner or Settings › Beta testing entry. Validate channel gating separately with `TierA` and `Production`/empty channel builds.

| # | Flow | Automated test | What it checks |
|---|---|---|---|
| 1 | Add recipe from URL | `testQA1_AddFromURL` | JSON-LD fixture → "Imported from page data" badge; Instagram caption fixture → card; hidden caption → friendly message + switch to Prompt |
| 2 | Add from photo | `testQA2_AddFromPhoto` | text screenshot via real Vision OCR; text-free food photo → "Guessed from photo" or the friendly message, never the old OCR error |
| 3 | Generate and edit | `testQA3_GenerateAndEdit` | edit title + cuisine on the review step |
| 4 | Save | `testQA4_Save` | lands in the library |
| 5 | Share | `testQA5_Share` | "Share link" and "Share as text" both open the share sheet (one link per share) |
| 6 | Open shared recipe | `testQA6_OpenShared` | `ate://recipe/<slug>` opens + saves; expired slug; unknown route → not found |
| 7 | Sync account | `testQA7_SyncAccount` | sign in, edit, sync, then a second launch with an empty local store pulls the edit (persistent mock server) |
| 8 | Timers | `testQA8_Timers` | start, pause (doesn't move), resume, leave cook mode → timer bar, finish → chime + haptic fired, Live Activity requested (test hook `qa.probe`) |

Real-server staging sync via curl runs only if staging secrets are configured (not yet — PRD v1.3 action 7).

## Manual on-device checklist (do before handing a build to testers)

Device: ______ iOS: ______ Build: ______ Apple Intelligence on? ☐

1. **URL** ☐ a recipe blog link imports with "Imported from page data" ☐ an Instagram reel with a caption imports ☐ one without shows "paste the caption into Prompt" and the button switches tabs ☐ a dead site fails in ≤ 10 s with a clear message
2. **Photo** ☐ a screenshot of a recipe imports ☐ a camera photo of a plate gives "Guessed from photo" ☐ a non-food photo gives the friendly message
3. **Generate & edit** ☐ a prompt gives a "Made with Apple Intelligence" card ☐ edit title, an ingredient, a step and cuisine before saving
4. **Save** ☐ appears in the library ☐ survives force-quit and relaunch
5. **Share** ☐ Share link sends exactly one link ☐ Share as text reads well in WhatsApp/iMessage
6. **Open shared** ☐ tapping `ate://recipe/<slug>` on the standard iPhone opens the recipe (a second-device check is optional, non-gating #359 follow-up) ☐ an old/invalid link says expired
7. **Sync and data portability** (two-device variants are optional, non-gating #359 follow-up; retain account isolation and failed-write checks on the standard device) ☐ sign up → confirmation email → link opens ate signed in ☐ magic link ☐ password reset ☐ edit on phone A, pull on phone B ☐ edit the same recipe on both offline, then sync: newest wins ☐ delete on A disappears on B ☐ export data, verify recipe/shopping/diary provenance and nutrition snapshots, import on phone B ☐ import asks before replacing nutrition goals/preferences and keeps existing records with matching IDs ☐ sign out (keep) / sign in as a *different* account: the first account's recipes don't appear ☐ sign out and remove local data clears the diary/goals ☐ delete account clears local diary/goals too
8. **Timers** ☐ start a step timer, lock the phone: Dynamic Island + Lock Screen count down ☐ pause/resume ☐ leave cook mode: timer bar shows above the tab bar ☐ finish: chime + haptic, notification if backgrounded
9. **Separate extended follow-up, not a gate** Other device/OS classes and largest Dynamic Type are tracked only in #359. Run them separately when requested; do not block this acceptance pass on them. VoiceOver review remains separate from the font/device matrix.

## Cooking Tracker — automated release gate and device follow-up (issue #31)

**Automated closure gate:** unit tests for day-key persistence/streak boundaries, Tracker focused UI tests, and Cook Mode completion/early-exit UI regressions must pass on the exact merged-main commit. The main Build IPA workflow runs these focused UI regressions on every push alongside the unit and key-flow QA gates; the full UI shard suite and backend E2E remain opt-in.

**Device-only follow-up (not a blocker for closing issue #31 under the 2026-10-12 scope decision):** tracked in [issue #60](https://github.com/melusi-k/ate-ios/issues/60). Simulator tests cannot certify relaunch behavior on physical hardware, real system time-zone changes, VoiceOver focus order, or largest Dynamic Type (the latter is separate non-gating #359 follow-up). Record these when a test device is available; do not claim them complete based on simulator output.

Record one row for each tested device/build when this follow-up is performed.

Device: ______ iOS version: ______ build number/channel: ______ date/time: ______

1. **Explicit completion:** start a saved recipe in Cook Mode and exit before the final step. Open Tracker and confirm no cooking event was added. Re-enter Cook Mode, advance to the final step, tap **Finish cooking**, and confirm today's date is marked and the recipe appears in that day's details.
2. **No duplicate event:** finish the same recipe twice on the same local day. Confirm the day contains one entry for that recipe and the streak counts the day once.
3. **Relaunch persistence:** force-quit Ate after completion, relaunch it, and confirm the same date remains marked with the same recipe in day details.
4. **Time-zone change:** note the recorded local date, change the device time zone in Settings, reopen Tracker, and confirm the stored day key has not silently moved or been rewritten. Record both time zones and the date shown before/after; report any ambiguity rather than marking pass.
5. **VoiceOver:** enable VoiceOver. Verify previous/next month controls are announced by name; each date exposes its number and relevant today/cooked/selected state; weekday headings are not redundantly spoken; opening a date moves focus sensibly into the selected-day sheet and the recipe title/fallback is announced.
6. **Largest Dynamic Type:** separate non-gating follow-up in #359. It is not part of this normal-size acceptance checklist.
7. **Layout:** on the standard iPhone 18 Pro at default text size, confirm the Tracker and day details remain reachable. Other device layouts are non-gating follow-up in #359.

Device follow-up evidence: device model, iOS version, app build/channel, test date, pass/fail for each numbered step, and screenshots for the normal-size calendar, selected-day sheet and any failure. Keep separately requested #359 screenshots outside this acceptance evidence. Do not mark a device-only criterion complete from simulator output alone.

## Insights hub — issue #38

The Insights tab is the combined daily/monthly hub; both its tab label and native screen heading are **Insights**. Automated acceptance is required before merge; physical-device and entitlement-matrix checks are deferred to the final pass of issue #38 and do not block this UI implementation. The same `CookingTrackerEntryUITests` target retains the calendar/month-navigation/empty-day cases owned by [issue #31](https://github.com/melusi-k/ate-ios/issues/31), while PR #63's main-push gate also runs Cook Mode completion-to-history and early-exit-negative tests. Keep these shared regressions green as one suite.

1. Open Insights from its tab and from the Library/Home shortcut. Confirm the shortcut opens the Insights root.
2. Confirm the screen includes the cooking streak/calendar, the Health insight card, meal/reflection content when Health data is available, and the local Ate journal preview. Confirm the calendar and journal are hosted in one scroll view.
3. Launch with no Health authorization and open Insights without tapping **Connect Apple Health**. Confirm no system/mock permission prompt appears. Tap Connect only when ready to test the explicit authorization flow.
4. Run the focused `CookingTrackerEntryUITests` plus the normal compile, unit, and UI-test CI gates. Preserve any failing assertion and source line rather than masking test failures.
5. Confirm the full searchable journal list and entry detail routes still work; Ate journal entries remain local-only and Ate does not write to Apple's Journal.

**Deferred final device pass:** on supported/unsupported devices, record Health permissions (including denial), entitlement/sideload and picker behavior, sample-data/no-data fallback, journal persistence, location/media, VoiceOver, and any separately requested non-gating #359 font/device exploration. Include device model, OS, build/channel, exact result and evidence. Simulator CI does not close these device-only checks.

## Testing stages and release checklist

### Everyday pull-request gate

The everyday PR gate uses the acceptance scope above and is intentionally short: validate documentation/acceptance-ID consistency, build the iOS app for a simulator, and run only the high-value smoke checks for account sync, Cooking Tracker, and Cook Mode completion/history. The main-branch IPA workflow builds and verifies the release artifact on every push. The separate Dogfood Qualification workflow runs the required unit suite and seven stable critical flows on pull requests; the known Settings/account-sync quarantine is diagnostic only and is never called passed. Broad UI shards and backend E2E remain opt-in. A green everyday gate is evidence for the named required checks only; it is not a claim that the exhaustive test suite has passed.

### Deliberate pre-production gate

Run **Actions → Pre-production QA → Run workflow** when preparing a pre-production build, or push a release-candidate tag named `preproduction-*`. Legacy workflow implementation currently retains and runs the full `AteTests` unit suite, focused settings/Tracker/Cook Mode/Health-journal/widget-intents acceptance checks, all four existing UI shards (`AteUITests`, `CoverageUITests`, `AccessibilityAuditUITests`, `WidgetsIntentsUITests`), and backend E2E against the configured QA backend. The four independent full-suite shard jobs each use **two Xcode simulator workers** (`-parallel-testing-enabled YES -parallel-testing-worker-count 2`) to shorten shard critical paths; the focused acceptance/regression invocations remain serial. Each UI shard and backend E2E has its own diagnostics artifact. Review all job results and artifacts before distributing the build. A worker count of two is a conservative cap, not a guarantee of lower billed runner minutes; monitor test stability, simulator memory pressure and end-to-end wall time. See [CI execution policy](CI.md) for the rationale, exact scope and rollback criteria. Do not delete a failing test merely to obtain a green run. Large-text/Dynamic Type and other-device selections in this legacy matrix must be separated into non-gating #359 work; their presence here does not override the acceptance scope above.

### Failure classification and quarantine register

Classify each failure before changing product code:

- **Product defect:** reproducible incorrect app behavior, supported by a failing journey/assertion that accurately represents the requirement. Fix the app and add/update coverage only when needed; do not expand UI coverage by default.
- **Test-quality issue:** an assertion that is ambiguous, targets a covered/non-interactive element, relies on nondeterministic setup, or otherwise does not correctly represent the intended behavior. Record the test name, failure evidence, reason, owner, and follow-up condition. Do not report it as an app defect or as a pass.
- **Environment/infrastructure issue:** simulator, signing, dependency, runner, or tool failure that prevents a trustworthy result. Record the evidence and rerun only after identifying a plausible transient cause.

Quarantined tests remain in source and are explicitly named in CI/docs with a reason and an accountable owner. A quarantine is **not a pass**: report it as skipped/quarantined and track the removal condition. Current known quarantine: `testBetaChannelShowsBetaDiagnosticsEntry` — launch-channel argument is not reliably applied in CI; owner: iOS QA/automation maintainer; exit condition: deterministic launch-channel fixture is available and the test passes repeatedly. Any new quarantine must include an explicit owner before it is accepted.

### Pre-production release checklist

Record build number, commit SHA, device model, OS version, date, tester, and evidence. Check every item before distribution:

- [ ] Exact release-candidate commit passed its required normal-size checks, or every in-scope failure is classified and explicitly accepted by the release owner; quarantined tests are not represented as passing. Legacy #359 font/device results are separate and non-gating.
- [ ] On simulator: cold launch, create/open/save a recipe, edit it, open Library, enter Cook Mode, complete a recipe, and verify the Tracker cooking-day/history entry.
- [ ] On simulator: verify account sign-in/sync journey using the configured QA fixture; verify Health unavailable/denied and sample-data fallback; open journal list and entry detail.
- [ ] On a real supported iPhone: launch and relaunch, save/open a recipe, complete Cook Mode and verify Tracker persistence, check sign-in/sync if staging credentials are available, and confirm no crash or blocked navigation on critical journeys.
- [ ] On the standard device at default text size: inspect critical navigation and VoiceOver focus for Library, Cook Mode, Tracker, Health insight and journal entry. Record unavailable device/entitlement cases as not tested, never as passed. Largest Dynamic Type and other devices remain separate non-gating #359 follow-up.
- [ ] Review crash logs, known issues, and test artifacts; document remaining product defects and test-quality issues separately.
- [ ] Release owner signs off the checklist before distributing the pre-production build.

A simulator cannot satisfy the real-device checklist. If no physical device is available, mark that portion **Not run** and do not claim the pre-production device gate is complete.


## Temporary everyday-CI quarantine — Settings/account sync (issue #76)

`AteUITests/KeyFlowsQATests/testQA7_SyncAccount` is retained and executed in everyday CI for diagnostics, but a failure is reported as **QUARANTINED / NOT PASSED** and does not block the everyday build while the recipe editor `Done` button selector is repaired. The failure is not classified as a product defect or test-only defect without evidence. The full log and xcresult remain artifacts. Pre-production must continue to execute the test and expose its real result; quarantine is not coverage or release approval. Track account/sync behavior under [#34](https://github.com/melusi-k/ate-ios/issues/34), Settings interaction under [#74](https://github.com/melusi-k/ate-ios/issues/74), and repair/repeated-run evidence under [#76](https://github.com/melusi-k/ate-ios/issues/76).


## Test coverage layers and work tracking

Use [issue #79 — Feature verification campaign](https://github.com/melusi-k/ate-ios/issues/79) to coordinate feature-by-feature execution. Keep these test layers distinct; passing one does not imply another passed:

- **Unit/model:** pure logic, parsing, validation, transformations, persistence rules and state transitions.
- **Integration/contract:** SwiftData, backend protocols, Supabase/auth/sync/sharing, deep links and extension boundaries.
- **Focused UI/regression:** a single critical journey or bug regression with deterministic setup and stable accessibility identifiers.
- **Full UI/accessibility:** broad UI shards, accessibility audits and VoiceOver; Dynamic Type and other-device responsive layouts are separate non-gating #359 coverage.
- **Backend/end-to-end:** staging backend journeys, auth/share/sync and multi-step integration.
- **Platform/extension:** widgets, intents, Siri/Shortcuts, Live Activities, notifications, Watch and share extension.
- **Physical-device/manual:** email round trips, real two-device sync, Health permissions/data, background timers, entitlement/sideload behavior and accessibility on device.
- **Release/reliability:** cold launch, upgrade/persistence, offline recovery, crash evidence, channel/version metadata and artifact integrity.

For day-to-day feature work, run the smallest relevant layer first. Run broad suites at planned checkpoints or pre-production candidates; do not rerun every UI shard for an isolated code change unless its impact warrants it. Every matrix row should name the test, acceptance ID, layer, last run/commit, evidence and status (**PASS / FAIL / QUARANTINED / NOT RUN**). Old historical passes are not current passes. Quarantined is never pass.

Use [issue #78 — CI/workflow operations](https://github.com/melusi-k/ate-ios/issues/78) for workflow triggers, runtimes, quarantines, diagnostics and documentation alignment. Use [issue #70 — coverage reconciliation](https://github.com/melusi-k/ate-ios/issues/70) for PRD/checklist/matrix mapping; create or update feature-owned issues for product defects rather than placing every defect in the campaign issue.
