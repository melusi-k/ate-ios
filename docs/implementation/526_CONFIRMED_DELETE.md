# #526 confirmed reflection delete follow-up

Base4e600cebfb9718bc2d92637874018292b3ad404c. Reported run43317070379,
artifact13992585044: native ManualReflectionEditSaveCancelAndConfirmedDelete
confirms Delete at93.16s, detail still exists105.14s. Original fail remains fail,
not a stall waiver. #527 edit-save outcome work does not cover this action.

## What evidence establishes

Full extracted confirmation PNG shows the correct edited target and native
Cancel/Delete alert. Log synthesized Delete against the native Delete button.
No post-confirmation PNG/hierarchy or app-write result was supplied. Existing
code leaves detail on failed delete, otherwise clears it after parent revision
refresh and success notifications. Evidence does NOT prove whether the committed
write failed or the conditional alert/parent-refresh invalidated the detail action.
Do not call this a proven SwiftData defect or merely a harness target mistake.

## Runtime candidate and deterministic safety improvements

Move the alert from the conditional List/model branch onto the stable detail
owner; act on immutable route entryID, not captured reader object e. Resolve
reflection kind in a new write context, preserve writer admission/rollback,
and verify absence through a second committed reader before reporting success.
No-op/throwing save is not success. Media is still removed only after verified
record deletion. Other entry kinds, missing IDs and unavailable store refuse.

On verified success, retire detail and dismiss BEFORE notifying loaded parent
history, instead of rebuilding parent rows while the child alert/model is still
live. On failure, keep detail and a persistent journal.delete.error message.
No success toast/QA/revision/dismissal on failure. Confirm/Cancel have distinct
stable IDs. Alert text, destructive confirmation and Cancel remain unchanged.
No Journal/Food Journal activation, archive/reset or sync policy changed.

## Qualification, not a declared cure

Existing UI method still exercises create/edit/cancel/reopen/delete, retains
original10second detail-absence wait and all final history-absence assertions.
It now scopes confirmation to the actual alert/button, captures posttap pixels
BEFORE that wait, and rejects visible write error. This makes another failure
explainable; no fallback back-button, retry loop or larger timeout.
New UI method injects one failed delete COMMIT, proves retained exact detail+
error, then explicitly reopens confirmation and requires successful removal.
Injection is UITesting-only and not used by the original passing/failing case.
Three native unit methods test stable edit/delete identity, no-op writer refusal
then retry, and unknown/missing-kind refusal. Existing methods/assertions retained.
Required unit list preserves base25+2 reminder names and adds only these3.

Python/static checks are not Swift/XCTest, OS interaction or visual acceptance.
Native run and fresh screenshots NOT RUN. Parent received the recovered decisive
old confirmation PNG. Reviewer must inspect exact-head post-confirmation, failure
and retry/history screenshots and both methods before accepting this candidate.
If original still fails, new screenshot/error separates write refusal vs stale
presentation. Do not close the failure from source alone.
