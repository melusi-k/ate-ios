# CookPlan cancel: background reminder removal

Status: HYPOTHESIS, not native-qualified. Reviewer 2 must accept the behavior change.

Run 45141909439 failed the saved-plan Cancel dismissal assertion. Reviewer's
xcresult inspection found the diagnostic launch argument but no emitted phase
records. The first missing phase is unknown. Earlier runs 44982883240 and
44970747415 also failed the assertion; 44835322541 and 45009157802 passed.

## Possible source path, not an observed cause

The prior sheet awaited ordered notification cleanup before dismissal. That cleanup
can wait on earlier queue work, synchronous system removal dispatched off Main, and
pending-notification verification. A delayed boundary on that path could retain the
sheet. We do not know which boundary, if any, caused this run's failure. A separate
2.87s unit-test entry delay is not proof of a hung OS callback or of this UI cause.

## Proposed behavior

The sheet calls the production cancelFromSheet seam. Local cancellation must first
commit successfully. Notification cleanup then registers synchronously in the same
intent queue before the success action dismisses the sheet. Cleanup no longer holds
the sheet open. A later re-enable stays ordered after cancellation.

Local-store failure throws before registration and the success action. The sheet
clears busy and retains its existing problem text. Reminder verification failure
instead invokes the toast callback after dismissal. This last change needs Reviewer
2's acceptance. A locally cancelled plan is not proof that the OS reminder is gone.
The existing async cancel(recipeID:) remains for AppStore callers.

## Evidence and diagnostics

Four new native tests call the same production seam as the sheet: synchronous local
commit and success action while removal is suspended; immediate later re-enable;
retained-reminder failure callback; unreadable local state with no success action or
notification removal. Continuation gates replace timing guesses. No sleeps, retries,
timeout increases or changes to existing native assertions.

The QA-only diagnostic now writes only to a file ledger, not stdout. A lock covers
creation and complete-line appends across threads. Fixed marks contain phase,
generation, monotonic time and thread flag, no recipe IDs or user content. The
workflow copies Library/Caches/cookplan-cancel-ledger.txt into the already-exported
cook-plan-cancel-live-query directory. File I/O remains synchronous; this avoids a
stdout pipe dependency but does not claim all diagnostics are cost-free.

Sheet marks: handler-enter/busy-set, dismiss-before/return, cancel-catch.
Production seam marks: local-cancel-before/after; notification-cancel-before/after
bracket registration, not completion. Background marks: registered, await, return or
catch. Existing queue/removal marks remain.

Base: published #658 head 800f689d6e5e9b327a5b62bf8d53147d38dabfa1. Its softened
entry-gate document is retained byte-for-byte. Python validation is not native proof.
The next native run must qualify the four new tests, the existing CookPlan UI
journey, and the exported ledger. No workflow dispatch is part of this packet.
