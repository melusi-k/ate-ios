# Food Journal: backend-first deployment review

Decision requested: approve or decline the production v6 database cutover below.
This document is a plan only. No production access, migration, deployment or app
activation has occurred in preparing it. Backend-first was selected; that is not
the final deploy approval. Reviewer owns publication and execution after approval.

## The decision that matters

The exact v6 migration is a BREAKING cloud-write cutover for old app builds. It is
not additive-only. Old builds keep local features and owner-scoped cloud reads,
but their recipe/shopping cloud writes fail after privileges are revoked. They do
not have update-required UX. They may show generic sync failure and retain local
unsynced edits. Backend-first therefore means an intentional cloud-write gap until
the generation-aware app is shipped and safely activated. It does not turn on Food
Journal, cloud Journal storage, account reset UX or safe old-device recovery.

Do not approve with the expectation old builds keep full cloud sync. If a gap is
unacceptable, STOP: choose a separately reviewed additive compatibility migration
and postpone the revocation/reset fence. Do not silently edit v6 or call that
alternative the completed reset contract. No reset may be exposed while old direct
writes remain allowed. An accepted backend-first order does not choose between
these compatibility tradeoffs without this disclosure.

The migration's own header says "Do NOT deploy independently of reset-aware
clients + rollout/recovery UX" and says old clients must show update-required.
Backend-first with the accepted cloud-write gap is an owner-approved exception to
that sequencing contract, NOT evidence those client conditions are met. The SQL
header is unchanged. Record that exception in the deployment receipt before any
production apply; the remaining safety guards are not waived.

## 1. Old-build rollout plan

| Existing behavior | After exact v6 cutover |
| --- | --- |
| Local recipe/shopping edits | Stay local; old builds cannot upload them |
| Owner cloud SELECT/pull | Existing select-own policy retained |
| Cloud INSERT/UPDATE/DELETE | Denied, including stale-device direct writes |
| Sign-in/auth/account identity | Not changed by migration |
| Published/shared recipes | Not changed by migration |
| Legacy Clear all button | Existing local clearLibrary flow, NOT new account RPC |
| Local diary, Journal, Health, timers | Not activated or migrated by this SQL |
| Old-device update-required screen | Missing today; cannot promise it remotely |

Before approving: inventory actual supported installed iOS/watch versions and
accounts/devices using cloud sync. This has not been done in production here.
Notify affected people through an approved communication scope, naming the cloud
write interruption and local-only edits. If audience/address approval is absent,
prepare the notice for owner review rather than sending it. Do not advise exporting
or uploading extra personal backups as an automatic reset workaround.

Do not restore old direct writes merely to make an old build look healthy after
any reset. That can resurrect erased data. Do not bump old rows to a new generation.
Upgrade activation must preserve older local work only under its reviewed adoption
policy, not automatically upload it. An unupgraded device may keep old local bytes;
backend reset does not remotely erase that device or its offline personal backups.

## 2. Exact production v6 deployment steps

### A. Freeze and verify the approved source, without touching production yet

1. Reviewer confirms the destination commit containing this exact v6 content.
   Source packet commit:841c14ee1975949dc1542bf24b0f4795ef089354.
   Migration: supabase/migrations/20261113063400_account_data_generation.sql
   SHA256:a129712b01abf2a08b7ae544cd5870d6375694ad90904f3575b862e72f9aa75d
   Rollback: supabase/rollback/20261113063400_account_data_generation.sql
   SHA256:96a574092b7994e442f59869c393294361db817199e81b759be5d11fa119830b
   Confirm those bytes using sha256sum from the destination checkout. Do not deploy
   a moving branch or guessed local SQL. No SQL changes are included in this runbook.
2. Pin real staging proof to hosted v6 bb4b0ce7 and the reviewed v6 SQL hash above.
   Reviewer supplied http-verbatim-f2e790ef.log: stale put0.140s, stale reset0.107s,
   wrong-retry0.105s, all HTTP409/PT409, unchanged rows; real GoTrue admin delete
   HTTP200. Earlier real staging also passed JWT isolation, anon denial and
   two-connection fencing. Preserve the supplied log as evidence; do not substitute
   the disposable shim smoke. Confirm the hosted destination's migration bytes
   match the SHA256 before relying on it for production.
3. Confirm free project/CI use and supported maintenance route. Do not buy a backup,
   tier, paid CI, or larger timeout. Determine actual existing provider recovery
   support; this packet has not established production backup/PITR availability.
4. Owner gives final explicit yes/no after reading the old-build consequence and
   rollback limit. Record approved target, exact source/hash, execution window and
   chosen operator. No production credentials in chat or this document.
   "Deploy when ready" permits execution only after the following gates are filled:
   - [ ] Runner: name the actual operator and approved supported migration runner;
     record how it targets ONLY this file and records the migration ledger. If psql
     is selected, name the supported ledger reconciliation route before applying.
   - [ ] Recovery: name the verified available restore/recovery mechanism, who can
     use it and what it costs. If no pre-cutover recovery route exists, explicitly
     escalate that fact rather than assuming free PITR or proceeding silently.
   - [ ] Quiescence: name the actual mechanism and start/end evidence that prevent
     app/operator writes during schema work. Old apps have no remote kill switch;
     if only the DDL lock is available, obtain explicit acceptance of that strategy
     and its lock/interruption risk before calling it a maintenance plan.
   - [ ] Exception: retain owner's backend-first/old-build-write-gap approval and
     the migration-header exception in the nonpersonal execution receipt.
   Blank boxes are blockers, not post-deploy follow-ups.

### B. Approved operator's production preflight, after that yes

5. Independently bind the selected project to the production app's actual Supabase
   URL/project identity. Distinguish it from staging using authenticated project
   inventory and app configuration, not similar project names. Pause if mismatch.
6. Inspect live schema/migration ledger, table policies/grants/function ownership,
   inherited/column privileges, role membership, auth.users triggers/hooks and
   existing RPC signatures. Original report said new objects absent, but recheck
   now. STOP if any candidate object already exists, baseline schema differs or
   privileges are broader than reviewed. Do not use CREATE OR REPLACE as a repair.
7. Verify the executing role is the actual allowed migration owner and can DELETE
   its synthetic auth.users probe. v5 removed forbidden SET ROLE auth-admin;
   no elevation is required or allowed. Keep all fail-closed guards intact.
8. Establish maintenance/write quiescence using a verified operational mechanism.
   Old apps have no new remote kill switch in this packet. If active writes cannot
   be quiesced or an acceptable interruption window is not established, stop and
   resolve it with owner, not a longer lock timeout. Record the real table size and
   lock-risk review. Do not promise instant DDL.
9. Record nonpersonal pre-state evidence: object existence, constraints, policies,
   effective privileges, function definitions/owners and ledger state. Do not dump
   private row payloads into logs/artifacts. Confirm recovery route and rollback
   limits before executing. No full-table erase or synthetic reset of a real user.

### C. Apply only the reviewed migration

10. Use the established migration runner against the verified production connection
    to apply ONLY the reviewed v6 file, with stop-on-error. The file has its own
    BEGIN/COMMIT and schema-cache notification; do not wrap a partial selection,
    strip guards, auto-retry failures or push all unrelated pending migrations.
    If using the operator's approved psql connection, the exact SQL invocation is:

        psql "$APPROVED_PRODUCTION_CONNECTION" -v ON_ERROR_STOP=1 \
          -f supabase/migrations/20261113063400_account_data_generation.sql

    The connection must be supplied through the approved secret mechanism and not
    echoed/saved to artifacts. This command is documented, NOT executed here.
11. Capture success/failure and reviewed source/hash/time. Migration guard creates
    and deletes synthetic auth/user recipe rows; those hooks are real side effects
    covered by the final deploy scope. Any error must stop. Verify transaction
    rollback through live state instead of assuming no objects landed. Do not retry
    or manually patch production around a guard failure. Surface the exact blocker.
12. If using psql outside the normal migration runner, reconcile the migration ledger
    using its supported mechanism only after confirmed success. No guessed ledger
    insert is supplied here; existing project's runner determines that operation.
    A ledger mark is not execution proof and execution without ledger is not a
    finished deployment. Resolve this runner choice in step4 before beginning.

### D. Verify and hold app activation

13. Re-read actual objects, owners, RLS and effective privileges; verify direct
    authenticated writes denied, authenticated RPC execute allowed, anon denied.
    Verify PostgREST schema cache exposes exact parameter names and snapshot shape.
14. Through a separately approved synthetic test account only, check snapshot/put,
    reset/idempotent retry, stale put/reset HTTP409 body PT409, no old-data resurrection,
    cross-owner isolation, and actual GoTrue-admin deletion cascade. Do not reset or
    inspect real-user payloads to test. Do not run the isolated rollback/grant-bypass
    SQL fixture against production. Never grant its deliberately unsafe privileges.
15. Check that legacy writes fail as disclosed and old owner SELECT still works.
    Report downtime/write-gap reality and migration evidence. Leave Food Journal
    activation and new Clear all UI OFF pending the entire list in section4.
    Continue only the bounded deployment follow-up, not an unapproved standing watch.

## 3. Rollback and stop conditions

- A failed migration transaction: inspect state and ledger first. Do not automatically
  rerun; a lost connection can leave commit uncertain. Determine what landed.
- Successful migration, NO reset ever committed: disable/quiesce all new RPC clients
  first, then verify the generation/control state. The reviewed rollback script
  takes exclusive locks and refuses any nonzero generation or reset request. Only
  with final operator/owner-approved reversal run it stop-on-error, then verify old
  policies/grants/columns/functions and ledger match the intended baseline.
- ANY reset committed, INCLUDING the step14 synthetic production smoke reset:
  do NOT run schema rollback or restore old direct writes.
  Preserve generation/request evidence and forward-fix while writes stay fenced.
  Do not restore deleted personal rows from backup as an incidental repair. Erased
  data is not recovered by dropping the schema; this is not a data-restore script.
- Unknown outcome: stay blocked. Never guess success or reset generation zero.
- PT409 is permanent conflict, not transport retry. Earlier PostgREST14 looping
  requests need separately scoped operator investigation; updating SQL does not
  stop an already-running backend. No broad terminate-all operation is approved.

Before the first production reset, persist a nonpersonal durable execution receipt
outside auth.users/account_data_generation/user_recipes and all deletable personal
reset rows. Record deployment/source/hash/operator/time, whether any production
reset (including synthetic smoke) committed, and verification outcome. The approved
operator must name and verify this durable restricted execution-record destination
before step14; it must not contain tokens, account payloads or personal fixture data.
Do not rely on generation-table emptiness as "no reset ever": deleting the synthetic
user cascades away its generation evidence. The outside receipt remains authoritative
for the no-rollback boundary even after every synthetic fixture is deleted. Unknown
receipt/history means stop and forward-repair, not assume rollback is safe.

Rollback is therefore reversible schema cutover only before the first reset, not
an unconditional undo button. Record the first-reset boundary when eventually
activating reset UX. Branches/source PRs stay until destination commit confirmed.

## 4. Activation wiring and evidence gate (separate work, not deployed by SQL)

- Integrate the reviewed FoodJournalAppGraph/ProductionAdmission/DiskResources
  stage1-6 graph, on current main, with exact-head native proof. Do not just flip
  AteApp's constructor. Resources must retain original lease/gate, strict disk
  access, actual Journal/goals/defaults and one archive/reset participant graph.
- Provision immutable shared paths and minimal generation/control/receipt storage;
  complete lazy startup before ordinary StoreRecovery, AppStore.load, migration,
  seed, timers/watch, widget/intent tasks or personal reads/writes begin.
- Replace legacy SupabaseSync direct POST with GenerationFencedSync and atomic
  snapshot admission. Every write keeps the original captured owner/generation;
  no generation-zero fallback, no epoch promotion of old bytes, no retry-on-PT409.
- Persist and validate receipt ownership and remote generation at existing-install
  adoption. No-receipt/advanced-epoch devices block rather than resurrect old data.
- On session refresh/sign-in/sign-out/account switch, quiesce writers, rotate actual
  durable epoch and remount the admitted graph. Cancellation alone is not a fence.
- Install the same writer boundary in app, widgets, share/intent extensions, cover
  completions, notifications, deferred widget/index writes, watch bridge and Live
  Activities. Await pending effects before cleanup; qualify watch wipe acknowledgement.
- Bind Settings Clear all to the real coordinator, correct account-wide disclosure,
  online authentication, retained same-UUID control, cloud receipt and complete
  local reset inventory: Journal/diary/goals/settings/recipes/shopping/covers/session,
  migration/adoption/recovery/archive bytes, timers/plans/notifications, widgets,
  Spotlight/watch/activities. Minimal nonpersonal control may remain; personal
  backup/recovery bytes may not silently survive an account-wide reset.
- Bind separate conflict packet fb10298f AccountGenerationConflictState/View to
  runtime put/snapshot failures AND startup reconciliation, after stopping writers.
  Keep staleLocalData distinct from pendingResetUnverified/unknown response. It is
  only an unmounted candidate today; its words alone do not pause sync.
- No recovery button until its actual owner/session/receipt-checked status read,
  quiescence, reconciliation and fresh graph remount exist. Never call legacy Sync
  now behind it. No fresh Clear all UUID, automatic retry or destructive discard
  from conflict. Blocking state and retained evidence must survive relaunch.
- Verify archive actual-consumer counts, import/export/settings goals bindings and
  complete reset compensation. Native normal-text, pixels, actual consumer and
  extension/device proof remain required; static Python passes are not these proofs.

Activation requires its own final release review after backend proof, user-facing
recovery behavior and current-head tests. Backend deploy approval is not activation
approval. No production readiness claim follows merely from this runbook.
