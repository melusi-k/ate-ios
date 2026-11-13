# Account data changed: minimal user-facing state proposal

Branch-only candidate state/presentation, NOT activated UI. Source reviewed:841c14ee.
No new RPC retries, destructive recovery or automatic epoch adoption.

## Current source, not claimed shipped behavior

- AccountDataResetService.check maps PT409 to ResetRPCError.staleGeneration.
  Its localized text is "Account data was cleared elsewhere; fetch a fresh snapshot."
- GenerationFencedSync.snapshot/push propagate the error. Push stops the batch.
- ClearAllResetCoordinator.runCloudPhase retains the request/control record and
  maps staleGeneration to serverOutcomeUnverified. A snapshot error during start
  also becomes unverified. No new request UUID is automatically created.
- JournalStartupGateView shows "Saved data is not ready" with generic unverified
  request text. It has no recovery actions. ResetAwareStartup.start is one-shot.
- AteApp does not mount this graph. AppStore.syncNow uses legacy SyncService;
  Settings Clear all invokes clearLibrary, not the candidate reset coordinator.
  AccountCard's ordinary Sync now is not a safe stale-generation recovery action.

## Proposed state and words

A PT409 proves a generation conflict, not which device initiated it. Do not claim
"another device" as a verified actor. Distinguish this from lost-response reset:

### Put or admission conflict: Account data changed

Title: "Your account data changed"
Body: "This iPhone has an older version of your account data. Sync is paused so it
doesn't upload old data again. Ate needs to check the current account before you
can continue."
Primary: "Check account status"
Secondary: "Get help"

This is a blocking state for the affected account, not a disappearing toast.
Do not show the old account graph as an editable empty library. Do not show Sync
now, keep-editing, automatic retry, destructive discard or sign-out-as-a-bypass.
"Get help" opens only local guidance initially, not an unapproved external send.

### Pending Clear all conflict: Check your account-data request

Title: "Your account-data request needs checking"
Body: "Ate couldn't confirm this request because your account data changed. Saved
data is staying closed. Checking status won't start another Clear all request."
Primary: "Check account status"
Secondary: "Get help"

Keep the original request UUID, expected generation and receipt evidence. Never
claim "nothing was cleared", "clear completed", or replay a fresh reset UUID from
this state. A separate unknown-response state keeps the current generic wording.

## Required safe action contract before enabling the primary button

1. Cancel queued sync and stop accepting writes for this account; quiesce every
   app/extension/watch writer using the actual shared boundary, not Task.cancel
   alone. Invalidate the retained old graph and epoch. Keep failure UI mounted.
2. Capture and validate current owner/session and persistent reset-control evidence.
   Perform one explicit owner-scoped snapshot, never under the file lock. This is
   a user-requested status read, not an automatic retry of the failed write/reset.
3. After the await, revalidate owner, session and original writer proof. Do not
   stamp stale local bytes with the returned generation or upload the failed batch.
4. Pending reset: resolve its retained receipt/request against the snapshot before
   deciding on local cleanup. A higher generation alone does not prove this user's
   particular request completed. If proof is insufficient, stay blocked and explain
   that status could not be confirmed. Do not add a new reset request.
5. Reset elsewhere / advanced epoch: invoke the reviewed reset/admission policy
   for existing local personal bytes, minimal control and receipt handoff. Do not
   silently add a backup that conflicts with Clear all's personal-byte policy.
   Any destructive new recovery choice needs its own approved product flow.
6. Build a new graph only after durable receipt/local-domain validation and all
   writer installations succeed. Dismiss failure UI only after fresh admission.
   If status read fails, remain blocked, show a plain offline/auth/error message,
   and allow another explicit status check after that attempt finishes.

Until this entire contract is bound, do not ship an active Check account status
button. A display-only prototype must label its action as unavailable rather than
silently calling legacy sync. Adding words alone is not recovery implementation.

## Acceptance checks needed

- PT409 on first/partial put stops all subsequent puts, shows blocking state and
  never reports success or uploads old bytes under a new generation.
- Snapshot conflict cannot open an empty/fabricated generation-zero account.
- Clear conflict retains UUID/control and cannot create another reset automatically.
- Owner switch during status read never publishes another account's data.
- Lost-response vs confirmed conflict messages remain distinct.
- Offline/check failure stays blocked, no background retry; double taps send one
  status read. Actual successful re-admission replaces the entire old graph.
- Relaunch uses durable block/control evidence before ordinary stores load.
- Native normal-text/pixel/accessibility proof after actual UI implementation.

This packet adds AccountGenerationConflictState and the unmounted
AccountGenerationConflictView, plus two native test methods. The state maps only
staleGeneration, preserves pending-reset distinction, exposes plain copy and no
action callback. The candidate view explicitly says status checking is unavailable.
It is not wired into startup or runtime error handling and cannot pause sync by
itself. Activation must bind writer quiescence and this blocking state before the
new sync ships. No button pretends a recovery path exists. Native compile/tests,
recovery execution and visual pixels are UNRUN, so this is not UI qualification. Backend staging results
for PT409 alone do not qualify this user-facing state.
