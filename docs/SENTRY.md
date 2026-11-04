# Sentry integration

Sentry is Ate's crash/error and performance-observability service. It complements, rather than replaces, the existing local `DiagnosticHistory` and typed Supabase telemetry contract in [TELEMETRY.md](TELEMETRY.md).

## Configuration

- The official Sentry Cocoa SDK is pinned through XcodeGen / Swift Package Manager.
- Supply the project's DSN through the `SENTRY_DSN` environment variable when running `xcodegen generate`; XcodeGen writes it to the app's `AteSentryDSN` Info.plist key.
- An empty DSN disables Sentry. UI-test launches always disable it.
- Never commit the Sentry onboarding run code, auth token, or other account credentials. The DSN is an ingestion endpoint, not an authentication secret, but should still be configured per build environment.
- Set the Sentry project environment through the existing `ATE_CHANNEL` build setting. Empty channel maps to `production`.

## Initial privacy posture

- `sendDefaultPii` is disabled.
- Automatic breadcrumbs are dropped until a reviewed allowlist exists.
- Event user, message, extras and breadcrumbs are cleared before sending.
- Performance tracing is disabled until explicit, privacy-reviewed spans and sampling are implemented.
- Do not add recipe/journal content, prompts, URLs, account identifiers, Health data, precise location, screenshots, access tokens or raw user-provided strings.
- UI tests must not emit remote events.

This is an initial guardrail, not the final privacy sign-off. Crash exception payloads, automatic integrations, SDK upgrades and all newly added event fields must be reviewed against the data map before enabling production ingestion.

## Release health and symbolication

Production readiness requires:
1. Configure the Sentry project DSN independently for development, CI, beta and production.
2. Upload the matching app dSYM files for every distributed archive and verify symbolication against a controlled crash.
3. Associate each event with app version, build number, Git SHA and environment.
4. Configure actionable crash-free-session / new-issue alerts with an owner and response path.
5. Confirm retention, access control, data residency/subprocessor disclosures and privacy-policy wording before production rollout.

CI symbol upload must use a dedicated Sentry auth token stored as a GitHub Actions secret. Never print it, put it in the app, or store it in repository files. A missing token must not silently mark symbolication as verified.

## Validation boundaries

- An in-process SDK cannot observe a failure that prevents the app process from starting. Keep Xcode / simulator / Actions launch diagnostics for those failures.
- SDK compilation is not proof of ingestion, crash capture or symbolication.
- Controlled test events and crashes must be sent only to a non-production Sentry project/environment.
- Keep existing telemetry consent, channel gating, retention and delivery behaviour unchanged; changes to that pipeline remain tracked by issue #165.
