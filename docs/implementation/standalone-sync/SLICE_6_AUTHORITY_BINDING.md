# Slice6: explicit AppStore durable authority binding

Hosted parent6b72f860c453b4cdf1d9eb8b0842e2deb6acac78,
tree9a6a60246f2034f6c33bdb24be444370a24d7a4c. Hosted rootb670cf1.
Dormant explicit injection only. No ordinary launch switch or shared extension wiring.

RecipeShoppingAuthorityBinding retains admitted owner, original receipt, concrete
commit journal, defaults projection and full session. No guessed default binding.
AppStore binds it before load, disables autosave and uses its isolated defaults and
session. A different live session refuses mutation. No late after-init installation.

The outer ordinary-write seam enters admitted owner/gate, snapshots local arrays,
metadata and snapshots, and commits every changed recipe/shopping/metadata revision
through the durable journal. Nested stamp/persist helpers skip legacy store saves
and sync-defaults writes. Local ordering is preserved; no extra clock or model
normalization is introduced by the binding. On failure, in-memory state is restored,
but retained redo may need replay, so no disk rollback claim. Writer capability is
revoked by owner failure handling, requiring explicit re-admission before replay.

The standalone syncNow branch now requires this exact binding/owner and commits
its staged result through journal, replacing the earlier non-atomic helper entirely.
An unbound explicitly injected standalone service can no longer publish via legacy
SwiftData/defaults helper. Standard production SupabaseSync remains unchanged and
NOT API-compatible; Food Journal remains OFF.

One native on-disk AppStore test UNRUN: local add/shopping stamp+tombstone writes
create durable authority; injected post-intent failure restores visible state and
retains intent; fresh admitted replay installs the recorded local result.207 Python
PASS, diff-check PASS. No native compile/device/relaunch qualification claim.

Remaining blockers before ordinary production construction:
-Startup replay must occur before binding/load; proof cannot be a caller assertion.
-Legacy raw inventory/preservation and unknown/advanced refusal still need factory.
-Shared/extension producers do not yet route through this authority.
-Auth refresh/replacement graph, signed-out local edits, reset inventory and strict
 StoreRecovery opening remain separate slices.
-Existing unbound native stage fixtures still test API refusal/revision paths, not
 a successful unbound commit. Only this explicit binding can publish durably.

Reviewer publishes/merges; source closures require destination confirmation;
branches kept. No UI, production action or activation.

Reviewer v2 data-loss correction: authority-bound load no longer enters the legacy
normalization/dedupe repair path at all. It fetches BOTH complete raw entity sets,
strictly decodes/validates identities and known-owner stamps, then adopts both only
in memory without observer effects. It never runs a full-image repair while shopping
is its default-empty value. Any inventory failure blocks subsequent ordinary writes
and standalone sync without repairing/replacing disk rows. The on-disk fixture now
seeds two duplicate-title recipe identities plus an existing shopping row and stamp,
asserts exact raw image/shopping bytes/stamp unchanged through init, then exercises
the earlier authority/failure/replay path with those sibling records retained.

Reviewer v3 fail-closed correction: authority cook-session load runs only AFTER
both raw inventories verify. Its explicit public entry validates inventory proof,
original admitted owner and authority.defaults, never the legacy nil-journalWriter
path or standard defaults. Failed/refused inventory/authority cannot assign identity.
External publication is permitted only after verified inventory and admitted owner:
no Self.current replacement, widget relay installation or publish scheduling on a
failed authority load. WidgetBridge also rejects direct calls for unready stores.
Fixture seeds a legacy cook session, corrupts a recipe inventory, preserves prior
current and widget publication/relay counters, and asserts bytes unchanged through
construction and explicit loader calls. Separate revoked-owner loader check included.
Native UNRUN,207 Python PASS.
