# Production Food Journal activation candidate

Consolidated qualification branch based on main1015437a. The production flag stays
OFF. The source-reviewed owner is included for exact-head native qualification,
not activated for users. Do not activate until native gates pass and a separate
activation decision is recorded.
No backend operation, SQL deployment, CI dispatch or installation was performed.

## Startup and ownership

AteApp returns before StoreRecovery/AppStore/TimerCenter construction on the
production path. FoodJournalApplicationOwner installs unowned shared-write refusal
once; resumes durable local-action or account-reset control using unopened raw
inventory; then snapshots/reconciles with the actual account service before
opening, binding and publishing the complete graph. Full session, receipt and
original lease remain load-bearing throughout. Malformed/inaccessible keychain
session is not treated as signed out. Existing signed-in contract is probed live by
the application; a failed/unknown probe blocks, with no legacy/offline fallback.

No App Group uses explicit app-only control/Covers/Inbox paths. Present-but-invalid
control does not trigger fallback. Mode is a typed diagnostic event; app-only Live
Activities and watch activation stay inert. Shared and app-only modes use the same
reset/receipt/archive gate discipline. Existing root UI is preserved for hermetic
UI-test fixtures; those fixtures do not qualify this production startup path.

Every ordinary AppStore is constructed under its admitted writer effect, with the
actual runtime, immutable DraftStore, timer boundary, per-store CoverStore, per-store
InsightsModel and generation-aware sync transport. Service callbacks capture that
owner. Async generation, spread parsing, draft repair and Health loads register
actual task completion and recheck after awaits. CookPlan's ordered OS queue closes
and drains as a lifecycle participant. Widget defaults operations explicitly use
the store's captured shared boundary. Old UI cannot obtain replacement covers or
Health context through mutable singletons.

## Replacement and destructive actions

The root changes to checking, removes the complete editor tree and awaits its real
onDisappear before quiescence. Session refresh dispatches the transition outside
its own consumer. Auth, import and reset replace/re-admit the full root. Password
recovery preserves the new-password intent. Failed post-retirement work keeps the
root closed; malformed archive input before retirement leaves the old root active.

Clear all uses the actual durable account-wide coordinator, exact raw/retained
inventory, receipt handoff and real OS cleanup. Cook-plan defaults are included.
System dependencies are instantiated lazily only after local erase during startup
resume. Diagnostic/Beta retained caches are cleared so later writes cannot restore
old personal notes. Settings describes account-wide scope and retained account/
subscription, rather than a library-only reset.

Sign-out-remove and delete-account use durable local-action control. Local erase
is resumable before ordinary opens, including after credentials were removed.
Delete first persists deleteRequested, then calls the real auth deletion API; only
a verified response advances to localErase. A lost delete response remains blocked
rather than automatically replaying remote deletion or guessing success. Minimal
control remains for support/recovery. Ordinary sign-out retains local receipt/data.
Account switching to foreign retained ownership remains fail-closed; it does not
silently adopt or wipe another account's local bytes.

## Archive association limitation

Canonical diary binds the real association store under its owner boundary. Existing
nonempty/corrupt links still cause the retained import/export services to refuse,
since this archive format cannot preserve them. No links are discarded or hidden.
Settings says this plainly. Product routing assigns link-aware archive format to a
separate follow-up; this candidate does not claim that work is complete.

## Verification and remaining gates

V2: 216 Python source tests PASS and diff check PASS. Changed/new Swift syntax
is grammar checked, with identical pre-existing parser-only errors in the C flock
symbol declarations and the watch's multiple catch patterns. This is NOT a Swift
compile/typecheck result. The required native method manifest is now 101 (95 in
v1), with actual provider-after-reset, ordered OS close/drain and cancel, unresolved
submission refusal, strict watch snapshot and extension-entry tests added. Native compile/typecheck/tests UNRUN. Grammar parsing is not
compilation. Full production startup, reset/resume/crash, editor dismissal, auth
callback, app-only/shared mode, OS service and UI/pixel journeys require independent
native execution. Existing QA fixture passes cannot substitute for these gates.

No screenshot or visual acceptance is claimed. Reviewer owns source review,
publication, exact-head native CI, production-path simulator evidence and final
acceptance. This candidate's closure/OS-crash semantics require that review before
shipping; source approval and the OFF qualification candidate are not a release decision.

## v2 startup refresh correction

Expired saved sessions refresh before any personal open. No flock is held across
the auth network request. Before persistence, the short gate rechecks original
full session, exact keychain bytes, control bytes and receipt. Owner mismatch or
any concurrent change blocks. Durable local-action resume does not refresh a
possibly deleted account; its control phase determines whether local cleanup is
safe. The draft-repair final apply also rechecks this owner's validator.


## v2 extension processes and OS ordering

WidgetBundle and share startup install a fail-closed extension boundary provider.
Intent-only .appex launches bootstrap at the shared writer entry too. Each new
entry captures its own admitted epoch; a captured reference remains old across
awaits and cannot rebind to a replacement epoch. Missing group/control doubt
refuses, never legacy. A later independent entry can recover after reset completes.
Heartbeat defaults are gated. App-only shares are inert (no clipboard bypass).

The actual share image helper captures before NSItemProvider loads, gates BOTH
Inbox directory and personal image bytes after the await, and final queue/saved
publication uses the original boundary. Its delayed-provider XCTest performs an
actual epoch rotation and asserts no late file or directory exists, then checks a
new entry can save. No NSItemProvider/real extension UI journey has run here.

TimerCenter owns an ordered awaited notification queue, registered for close and
drain before cleanup. Pausing/stopping is ordered after an earlier in-flight add.
Extension timer effects create a durable NONPERSONAL submission token under the
same shared writer flock before OS submission; every add is awaited. Tokens exclude
other timer submissions and prevent account reset AND auth epoch invalidation
before the OS add resolves. No writer flock spans an await. Existing 300ms removal
settle is unchanged. The application still verifies OS removal after draining.

A terminated extension can leave an unresolved OS-submission token. This is an
explicit fail-closed recovery LIMIT: reset/auth rotation remain blocked, and simply
reopening does not prove it safe to remove that token. There is no automatic token
expiry, retry, assumed cancellation, or claimed erase success. Native qualification
must review this support/recovery path before publication.

Watch runs on a different device and cannot share the phone flock. Its production
store and timer store now use real watch epochs. Shopping writes use only an
original pre-edit account snapshot generation and exact full-session checks with
put_user_recipe; no direct user_recipes POST or late generation adoption. Snapshots
are strict and owner-scoped. This is not a claim that offline watch bytes or wrist
timers are synchronously erased by a phone reset; paired-device convergence and
native watch journeys remain unqualified. Food Journal remains LOCAL-ONLY.

## Native separate-process fixture (UNRUN)

On macOS: `python3 scripts/native/test-food-journal-process-gate.py`. It compiles the
actual app/shared gates and archive nesting implementation into a native helper,
then runs distinct writer and reset processes. A captured writer attempts personal
image creation while the reset flock is held AND after release/epoch rotation;
both must refuse with no bytes. This is a real process test, not two objects in an
iOS XCTest. It has not run here. It does NOT replace production-path iOS startup,
shared/sideload, widget/share/AppIntent, OS service or watch qualification.

## v3 watch ownership correction

WatchStore now owns WatchOwnedContent as the only recipes/shopping state. Every
session/token transition invalidates the watch epoch and clears displayed rows,
snapshot generation and local UI provenance before publishing a new identity.
Owner changes replace the disk cache with empty owner-bound content first;
sign-out removes it. A failed cache replacement leaves memory revoked and public
WatchStore signed out. Cache v2 carries its owner and format; legacy ownerless,
corrupt, foreign-owner or signed-out bytes are never displayed/adopted. Startup
cache reads can restore same-owner display only, never generation/write authority.
A same-owner token refresh conservatively drops the current in-memory view until
its new snapshot completes; it does not adopt an old UI closure as a new action.

Snapshots retain strict owner proof through publication. Each live shopping item
carries a local snapshot UUID, not a server payload field. Before either local
optimistic change or RPC, the item must exactly match the current snapshot member,
its provenance, full session and captured generation. Each edit advances provenance
for the whole view. Replacement snapshots with identical IDs, values and even the
same server generation still reject a retained old item. After token/network awaits,
full session/generation/revision are rechecked; stale requests cannot clear a new
owner's state or publish old status. Cache-loaded rows have no live provenance.

Four native WatchOwnedContent tests exercise the actual production seam and real
temporary files: A->B with failed/no refresh and restart; ownerless and same-owner
offline cache cannot authorize toggles; cross-owner/identical-replacement retained
items and token rotation; and cache replacement failure still revokes old rows and
captures. No network mocks or backend writes are involved. Required native names
101 -> 105. Python 217 PASS, changed Swift grammar checked (only the unchanged
watch multi-pattern catch parser limitation), diff PASS. Native compilation,
watchOS/iOS XCTest execution and paired-device UI evidence remain UNRUN.
