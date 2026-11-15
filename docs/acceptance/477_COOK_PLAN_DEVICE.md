# #477 cooking plan: physical-device acceptance

Source reviewed: e6bcae0ef9ca1e156bd06ab6440609dfd921e379 (main).
This is preparation, not a pass. All physical rows below are NOT RUN. Record the
actual installed candidate's source, build and channel before running. A source
SHA in this document does not establish what is installed. Food Journal stays OFF.

## Source boundary

Already present in this source: RecipeDetailView's "Cook this on..." action,
CookPlanSheet, local CookPlanStore, ordered CookPlanNotifications and cold-start
CookPlanNotificationRouter. One plan per recipe, stable reminder identifier,
explicit saved instant and chosen zone, separate ate.cook-plan.* namespace.
Saving without a reminder is local and does not request permission. Reminder
save persists first; denied permission keeps the sheet with an honest message.
UI testing skips real reconciliation, so fixture success cannot prove delivery.

The existing CookPlanUITests method covers no-reminder save/reopen/cancel only.
CookPlanTests, CookPlanNotificationTests and CookPlanAccountSafetyTests cover
source fixtures for persistence, replacement, namespace/payload checks, queued
cleanup and failures. No fresh native result is claimed here. The zone fixture
checks persistence, not ambiguous/skipped DST clock times or a physical trip.

## First owner run: small, non-destructive

Use a saved disposable recipe and ordinary text size. No sign-in, sync, clear-all,
new app install or notification reset is needed for this first run. Do not delete
personal data to create a clean state.

1. Record iPhone model, iOS, app version/build/channel/source if available,
   current time zone, and current Ate notification permission in iPhone Settings.
2. Start a stopwatch on the saved recipe's visible Library card. Open it, use its
   expand control if shown, then "Cook this on...". Choose a future date/time,
   turn "Remind me" OFF, review the picker and displayed zone, then Save.
3. Stop timing when save completes. Record elapsed seconds, not a rounded pass.
   Target is under30seconds excluding OS permission-prompt time. If timing ran
   long because the route or controls were unclear, record that, do not discard it.
4. Reopen the plan. Capture the recipe title, saved time+zone and reminder OFF.
   Close/reopen Ate normally while offline and confirm this same plan remains.
5. Change the date/time and Save, reopen to verify the new value. Cancel cooking
   plan, reopen and confirm no saved-plan section. This cancels a plan, not recipe.

This first run is not full #477 acceptance. Do not label it delivery, cold-start,
denied-permission or timer-isolation proof.

## Reminder proof on the same exact candidate

Do not change the system clock. Pick a reminder far enough in the future to
finish the setup, for example at least5minutes ahead, and write its exact time
and zone. Record Focus/notification-summary settings and screen state if delivery
is absent. Late/absent delivery remains unproven rather than automatically a bug.

| Case | Steps and expected observation | Result/evidence |
| --- | --- | --- |
| Permission allowed | If not determined, choose a reminder then Save and allow the OS prompt. Otherwise record already allowed. Before choosing a reminder, merely opening the form must not ask permission. Plan saves; exactly one reminder arrives at its selected instant. | NOT RUN |
| Tap while active | Tap that recipe's reminder; intended saved recipe opens, never another recipe. Capture title and reminder time. | NOT RUN |
| Cold start | Schedule another future occasion, terminate Ate before it fires, then tap delivered notification. Intended recipe opens after launch. | NOT RUN |
| Replace/repeated Save | Change A to a later B; Save twice/reopen/relaunch. Observe across BOTH time windows: no old-A notification and one B reminder. A single B capture cannot prove A was cancelled or absence of duplicates. | NOT RUN |
| Reminder OFF/cancel | Schedule A, then turn reminder OFF and save, or cancel plan. Retain observation through A. Plan remains when OFF; cancelled plan disappears. No obsolete notification. | NOT RUN |
| Denied | With permission denied, select reminder and Save. Plan stays with explicit notifications-off message; no repeated permission prompt. Done/reopen/offline relaunch retain chosen time. Never expect a notification. Preserve the user's prior permission setting afterward if changed for this test. | NOT RUN |
| Delete recipe | On a disposable recipe only: schedule A, delete recipe, observe through A, no pending reminder delivers. A stale already-delivered tap must show safe missing-recipe state, never another recipe. If deletion removes that notification, record stale-tap case as not exercised. | NOT RUN |
| Timer isolation | Have an ordinary timer active while changing/cancelling a cooking plan; timer remains and fires as expected. Cancel the test timer afterward. | NOT RUN |
| Time zone/DST | Record original zone and instant. In a separate controlled test, after agreeing to a device-zone change, verify saved plan retains chosen zone/instant. Explicitly test skipped/repeated DST wall-clock choice before claiming DST acceptance. Restore original zone. | NOT RUN |
| Past reminder | Choose a near-future time, wait until past before Save. Save must not silently schedule a past reminder; confirm persisted previous plan is unchanged. | NOT RUN |

Clear-all and account removal are separate destructive acceptance, not part of
the quick owner run. Use an expressly disposable dataset with a verified recovery
route and approval before performing them. Verify plan/reminder cleanup without
affecting unrelated timer semantics. Fault injection and corrupt-store fixtures
are not evidence of real OS cleanup.

## Evidence record

For each row capture: test start/end with zone, exact app build/channel/source,
physical device/iOS, permission before/after, recipe label, chosen time/zone,
actual result, elapsed seconds if timed, screenshot/video references and any
restoration/cleanup. Distinguish PASS, FAIL, BLOCKED and NOT RUN. Keep failures.
Private recipe contents need not be collected: a disposable named recipe is enough.

Acceptance issue: https://github.com/melusi-k/ate-ios/issues/477
