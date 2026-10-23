# Ate telemetry contract

## Runtime policy

- Recognized non-production channels (`TierA`, `TierB`, `TierC`, `Beta`, `QA`, `Internal`, `Development`) send privacy-safe remote telemetry by default.
- Empty, unknown, and production channels never send remote telemetry. UI-test launches never send remote telemetry.
- Telemetry uses the existing Supabase project and is best-effort. Feature behaviour must never depend on delivery.
- The Supabase Edge Function must be deployed with JWT verification disabled because the app uses only its public publishable key. The function independently validates that key against server-side public-key configuration. Never put a service-role key in the app.
- Apply `supabase/migrations/20261023090000_remote_telemetry.sql` before deploying the function. Confirm table grants/RLS and retention in the target project.

## Payload and privacy

- Event names are a closed Swift enum and server-side allowlist. The server constructs database rows from known fields only; unknown fields are discarded.
- Payloads contain event category, event timestamp, release channel, app version, build number, Git SHA and platform. They contain no user/account/device identifier.
- Never include recipe titles or ingredients, prompts, screenshots, URLs, raw error messages, Health data, precise location, access tokens, or other user-provided strings.
- Only events from the last seven days are accepted. Each request accepts at most 20 events; the client applies a conservative local rate guard. The server deletes received rows older than 30 days during ingestion.
- Supabase infrastructure may process request metadata such as IP address for service security. The application does not add an IP address to the telemetry payload or store one in the event table.
- Local diagnostic history remains bounded to 200 events, exportable and clearable in Settings. Clearing local history does not retroactively delete already received remote aggregates/events; remote rows expire under the 30-day retention policy.
- Product event recording and uploads must not affect feature success/failure, block UI work, or make release gates less strict.

## Deployment and acceptance

1. Apply the migration to the existing Supabase project.
2. Configure the function's accepted public key list with the project's publishable/anon key; do not create a new client-side secret.
3. Deploy `telemetry` with `--no-verify-jwt`; verify the function rejects missing/unknown API keys, production/unknown channels, malformed timestamps, unrecognized categories, and oversized batches.
4. Verify a non-production test event is inserted and production/unknown-channel requests are rejected.
5. Verify RLS prevents `anon` and `authenticated` from reading or writing telemetry rows, and verify rows older than 30 days are removed on ingestion.
6. Build and run tests on the exact PR head. Do not merge based on a previous head's run.

## CI telemetry

CI emits a separate JSON artifact derived from GitHub Actions run/job/step metadata. It includes the commit SHA, workflow/run identifiers, runner metadata, outcomes and available timing values. Creation-to-start durations are explicitly named as such; they are not described as queue time because run creation is not a queue timestamp. Missing timings stay null. The collection is best-effort and non-blocking; it must not change build/test outcomes. No source files, logs, secrets, app data, or tester data are collected by this artifact.
