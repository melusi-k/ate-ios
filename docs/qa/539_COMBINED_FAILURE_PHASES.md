# #539 combined real-Keychain and cleanup-phase diagnostic head

Base832042107e510ec75fa7be627d240982a809f2db. This extends the real-Keychain status packet, NOT the rejected mock-credential branch. Product cause remains UNPROVEN. No failure is waived or repaired by this packet.

## Updated original evidence

Nutrition job was cancelled, not by us. Its recorded real failures still count. CookPlan failed45.433s: after Cancel40.48s, it waits only for the underlying recipe.plan to exist, taps42.97s, computes hit{-1,-1}, then fails original cancelPlan absence assertion. Last screen-recording frame shows the old Saved plan sheet and Cancel cooking plan. No failure-instant named PNG.

Journal ClearAll failed61.669s at line36, which waits for "No journal entries yet", NOT for a seeded precondition. Before that it seeds/checks Journal, taps Settings Clear all33.50s, resolves another Clear all via app.buttons["Clear all"].firstMatch, taps36.24s, then Journal47.55s. Failure hierarchy AND last screen-recording frame show selected Journal root with "Seeded from a Journal moment" still present, no empty state. The pixels show the row below bottom chrome; this is evidence of surviving/stale content, not an offscreen-target explanation for the missing EMPTY-state assertion. A real privacy/reset defect remains possible and important. No supplied record proves the dialog's actual handler ran: the second label-only target is unscoped, but duplicate-target misselection is a hypothesis, not a diagnosis.

Account update: last video frames now exist for SettingsSync and AccountSwitch, visibly showing the exact red sessionWriteFailureMessage. Shopping video endings show SpringBoard and are not auth-error pixels; their inner failure hierarchies do show the same error. This updates the earlier report's missing-pixel caveat without pretending these are assertion-instant captures.

FoodDiaryLog capped240s, then query timeout at line124 and very slow teardown. Summary/spindump does not establish a causal connection to either cleanup or Keychain. Remains unqualified separately.

## Product paths and common-cause hypothesis

ClearAll's actual handler schedules clearLibrary. It first clears local cooking plans then AWAITS verified OS notification cleanup (pending IDs, remove, delivered removal, verify pending IDs). Only afterward does it eraseJournalPersonalData and advance Journal revision. CookPlan Cancel locally deletes its plan then AWAITS the same adapter's single removal/verification before dismissal. An unfinished OS cleanup could explain both final frames. A failed cleanup, a handler that never ran, or stale presentation after erase are also possible. Raw logs contain no stage receipts. Do not reorder Journal erasure, skip cleanup, dismiss early, force an empty UI or increase waits on this evidence.

Existing native reset tests in this run passed for legacy actual-owner erasure, bound actual-owner erasure and personal files; explicit sign-out UI also emptied Journal and expiry UI preserved it. Those are useful comparisons but cannot override this real Settings ClearAll failure.

## Added receipts only

A fixed enum records up to48fixed stage tokens plus monotonic uptime milliseconds, process-local and in system log. No text, IDs, recipe data, row counts, notification IDs, credentials or raw errors. It is NOT Observable and does not trigger rendering or schedule work. No files/network/telemetry.

Stages cover:
- Actual Settings confirmation callback, clearLibrary entry/refusal.
- Local plan-store clear begin/return, pre-erase cleanup begin/return/failure.
- All-notification pending/remove/delivered/verification begin+return.
- Journal-containing local erase begin/whole operation return/failure.
- CookPlan Cancel entry/local delete/OS return/failure/dismiss.
- Single-notification removal and verification begin+return.

Surviving Journal new-entry button and CookPlan cancel button expose the current summary as an AX value when their existing body reevaluates. These are snapshots, not a new polling/render loop; a value can lag if the body does not reevaluate, so retain the numeric system log too. No visible title/text change, extra await, wait, retry, tap, cleanup skip or reordering. Queued work's missing begin token distinguishes it from a started but unfinished step. Success/refusal semantics remain unchanged. Notification cleanup phase receipts cover the real client, not an injected mock.

The existing real-Keychain trace still wraps live Security calls once and returns the actual unchanged status. authError AX value exposes numeric operations/statuses only for sessionWriteFailureMessage. Product Keychain write failure still blocks sign-in. Device/sideload sign-in is NOT qualified until actual status and final effective re-signed entitlements are checked. See539_REAL_KEYCHAIN_STATUS.md for the source comparison and Apple sources.

## Verification and next decision

323PythonPASS; Swift tree-sitter grammarPASS for10touched/new Swift files, not a compiler/typecheck. Exact phase inverse across6product files and mutation rejectionPASS. ALL AteUITests Swift files byte-identical to83204210. Existing audits compose only exact diagnostic edits and retain original historical hashes. No original XCTest assertions, timeouts, test setup, fixture flags, inputs or journeys changed. Native diagnostic tests added in the earlier Keychain packet are unchanged in this extension.

Native compile/typecheck/XCTest, updated AX values/system-log delivery and post-patch pixels UNRUN. Inspected original Journal, CookPlan and Account final-frame images only. This is diagnostic progress, not acceptance. Trace is bounded and process-local, so collect before termination; no guaranteed durable export.

One next Account+Nutrition run can distinguish the missing evidence if the diagnostic head compiles and the original assertions fail again. Preserve original tests. For ClearAll, if clearEraseReturned appears with the row still present, inspect storage owner/cache/revision publication; if erase never begins, inspect the exact previous fixed stage. If clearConfirmed is absent, recover the target-selection recording. Those are conditional investigations, not asserted causes. For CookPlan, distinguish notification work not returned from completed cancellation/dismissal followed by invalid re-open delivery.

No native run launched, remote mutation, merge, publishing, spending or production write. Reviewer alone reviews/publishes. Keep all real reds/caps open. Source PRs close only after reviewer confirms destination commit; branches kept.
