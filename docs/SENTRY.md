# Sentry integration

Sentry is Ate's crash/error and performance-observability service. It complements, rather than replaces, the existing local `DiagnosticHistory` and typed Supabase telemetry contract in [TELEMETRY.md](TELEMETRY.md).

## Configuration

- The official Sentry Cocoa SDK is pinned through XcodeGen / Swift Package Manager (`from: 9.32.0`; commit `Package.resolved` when reproducible pinning is required).
- Supply the project's DSN through the `SENTRY_DSN` environment variable when running `xcodegen generate`; XcodeGen writes it to the app's `AteSentryDSN` Info.plist key. For distributed beta builds, CI reads it from the `SENTRY_DSN` GitHub Actions secret in the Build IPA workflow; an unset secret expands empty and leaves Sentry disabled. Find the DSN in the Sentry project under Settings > Projects > [project] > Client Keys (DSN) (https://docs.sentry.io/concepts/key-terms/dsn-explainer/).
- Opt-in ingestion gate: the Build IPA workflow injects the DSN for a one-off proof only when a manually dispatched `TierA` build sees the temporary repository variable `SENTRY_INGESTION_PROOF=enabled`. This switch is separate from `SENTRY_BETA_INGESTION`, which remains the explicit opt-in for subsequent beta ingestion. The proof variable is read by the workflow on the selected feature-branch ref, so the proof can run while this PR remains draft and without adding a dispatch input that is absent from `main`. Production-channel builds never start Sentry regardless (app-side channel gate).
- Ingestion proof procedure: add the temporary repository **variable** `SENTRY_INGESTION_PROOF=enabled` under Settings → Secrets and variables → Actions → Variables. Then run Build IPA manually, select the `feature/289-sentry-observability` ref, set `channel=TierA`, and set `run_tests=false` to avoid unrelated full-suite work. The workflow file must be present on the default branch for `workflow_dispatch` to be available; the selected feature ref supplies the proof-aware workflow implementation. Proof mode is recognized only for this manual TierA dispatch. The proof run erases the simulator before install (fresh synthetic state), and the existing A-CI-03 bare 10-second simulator launch (no `-UITesting`) starts the SDK and captures ONE synthetic error embedding the run's canary marker (`AteSentryCanary` Info.plist key, from the `SENTRY_CANARY` env, empty in every normal build). The stored event must (a) exist, proving ingestion, and (b) contain the canary nowhere, proving scrubbing. Verify by inspecting the stored event JSON in the Sentry project. Never commit a canary value. Remove `SENTRY_INGESTION_PROOF` immediately after the run, whether it succeeds or fails.
- Proof runs never publish: the per-build prerelease, rolling `latest-build`, A-CI-06 published-artifact check and the `latest-beta` promotion job are all skipped while `SENTRY_INGESTION_PROOF` is enabled for the TierA dispatch. The proof IPA is retained only as a GitHub Actions artifact (subject to repository artifact access/retention) and is never distributed.
- A single canary proves only the seeded field paths; it is not blanket proof that no private content can be captured. The payload-verification gate below still governs production ingestion.
- An empty DSN disables Sentry. UI-test launches always disable it. CI test lanes (compile check, dogfood, UI suites) do not set a DSN, so tests never emit remote events.
- Channel gate: Sentry starts only in recognized non-production channels (`AppConfig.isBetaChannel`), the same policy the Supabase telemetry contract uses. Production, unknown and empty-channel builds never start Sentry in this slice; enabling production ingestion requires the payload/consent review below.
- Never commit the Sentry onboarding run code, auth token, or other account credentials. The DSN is an ingestion endpoint, not an authentication secret, but it is still configured per build environment rather than committed.
- The Sentry environment is derived from the existing `ATE_CHANNEL` build setting (lowercased).

## Enabled in this slice (non-production builds with a DSN)

- Crash and unhandled-error capture (SDK default crash handler).
- App-hang and watchdog-termination detection (SDK defaults).
- Release identity: version+build in the release name, build in `dist`, Git SHA as a `git_sha` event tag, channel as environment.

## Deliberately off in this slice

- `sendDefaultPii` is disabled.
- Release-health session tracking is disabled until session payloads are verified against the privacy contract.
- Network tracking is disabled (it attaches request URLs and trace headers; URLs are on the never-send list).
- Performance tracing is disabled until explicit, privacy-reviewed spans and sampling are implemented (#289 instrumentation slice).
- Automatic breadcrumbs are dropped until a reviewed allowlist exists.
- Event user, message, extras, breadcrumbs, request and SDK tags are cleared before sending (`SentryBootstrap.scrubEvent`, covered by `AteTests/SentryBootstrapTests.swift`).
- Exception free-text values are replaced with `[Filtered]` (raw error messages can embed interpolated user strings; TELEMETRY.md bars them). Exception type, mechanism, stacktrace and threads are kept for triage.
- Remaining fields (contexts, mechanism metadata, debug images) are retained for crash triage and are NOT categorically content-free; they are covered by the payload-verification gate below before any production-channel ingestion.

Do not add recipe/journal content, prompts, URLs, account identifiers, Health data, precise location, screenshots, access tokens or raw user-provided strings. UI tests must not emit remote events.

This is an initial guardrail, not the final privacy sign-off. Crash exception payloads, automatic integrations, SDK upgrades and all newly added event fields must be reviewed against the data map before enabling production ingestion.

## Initial data map

Sent (after scrubbing): exception type/mechanism/stacktrace, thread stacks, device model, OS and app context, release name (version+build), `dist` (build number), environment (channel), the `git_sha` tag, and the SDK's per-install pseudonymous installation identifier (device app hash) used for event grouping. That identifier persists per install and is recorded here as a known data element; it carries no account or content data but is pseudonymous.

Never sent: event user, message, extras, breadcrumbs, request data (URLs), SDK tags, raw error/exception messages (filtered to `[Filtered]`), sessions, network requests/headers, performance spans, and everything on the TELEMETRY.md never-send list (recipe/journal content, prompts, screenshots, account identifiers, Health data, precise location, access tokens, raw user-provided strings).

## At-rest crash cache caveat

The scrub guarantee covers the TRANSMITTED payload only, through the verified `beforeSend` SDK path. A fatal crash is written to the SDK's on-device cache UNSCRUBBED (the process is dying; `beforeSend` runs at transmit time on the next launch). Raw crash data - including any interpolated strings in exception payloads - therefore exists at rest on the device until the next launch transmits or discards it. Local `DiagnosticHistory` already documents its own bounds; this cache is additional and is not exported or displayed in-app.

## Release health and symbolication

Production readiness requires:
1. Configure the Sentry project DSN independently for development, CI, beta and production.
2. Configure CI symbol upload using the Sentry CLI and `SENTRY_AUTH_TOKEN`; upload matching app dSYM files for every distributed archive and verify symbolication against a controlled crash.
3. Associate each event with app version, build number, Git SHA and environment.
4. Configure actionable crash-free-session / new-issue alerts with an owner and response path.
5. Confirm retention, access control, data residency/subprocessor disclosures and privacy-policy wording before production rollout.

CI symbol upload must use a dedicated Sentry auth token stored as a GitHub Actions secret. Never print it, put it in the app, or store it in repository files. A missing token must not silently mark symbolication as verified.

## Validation boundaries

- An in-process SDK cannot observe a failure that prevents the app process from starting. Keep Xcode / simulator / Actions launch diagnostics for those failures.
- SDK compilation is not proof of ingestion, crash capture or symbolication.
- Controlled test events and crashes must be sent only to a non-production Sentry project/environment.
- Keep existing telemetry consent, channel gating, retention and delivery behaviour unchanged; changes to that pipeline remain tracked by issue #165.
