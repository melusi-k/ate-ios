# Production forward reconciliation candidate

No production action performed. New migration:
`supabase/migrations/20261113064000_reconcile_account_data_contract.sql`.

## Grounding and scope

Targets the existing contract in the Reviewer's read-only production capture on
2026-11-13 around08:11-08:13 SAST, following recorded migrations20261113042539 and
20261113042557. Live function capture and both recorded SQL files are preserved as
isolated-test fixtures. Their provenance is the owner's supplied Reviewer attachments,
not a claim of current live state. Reviewer must recheck current definitions before
applying anything.

Observed sources:
- https://supabase.com/dashboard/project/ploncuhexmwydjxljuhe/database/migrations
- https://supabase.com/dashboard/project/ploncuhexmwydjxljuhe/sql/new
- Retry hazard reference: https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b

This is NOT create-only v6 and does not reconcile the migration ledger by pretending
v6 was previously applied. Do NOT run the repository's entire pending migration chain
against this production schema: its earlier v6 create-only file will collide with the
already-created objects. Apply/record only this reviewed forward SQL through the
qualified operator/runner plan. Never delete history to make a migration tool happy.

## Exact change

Only three existing bodies are replaced via CREATE OR REPLACE with the same signature,
return type, owner semantics, security-definer setting and empty search_path:

- enforce_account_data_generation: permanent mismatch raisesPT409.
- put_user_recipe: validates nonnegative/non-null generation, recipe/shopping kind,
  nonempty/non-null id, nonnegative/non-null timestamp, non-null deleted, and non-null
  SQL data for live rows; PT409 on stale generation. Upsert changes a row only for a
  newer timestamp or an equal-timestamp tombstone replacing a live row. All other equal
  writes retain existing server payload. Existing table JSON/data-size constraints stay.
- clear_account_data: sameUUID retry returns only when current==expected+1, guarded
  against bigint overflow; other sameUUID retry isPT409. New request at max bigint is
  rejected22023; mismatched expected generation isPT409. Existing owner/update lock,
  receipt and owner-row erase behavior remain for FUTURE explicit reset RPC calls.

These bodies are exact v6-qualified body text, not a new data-format policy. In
particular data remains arbitrary JSONB subject to the existing size constraint;
this does not introduce object-only validation or silently normalize existing rows.
SQL NULL is allowed for tombstones, not live records. No table, row, current receipt,
trigger, policy, grant or existing snapshot/delete-fence body changes during migration.
The migration itself never calls reset, creates an identity, inserts/deletes fixture
rows, scans personal payloads, repairs ACLs or drops objects.

Preflight refuses drift in postgres/no-user-JWT context, owners, RLS, effective
table/column/client-role/function privileges and exact enabled trigger bindings.
Inside one transaction it snapshots and verifies all five function OIDs/ACLs/owners/
security config plus table ACL/owner/RLS and untouched snapshot/delete-fence definitions.
A mismatch aborts the transaction. CREATE OR REPLACE is rerunnable; schema-cache NOTIFY
is transactional and follows successful checks. No weaker rollback script is supplied.

## Validation status

-195 Python/static tests PASS, including four added reconciliation structure tests.
- PostgreSQL SQL parser and PL/pgSQL parser accept the outer migration and all three
  replacement bodies. These are parser checks, NOT execution against a database.
- Disposable fixture SQL/parser checks PASS. Real PostgreSQL fixture execution,
  PostgREST HTTP behavior, concurrent sessions and real GoTrue cascade are UNRUN here.
  Only PostgreSQL client programs are installed, no disposable local server.

For a brand-new disposable LOCAL database, run as local postgres:

```sh
psql "$ISOLATED_TEST_DSN" -v ON_ERROR_STOP=1 -f supabase/tests/528_reconciliation.sql
```

Never use a production DSN for that test. It creates role/auth/schema fixtures, installs
the two recorded prior migrations, seeds generation7 and a personal-byte stand-in,
then applies reconciliation TWICE and checks exact logical row/generation values,
function OIDs and ACLs unchanged. It runs the existing reset/LWW/isolation/ACL suite,
then additional validation/PT409-trigger/sameUUID/max-bigint tests with rollback.
The service_role default grant in that isolated fixture models captured Supabase
privileges; it is deliberately absent from the production migration.

## Reviewer execution gates

Keep the owner's current production confirmation, backup decision and actual cutover
plan separate from this branch-only packet. Recheck live definitions/schema/grants;
qualify isolated SQL and exact production-compatible role/cascade behavior; inspect
the final SQL hash; ensure API/writer quiescence for the cutover and verified runner
receipt/ledger/recovery route. Do not provoke a known stale40001 RPC on production as
preflight. After application verify saved definitions containPT409/LWW/retry guards,
unchanged effective privileges and successful schema-cache reload. Synthetic reset
or account deletion is a separate authorized action with irreversible effects, not
an implicit migration smoke test. Full app activation stays OFF until its graph,
auth/writer/reset/conflict qualification is complete.
