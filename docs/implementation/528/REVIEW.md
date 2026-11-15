# #528 account-generation migration review packet

Branch-only draft on main 1015437a. No deployment or production connection.
Owning issue: https://github.com/melusi-k/ate-ios/issues/528

## Files and wire contract

- supabase/migrations/20261113063400_account_data_generation.sql: timestamped
  migration in the existing repository format, explicit transaction.
- supabase/rollback/20261113063400_account_data_generation.sql: guarded reverse
  schema path, NOT erased-row restoration.
- supabase/tests/528_account_data_generation.sql: isolated database role/SQLSTATE/
  ownership/idempotence fixtures, rolled back.
- scripts/tests/test_528_migration_contract.py: static contract checks only.

The migration promotes the existing candidate protocol in
  docs/implementation/clear-all/account_data_reset.sql,
with stricter invalid input checks, bounded bigint reset, retry request/generation
pair validation, conditional server LWW and executable environment guards. It does not imply that the candidate document was an approval.

account_data_generation has one auth.users-linked owner row, nonnegative bigint
reset generation and latest request UUID. Existing user_recipes rows receive
nonnullable data_generation=0; account deletion cascades remain. RLS is enabled on
the generation table with no client policy/grant. Existing user_recipes select-own
RLS remains. Direct INSERT/UPDATE/DELETE privilege is removed from PUBLIC, anon and
authenticated, and owner write policies are removed: a NEW column comparison alone
cannot distinguish a stale client overwriting a fresh row.

Only three authenticated SECURITY DEFINER RPCs expose the protocol, pinned empty
search_path and auth.uid()-derived owner. PUBLIC/anon function execute is revoked.
- account_data_snapshot(): JSON generation plus full-shape rows from the same
  account lock; matches AccountDataResetService's strict DTO. No separate epoch GET.
- put_user_recipe(p_caller_generation,p_kind,p_id,p_data,p_updated_at,p_deleted):
  explicit original caller generation required; recipe/shopping and tombstones only.
- clear_account_data(request_id,expected_generation): exclusive account row lock,
  one generation increment plus physical owner-row deletion in one transaction.
  Latest identical request+expected pair returns exactly expected+1. A prior request
  cannot erase new data after another reset. Overflow/invalid inputs refuse.

SQLSTATE PT409=stale generation, 42501=auth/owner, 22023=invalid request, matching
native mappings. Missing RPC remains PGRST202/404 and must block signed-in admission.
Native stages 1-6 preserve original lease/receipt/session across snapshot awaits;
they do not adopt generation zero when this contract is missing. Snapshot rows
contain recipe/shopping only; this SQL does NOT claim Journal/Health cloud sync.

## Deployment gates and old clients

This is intentionally NOT deployable without coordinated rollout approval. Revokes
break existing direct-table-write iPhone/watch clients; do not deploy merely because
the additive functions exist. Before deployment: inventory installed iOS/watch
versions, land generation-aware sync/admission and update-required UX, enforce an
old-client minimum/update plan, then stage privilege cutover. Shipping RPC clients
before revokes is a compatibility phase, not reset safety: no reset may be offered
while old direct-write clients can resurrect records. An additive-only migration
must never be labelled the completed reset fence.

The migration now ends with an executable fail-closed environment guard. It
requires a known migration/definer owner from the delete-fence allowlist, checks
all definer owners and effective client EXECUTE privileges, rejects client
membership of privileged roles, checks effective inherited/table/column write
privileges, and rejects direct generation access. It creates synthetic auth/user
recipe fixtures, deletes the auth user as the actual migration role, and verifies
both cascades actually complete. Any failure aborts the migration transaction.
This is not a production check performed by the author. It is executable staging
and eventual approved-cutover behavior. The cascade probe can fire auth.users
hooks and thus is itself subject to rollout approval, despite using no personal
data. The required auth-admin role-existence guard is retained. No role elevation
or SET ROLE supabase_auth_admin is attempted.

Schema/table/trigger locks can block writes during migration. Estimate table size,
lock duration and maintenance window in staging. No larger timeout or paid service
is proposed. Shared recipes, billing, telemetry, account identity and subscriptions
are not reset by these functions.

## Server-arbitrated LWW and snapshot scope

The Product Owner/Instinct proposal under the owner's technical-decision grant:
newer updated_at wins. At equal updated_at a tombstone wins over live; otherwise
retain the existing server row, with no JSON payload comparison. Arrival order
on the server arbitrates equal-time live/live differences. A successful ignored
put is not proof the local value won: clients must pull authoritative state.

SyncMerge adopts remote state at equal stamps, including live vs local tombstone,
and never pushes an equal-stamp local record over it. This means unsent local
equal-time tombstones also lose to a fetched live row; they require a newer edit
stamp to be sent. Once a tombstone reaches the server at equal time, subsequent
live writes at that time cannot resurrect it. No global deterministic ordering
across independent server histories is claimed. Reset fencing runs before LWW.

Snapshot takes a shared account lock and reads rows with one SQL aggregate: it
excludes reset, not concurrent same-generation writes. It is a statement-consistent
row set with a stable generation, not an exclusive full-write freeze.

## Required database verification, UNRUN

1. Apply existing migrations then this one in fresh isolated Supabase/Postgres.
   Run the SQL fixture with ON_ERROR_STOP. Verify RLS and effective privileges as
   anon/authenticated/service and cross-owner select, not only as postgres.
2. Two actual authenticated connections for one synthetic owner: A holds FOR SHARE
   generation row and writes; B reset must wait. Commit A, B returns generation+1
   and deletes rows; A's old-generation retry must fail PT409. Reverse order too:
   B holds FOR UPDATE during reset; A put waits then rejects stale epoch.
3. Concurrent identical reset UUID requests return one increment. Different UUIDs
   using old expected epoch cannot delete newly written rows. Retry with same UUID
   but wrong expected generation must fail. Snapshot/reset concurrency never pairs
   old rows with a new generation. Test independent owners do not block each other.
4. Kill connection after reset commit before response. Retry original UUID/epoch
   and verify one increment. Exercise generation bigint maximum and malformed/null
   parameters. Verify tombstones and original owner isolation.
5. Auth-user deletion cascade through trigger must succeed for the migration role;
   separately qualify the actual GoTrue/auth-admin deletion path in staging;
   authenticated direct delete/update/insert must fail, even forged config flags.
6. Rollback only in isolated pre-reset state: verify restores exact old policies and
   schema. After any reset, rollback script MUST refuse. Prefer forward fix after
   rollout. A schema rollback cannot restore erased personal bytes and must never
   lower generations or re-enable stale clients as recovery.
7. Contract smoke from actual client DTOs and generation-fenced sync plus startup,
   reset lost-response, receipt handoff, archive and sign-in transitions. Backend
   success alone does not qualify local activation or full account reset surfaces.

## Evidence and rollback

Two static contract tests PASS; full Python suite rerun reported with packet; git diff --check PASS. psql client exists but no local server/initdb/Supabase
runtime is available, so SQL execution, grants/RLS, two-session concurrency and all
native/live-contract tests are UNRUN. No production Supabase reads/writes, migration
apply, server deployment, remote push or PR publication occurred.

Rollback file first locks both tables and refuses if generation is nonzero or any
reset request exists. Pre-reset rollback removes new objects and restores precisely
the existing owner write policies/grants. After a reset, retain generation/request
evidence and forward-repair; do not drop it or re-enable direct writes. This is a
review packet, not an instruction to run either SQL file.

## v4 client convergence and free SQL lane draft

AnyJSON/JSONValue numeric transport remains unchanged (Double). The v3 Decimal
change and all canonical key code are removed. Swift tests cover adopting remote
live payload in both orders, remote tombstone, remote live over a local tombstone,
and no equal-stamp push. SQL tests cover delayed older write, retaining first server
payload in both arrival orders, and tombstone precedence in both orders. Swift
compile/tests and actual SQL execution are UNRUN here.

.github/workflows/account-generation-sql-draft.yml is a manual-only free hosted
runner lane using disposable postgres:16 and minimal auth.uid/users/role shims.
It applies the real user_recipes baseline, proposed migration and fixtures. It
has NOT been published, triggered or run. It does not model GoTrue/PostgREST JWT
validation, schema cache, real Supabase grants/inheritance, hooks, installed clients,
concurrency or deployment environment. Passing it is SQL smoke proof only, not
production approval. No credentials or project secrets are used.

## v5 real staging role correction

Reviewer-provided staging apply log records SQLSTATE42501 at SET ROLE
supabase_auth_admin on v4; transaction rollback left only the baseline table.
The real postgres migration role is not a member of supabase_auth_admin or
supabase_admin. The disposable superuser shim did not expose that restriction.

v5 retains the real auth.users DELETE/cascade probe in the migration but performs
it directly as the migration role, one of the already-checked delete-fence roles.
This is an actual DELETE, not an ACL-only check. No ownership, effective grant,
column/inherited bypass, allowlist or cascade-presence guard was removed. This
proves only that role's path. GoTrue's actual auth-admin deletion path still needs
separate staging qualification; migration success must not imply it passed.
The copied bypass-test guard matches the migration again. Author has not applied
v5 to any database. Reviewer must reapply to staging; production remains untouched.

## v6 permanent generation conflict HTTP response

Reviewer reports v5 real staging passed GoTrue sign-in, JWT isolation, anon denial,
two-connection fencing and GoTrue admin deletion cascade. Two stale-generation
HTTP puts did not return within15 seconds. Supabase documents PostgREST14's infinite
transaction retry behavior for custom SQLSTATE40001 exceptions:
https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b

All four migration conflict raises now use PT409, including the table trigger,
put, reset retry mismatch and reset epoch mismatch. The older candidate SQL doc
is updated too; no other SQL RPC raises class40 anywhere in the repository.
Client mapping recognizes PT409 as staleGeneration. Generic40001 is NOT mapped to
permanent stale state: it may represent a real transient serialization failure.
Tests exercise PT409 over put, snapshot and clear with exactly one transport call,
and distinguish a generic40001 response. SQL expectations use PT409. No timeout
increase or retry was added. Swift and SQL tests remain UNRUN by this author.

Reviewer should reapply this candidate to staging then verify stale put and reset
conflicts return HTTP409 with body code PT409 inside the existing request budget,
including no row mutation and no continuing repeated backend error stream. The KB
notes that already-looping requests may need separate operator cleanup; changing
SQL alone does not stop those in-flight loops. No cleanup/termination is authorized
or performed by this packet. Production remains untouched.
