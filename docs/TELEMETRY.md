# Ate telemetry contract

## Runtime policy

- Recognized non-production channels (`TierA`, `TierB`, `TierC`, `Beta`, `QA`, `Internal`, `Development`) send privacy-safe remote telemetry by default.
- Empty, unknown, and production channels never send remote telemetry. UI-test launches never send remote telemetry.
- Telemetry uses the existing Supabase project and is best-effort. Feature behaviour must never depend on delivery.
- The Supabase Edge Function must be deployed with JWT verification disabled because the app uses only its public publishable key. The function independently validates that key against server-side public-key configuration. Never put a service-role key in the app.
- Apply both migrations in timestamp order before deploying the function: `20261023090000_remote_telemetry.sql`, then `20261023120000_telemetry_abuse_controls_retention.sql`. The latter installs the server-side rate-limit RPC and scheduled retention jobs. Confirm the `pg_cron` jobs are active in the target project.

## Payload and privacy

- Event names are a closed Swift enum and server-side allowlist. The server constructs database rows from known fields only; unknown fields are discarded.
- Payloads contain event category, event timestamp, release channel, app version, build number, Git SHA and platform. They contain no user/account/device identifier.
- Never include recipe titles or ingredients, prompts, screenshots, URLs, raw error messages, Health data, precise location, access tokens, or other user-provided strings.
- The server reads request bodies with a hard 12,000-byte limit before JSON parsing; this limit is enforced while streaming and does not rely on `Content-Length`. Each request accepts at most 20 events, and only events from the last seven days are accepted.
- The server enforces an atomic per-client-address quota of 300 requests per hour and 2,000 requests per day. The Edge Function hashes the platform-provided `cf-connecting-ip` value before sending it to the rate-limit table; raw addresses are not stored by the application. If that header is unavailable, the endpoint fails closed. The app's local rate guard is only an additional guardrail, not a security boundary.
- A daily `pg_cron` job deletes received events older than 30 days even when no new telemetry arrives. A second daily job removes inactive hashed rate-limit keys after two days. Verify both jobs are active after applying the migration.
- Supabase infrastructure may independently process request metadata such as IP address for service security. The application does not add an IP address to telemetry payloads or store one in the event table.
- Local diagnostic history remains bounded to 200 events, exportable and clearable in Settings. Clearing local history does not retroactively delete already received remote events; remote rows expire under the 30-day retention policy.
- Product event recording and uploads must not affect feature success/failure, block UI work, or make release gates less strict.

## Deployment and acceptance

1. Apply the migrations to the existing Supabase project in timestamp order.
2. Configure the function's accepted public key list with the project's publishable/anon key; do not create a new client-side secret.
3. Deploy `telemetry` with `--no-verify-jwt`.
4. Verify missing/unknown API keys, production/unknown channels, malformed timestamps, unrecognized categories, oversized bodies (including requests without `Content-Length`), and batches over 20 are rejected.
5. Verify the server-side quota allows requests within limits and rejects requests over hourly/daily limits; confirm missing platform client-address metadata fails closed.
6. Verify a non-production test event is inserted, and that RLS prevents `anon` and `authenticated` from reading or writing telemetry rows.
7. Verify both scheduled jobs exist and run; confirm events older than 30 days are deleted even when no ingestion occurs.
8. Build and run tests on the exact PR head. Do not merge based on a previous head's run.

## CI telemetry

CI emits a separate JSON artifact derived from GitHub Actions run/job/step metadata. It includes the commit SHA, workflow/run identifiers, runner metadata, outcomes and available timing values. Creation-to-start durations are explicitly named as such; they are not described as queue time because run creation is not a queue timestamp. Missing timings stay null. The collection is best-effort and non-blocking; it must not change build/test outcomes. No source files, logs, secrets, app data, or tester data are collected by this artifact.
