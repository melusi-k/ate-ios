# #501 disposable local shopping conflict proof

This is a manual proof lane, not evidence of a passing race or a hosted deployment.
It prepares the existing `supabase/review-candidates/shopping_monotonic_sync.sql`
without promoting it into shipping migrations. Existing app sync stays unchanged.

## Running

After #498 data-safety qualification and owner approval to run the free manual CI
lane, publish this branch and dispatch **Local shopping conflict proof** on the
exact reviewed head. It starts a fresh local Supabase project using only the
existing user_recipes schema slice plus a disposable marker. It never runs the
hosted backend-e2e script, links a project, pushes migrations or reads owner keys.
The pinned CLI is Supabase 3.2.0, Python driver psycopg[binary] 3.3.9, database 17.

The Linux runner needs Docker. The app's full migration directory is deliberately
not copied: it contains unrelated hosted features and operational prerequisites.
This test therefore proves the candidate guard against the app's actual table,
ownership policies and PostgREST conflict surface, not all migrations composed.

Two fixture users are created by the local Auth admin endpoint with confirmation
already set and sign in locally; no mail is sent. Two separate database sessions
assume `authenticated` with distinct user claims. The first holds the conflict-row
lock while the second attempts its upsert. A bounded pg_stat_activity barrier
requires an actual lock wait before first commit. No sleep is used as race proof.

Cases: newer first/stale second; stale first/newer second; tombstone versus stale
live row; equal timestamp with tombstone first and live first; PostgREST
`on_conflict=user_id,kind,id` parity; two-user read/write RLS and same-id isolation.
The negative control disables only the candidate trigger and must observe a stale
overwrite with the same real-lock orchestration. Generic errors do not pass that
control. The guard is restored and stale rejection repeated.

## Safety and retained evidence

Before I/O, require literal loopback addresses for API and database, explicit
ports, no connection query parameters or DNS. Proxies and HTTP redirects are
blocked. Connections are built from parsed fields with fixed hostaddr. Refuse a
database without the isolated marker or with pre-existing users. No hosted
fallback. Only this stack is stopped and its volumes deleted; fixture users are
also deleted in the proof's finally path.

Local CLI status/start/stop output contains ephemeral local keys and is neither
printed nor uploaded. The only retained artifact is a category-only receipt with
pass/fail, successful check names, exact GITHUB_SHA, PostgreSQL version and
candidate SQL SHA256. It contains no endpoints, user ids, tokens, passwords,
exception text or DB connection URL. Infrastructure startup failure fails the lane
and missing receipt fails artifact upload; it cannot turn into an empty green.

The new workflow is manual-only and has no hosted secrets. It does not change
existing required checks, release jobs, timeouts or acceptance assertions. Its
20-minute timeout bounds a new local lane, not an extension of an existing test.

## Current result

Python safety/source tests and syntax pass locally. CLI parsed the checked config
and reached container startup, then failed because neither Docker nor Podman is
available here. Actual PostgreSQL concurrent race, local Auth/PostgREST, RLS,
cleanup and negative-control execution are UNRUN. Do not call #501, #72 or
live-sync complete until the exact-head proof passes. No hosted service touched.
