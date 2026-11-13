# Slice1: dormant standalone recipe/shopping admission owner

Exact hosted base67ec3bc25fcfaf9865c7865cba5e83b7d528349d,
tree76aa007b9b393ffcfeaa48e86e74e369f6f7df74. Branch-only.

Adds RecipeShoppingSyncOwner: real strict reset-control/receipt/gate construction;
original captured persistent lease; full AuthSession equality before/after awaits;
matching owner/generation receipt required; whole recipe/shopping batch shape and
payload identity validation; one snapshot/push capture; actual admitted writer-effect
API; no direct-table fallback, receipt stamp, erase, reset or account switch.

Deliberately no production constructor/call-site, FoodJournalRuntime, default sync
replacement or UI. Ordinary cloud upload remains NOT API-compatible. This owner is
not ready to wire into AppStore: missing staged syncNow, local revision, read-only
pre-admission load, ordinary/shared writer inventory and auth lifecycle/error route.
Missing receipt refuses even at generation0. Known legacy adoption requires a
separate verified recipe/shopping raw-store and metadata preservation inventory;
this slice does not guess it from diary/goals preservation. Unknown owner and
advanced/regressed generation never stamp or delete. The gate may provision only
its nonpersonal epoch/lock control, not a receipt or personal-data replacement.

All file primitives retain their existing durability/path guards. Caller must supply
the real pre-provisioned shared directory; no app-group-to-standard fallback. Later
factory wiring must resolve it once and use the same directory in all processes.
A new full session requires a new explicitly admitted owner, not a userID-only reuse.
The owner retains capability proof after successful push. Concurrent-cycle refusal
alone preserves the active cycle/proof; missing snapshot, other pull/push failure,
writer-effect failure, cancellation or explicit abandon revokes proof. A new pull
clears prior proof until its response is fully validated. Retained cycle tokens are
checked through adapter validation before/after every network await, preventing
late admission, further puts or reported success after abandonment/cancellation.
No automatic re-admission, generation promotion or implicit partial-upload retry.

Thirteen native tests added, all UNRUN here: missing receipt, advanced generation with
retained fixture bytes/receipt, same-owner token replacement, exact snapshot/put
route for both payload kinds, pending control/foreign owner, malformed live payload,
regressed/foreign snapshot, original lease invalidation and partial stale tombstone
upload. File-byte fixtures are not AppStore pending-edit durability qualification;
that requires the staged syncNow slice. No claim of ordinary-launch integration.

207 existing Python tests PASS; diff-check PASS. No Xcode/native runner available
here. Native compile/tests and all device qualification remain UNRUN. Existing
full-unit lane discovers the new test class; no CI budget/timeout/retry changes.
Reviewer publishes/merges. Source PRs close only after the reviewer confirms the
destination commit; branches kept. Food Journal activation stays OFF.

Reviewer revision: deterministic continuation barriers cover suspended pull and
mid-push abandonment and cancellation, plus concurrent-refusal versus missing
snapshot proof semantics and abandonment after a successful cycle. No sleeps,
timeout increases or changed original test assertions. Native remains UNRUN.
