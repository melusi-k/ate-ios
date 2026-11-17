# #551 first native reopen result: product dismissal still blocked

Basec5c0ed7f8138a3765b3db195c969803fffad9723.
https://github.com/melusi-k/ate-ios/actions/runs/43913665867/job/133462195778?pr=551

The original reopen/setup repair did NOT pass its first native test. CookPlan line43 now fails the unchanged10s old-sheet-disappearance boundary,54.054s total. Cancel tapped41.39s; reminder remains through52.56s. No reopen occurs. Thus the earlier hypothesis of simply tapping the underlying plan button too soon is insufficient. Keep the real failure; do not lengthen the wait or dismiss artificially.

Exact inner failure hierarchy0C9AEB69-B8A8-436C-94C3-46B9F575F07F shows old sheet, reminder0, saved plan and Cancel cooking plan. Done and Save are Disabled. No cookPlan.message error appears. The supplied CookPlan PNG is an earlier saved-plan capture, not an assertion-time screenshot. The earlier #539 last video frame also showed the old saved-plan sheet. No new native pixel result was generated here.

Source: cancel() sets busy=true, enters a MainActor task, deletes the local plan, awaits store.cookPlanNotifications.cancel, then sets busy=false and dismisses. Catch sets busy=false plus cookPlan.message. The disabled toolbar/no-error state supports an unfinished busy task, not a proven completed dismissal or handled failure. It does not establish whether local deletion completed.

The notification adapter serializes work behind a tail Task. Saving with reminder OFF returns after synchronous local save but enqueues removal and pending-ID verification. A later Cancel queues its own removal behind that earlier task. Thus Cancel can wait on unfinished prior Save cleanup before its own notification work starts. Or Cancel's removal/verification can itself remain suspended. No OS phase evidence currently distinguishes these. There is no independent source defect proven in SwiftUI dismiss. Reopening the sheet does not prove OS cleanup from Save completed.

Patch is diagnostic-only: fixed phase+monotonic-milliseconds ring,32entries, process-local and numeric/fixed-token system log. Queue wait/admitted/returned, real remove and verify begin/return, Cancel entry/local delete/OS completion/failure/dismiss request. No identifiers, text, data counts, notification IDs, error strings, file persistence, network or telemetry. Existing cancel button AX value exposes the trace on normal body reevaluation. The trace is deliberately nonobservable; AX can lag if body does not reevaluate, so retain system/app logs too. No new waits/awaits, retry, task, cleanup skip/reorder, mocks, app-state write beyond receipts, or changed success/error semantics.

The queue phases are not per-intent IDs. Sequence plus Cancel entry separates earlier Save work from Cancel; concurrent unrelated operations can still make attribution ambiguous. Missing terminal token is evidence of the last retained stage, not proof of a particular OS failure. Keep the logs before termination and retain the failure hierarchy.

259PythonPASS (baseline257); exact two-file behavior inverse and mutation rejectionPASS. Existing queue historical hash retained after stripping only exact diagnostic delta. Three touched/new Swift files tree-sitter grammarPASS, not compiler/typecheck. ALL AteUITests Swift sources byte-identical to base, including all strict reopen assertions. Native compile/typecheck/XCTest/device, new AX/log delivery and updated visual state UNRUN. Diagnostic is NOT a cure and no new native run was launched.

NutritionDiary line124 query timeout after240s cap remains separate UNPROVEN; this packet does not fix or waive it. Reviewer alone reviews/publishes, branches retained, source PR closure only after confirmed destination commit.
