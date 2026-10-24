# Telemetry deployment evidence

Deployment verified against the existing `ate` Supabase project (`ploncuhexmwydjxljuhe`, EU Ireland / `eu-west-1`) on 24 October 2026.

## Rollout

- Applied `20261023090000_remote_telemetry.sql` as migration `remote_telemetry`.
- Applied `20261023120000_telemetry_abuse_controls_retention.sql` as migration `telemetry_abuse_controls_retention`.
- Deployed `supabase/functions/telemetry/index.ts` as Edge Function `telemetry`, version 2, with JWT verification disabled. The function performs its own public-key validation and uses the server-only service-role credential for inserts.
- Configured the server-side `ATE_PUBLIC_KEYS` secret with the active public publishable key. The key value is intentionally not recorded in this repository or in issue comments.
- No service-role credential is present in the iOS client or telemetry payload.

## Acceptance evidence

The live endpoint `https://ploncuhexmwydjxljuhe.supabase.co/functions/v1/telemetry` returned:

| Check | Result |
|---|---:|
| Valid `Development` event | `202`, `{"accepted":1}` |
| Missing API key | `401` |
| `Production` channel | `400` |
| Unknown channel | `400` |
| Malformed timestamp | `400` |
| Unknown event kind | `400` |
| Request over 12,000 bytes | `413` |
| Batch over 20 events | `400` |
| Valid chunked request without `Content-Length` | `202`, `{"accepted":1}` |

The accepted test events are present in `public.app_telemetry_events` with only the allowlisted event kind, channel, coarse build metadata, platform, and timestamps.

Direct Data API checks with the public publishable key returned `401` for both reading and writing `public.app_telemetry_events`. Database inspection confirmed RLS is enabled, `anon` and `authenticated` have no table grants, and only `service_role` has table privileges. The rate-limit RPC is `SECURITY DEFINER` and is executable only by `service_role`.

## Retention and scheduled cleanup

Both scheduled jobs are active:

- `ate-telemetry-retention-daily` at `17 3 * * *`, deleting events older than 29 days. The one-day scheduling margin guarantees removal by 30 days even if ingestion stops.
- `ate-telemetry-rate-limit-cleanup-daily` at `27 3 * * *`, deleting inactive hashed rate-limit keys older than one day.

The configured jobs provide the no-new-events cleanup path required by the telemetry contract. Supabase's security advisor reports the expected informational `rls_enabled_no_policy` findings for the two intentionally service-role-only tables; direct anon/authenticated access checks are denied.

## Related privacy documentation

The deployment is covered by the telemetry contract and privacy/subprocessor disclosures in:

- [`docs/TELEMETRY.md`](TELEMETRY.md)
- [`docs/legal/privacy.md`](legal/privacy.md)
- [`docs/legal/subprocessors.md`](legal/subprocessors.md)
- [`docs/legal/cookies.md`](legal/cookies.md)


## Review reconciliation — 24 October 2026

The follow-up review of [issue #169's deployment evidence](https://github.com/melusi-k/ate-ios/issues/169#issuecomment-6379507669) is complete. The deployment/receiver rollout remains **completed** and this issue remains closed.

The review cross-checked the recorded live acceptance results against `supabase/functions/telemetry/index.ts`, both migrations, and `docs/TELEMETRY.md`. The implementation includes public-key allowlisting, a streaming request-size cap, a 20-event batch cap, server-side allowlisted row construction, atomic per-client rate limits (300 requests/hour and 2,000/day), fail-closed handling when the platform client-address header is absent, service-role-only database access, and scheduled cleanup.

The original deployment evidence explicitly records the live results listed above. To keep evidence precise, the following additional runtime cases were **not recorded in the deployment comment** and must not be inferred as having passed solely from code inspection:

- A supplied but invalid API key returning `401`.
- Exhausting the hourly/daily quota and observing `429`.
- Missing platform client-address metadata returning `503`.
- An end-to-end retention execution/deletion observation (the scheduled jobs are recorded as active).

These are follow-up verification opportunities, not evidence of a known deployment defect. They do not block closing the deployment task because the deployment and receiver acceptance checks recorded in issue #169 passed; retain the distinction between configured safeguards and separately observed runtime outcomes. If these cases are exercised later, append their timestamped outcomes here.
