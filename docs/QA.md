# QA pass on key flows (beta-promotion gate)

The workflow has two validation levels. **Every push to `main`** sets `RUN_TESTS=true` for the release job and runs unit tests plus the eight `KeyFlowsQATests` flows and focused release-job checks before publishing `latest-build`. The full UI-test shards and backend E2E jobs are conditional: they run on manual dispatch with `run_tests=true` or when the pushed commit message contains `[run tests]`. A validated beta promotion requires unit tests, all eight key flows, every UI-test shard and backend E2E to pass; only then should the exact validated build be promoted to `latest-beta`. Verify the current `.github/workflows/build-ipa.yml` conditions when this workflow changes. The flow → pass/fail table goes into the job summary and release notes (`scripts/qa-summary.py`). The UI-test launch flag enables beta diagnostics for automation; a production build must not show the Beta banner or Settings › Beta testing entry. Validate channel gating separately with `TierA` and `Production`/empty channel builds.

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
6. **Open shared** ☐ tapping `ate://recipe/<slug>` on a second iPhone opens the recipe ☐ an old/invalid link says expired
7. **Sync** ☐ sign up → confirmation email → link opens ate signed in ☐ magic link ☐ password reset ☐ edit on phone A, pull on phone B ☐ edit the same recipe on both offline, then sync: newest wins ☐ delete on A disappears on B ☐ sign out (keep) / sign in as a *different* account: the first account's recipes don't appear ☐ delete account
8. **Timers** ☐ start a step timer, lock the phone: Dynamic Island + Lock Screen count down ☐ pause/resume ☐ leave cook mode: timer bar shows above the tab bar ☐ finish: chime + haptic, notification if backgrounded
9. **Other device classes** ☐ an iPhone without Apple Intelligence (badges say Demo / page data) ☐ iOS 18 device if available ☐ VoiceOver pass on Library, Add, Cook ☐ largest Dynamic Type

## Cooking Tracker — automated release gate and device follow-up (issue #31)

**Automated closure gate:** unit tests for day-key persistence/streak boundaries, Tracker focused UI tests, and Cook Mode completion/early-exit UI regressions must pass on the exact merged-main commit. The main Build IPA workflow runs these focused UI regressions on every push alongside the unit and key-flow QA gates; the full UI shard suite and backend E2E remain opt-in.

**Device-only follow-up (not a blocker for closing issue #31 under the 2026-10-12 scope decision):** tracked in [issue #60](https://github.com/melusi-k/ate-ios/issues/60). Simulator tests cannot certify relaunch behavior on physical hardware, real system time-zone changes, VoiceOver focus order, or largest Dynamic Type. Record these when a test device is available; do not claim them complete based on simulator output.

Record one row for each tested device/build when this follow-up is performed.

Device: ______ iOS version: ______ build number/channel: ______ date/time: ______

1. **Explicit completion:** start a saved recipe in Cook Mode and exit before the final step. Open Tracker and confirm no cooking event was added. Re-enter Cook Mode, advance to the final step, tap **Finish cooking**, and confirm today's date is marked and the recipe appears in that day's details.
2. **No duplicate event:** finish the same recipe twice on the same local day. Confirm the day contains one entry for that recipe and the streak counts the day once.
3. **Relaunch persistence:** force-quit Ate after completion, relaunch it, and confirm the same date remains marked with the same recipe in day details.
4. **Time-zone change:** note the recorded local date, change the device time zone in Settings, reopen Tracker, and confirm the stored day key has not silently moved or been rewritten. Record both time zones and the date shown before/after; report any ambiguity rather than marking pass.
5. **VoiceOver:** enable VoiceOver. Verify previous/next month controls are announced by name; each date exposes its number and relevant today/cooked/selected state; weekday headings are not redundantly spoken; opening a date moves focus sensibly into the selected-day sheet and the recipe title/fallback is announced.
6. **Largest Dynamic Type:** set the largest accessibility text size and inspect the streak label, month title/navigation, weekday row, all date buttons, and selected-day sheet. Confirm there is no clipping, overlap, or unreachable control; all days remain tappable.
7. **Layout:** check portrait and landscape on iPhone; on iPad, check the supported sidebar layout if available. Confirm the Tracker remains reachable and the calendar/day details fit without controls being obscured.

Device follow-up evidence: device model, iOS version, app build/channel, test date, pass/fail for each numbered step, and screenshots for the calendar, selected-day sheet, largest Dynamic Type, and any failure. Do not mark a device-only criterion complete from simulator output alone.

## Today & Journal Tracker hub — issue #38

The Tracker tab is the combined daily/monthly hub; its tab label remains **Tracker** and its screen heading is **Today & Journal**. Automated acceptance is required before merge; physical-device and entitlement-matrix checks are deferred to the final pass of issue #38 and do not block this UI implementation. The same `CookingTrackerEntryUITests` target retains the calendar/month-navigation/empty-day cases owned by [issue #31](https://github.com/melusi-k/ate-ios/issues/31), while PR #63's main-push gate also runs Cook Mode completion-to-history and early-exit-negative tests. Keep these shared regressions green as one suite.

1. Open Tracker from its tab and from the Library/Home shortcut. Confirm the shortcut opens the Tracker root.
2. Confirm the screen includes the cooking streak/calendar, the Health insight card, meal/reflection content when Health data is available, and the local Ate journal preview. Confirm the calendar and journal are hosted in one scroll view.
3. Launch with no Health authorization and open Tracker without tapping **Connect Apple Health**. Confirm no system/mock permission prompt appears. Tap Connect only when ready to test the explicit authorization flow.
4. Run the focused `CookingTrackerEntryUITests` plus the normal compile, unit, and UI-test CI gates. Preserve any failing assertion and source line rather than masking test failures.
5. Confirm the full searchable journal list and entry detail routes still work; Ate journal entries remain local-only and Ate does not write to Apple's Journal.

**Deferred final device pass:** on supported/unsupported devices, record Health permissions (including denial), entitlement/sideload and picker behavior, sample-data/no-data fallback, journal persistence, location/media, VoiceOver, and largest Dynamic Type. Include device model, OS, build/channel, exact result and evidence. Simulator CI does not close these device-only checks.
