# Slice2: staged publication, still dormant

Hosted slice1v2 parent:178afa4eddf5a0fe1a602a479c392a72ee52ee2f,
treebe370fa3ad27cef6877342e0704abfdab8ab650c.
Hosted root67ec3bc25fcfaf9865c7865cba5e83b7d528349d. Branch-only.
Do not publish this as a complete API-compatible route.

Changes:
- Pure RecipeShoppingSyncStage prepares both merge results/upload rows without
  mutating caller values. Metadata keeps its original JSON keys via a typealias.
  Existing SyncMerge equal-stamp semantics retained. No dedupe/normalization or
  new clock stamps in the staged path. Missing/invalid pending stamps refuse.
- AppStore recipes, shopping and sync metadata mutations change a UUID local
  revision. Only explicitly injected RecipeShoppingSyncOwner takes the new path.
  Default SupabaseSync/MockSync behavior remains unchanged.
- Snapshot admission precedes staging. Foreign legacy owner refuses with no
  account-switch erase. No meta.userID stamp before successful upload. API failure
  preserves actual AppStore arrays and pending metadata/tombstones.
- After upload, full session, original lease/receipt and local revision must still
  match before publication. A changed revision retains newer local edits and
  reports interrupted, not synced. No automatic retry.
- New throwing local commit uses a separate non-autosaving ModelContext, encodes
  before mutations, catches SwiftData save failure and rolls back that context.
  Defaults metadata gets an immediate readback check. Only then publish arrays,
  snapshots and success. No legacy swallowed save helper is used for this path.
- Successful push keeps admitted capability. Every early return/error abandons it.

Seven new native tests UNRUN: five pure stage tests plus two actual AppStore tests
for recipe/shopping edit+tombstone preservation on stale upload and a deterministic
suspended successful upload that cannot overwrite a newer local edit/report synced.
No sleeps/timeouts; refusal tests use context nil and make no persistence-success
claim.207 Python PASS; diff-check PASS. Native compile/execution UNRUN.

Remaining boundaries:
- No production construction, read-only pre-admission load or shared-writer binding.
- No missing-receipt adoption, raw preservation or implicit account switch.
- Expiring credentials refuse pending the refresh/new-admission lifecycle slice.
  401/403/PT409 user-facing semantics are not yet adapted in this staged path.
- Separate SwiftData/defaults writes are not a crash-atomic combined transaction;
  immediate readback is not fsync/durability proof. A crash between commits still
  needs reconciliation design/testing. Failed local commit is never reported synced.
- No native successful persistence/relaunch qualification yet. Current packet
  deliberately does not claim that intermediate slices meet all acceptance checks.
- AppStore is a focused runtime evidence path: later published combined source needs
  its own hosted-ancestor focus refresh before building. No guard relaxation.

Reviewer alone publishes/merges. Source PRs close only after Reviewer confirms the
destination commit; branches kept. Food Journal OFF; no new UI/activation.
