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
