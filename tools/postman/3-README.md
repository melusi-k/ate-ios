# Ate API test workspace

Import `Ate.postman_collection.json` and `Staging.postman_environment.json` in current Postman (with `pm.execution.skipRequest()` support). Select the staging environment. No account keys or passwords are committed. Nothing in this packet has been sent to a live API.

## Safe setup

1. Create/use an isolated, disposable staging account and project. Never point this collection at production. Set `supabase_url` and `approved_staging_host` to that project's exact HTTPS origin/hostname. The hostname approval is an operator check, not automatic proof of staging.
2. Set the staging publishable/anon key locally, never a service-role/secret key. Set `synthetic_account_confirmed=true` only after confirming that the account and its data are disposable. Keep passwords, JWTs, OTP codes and PKCE verifiers in local secret environment values. Never send them in chat or commit/export a filled environment.
3. For sign-in, set the synthetic `test_email`/`test_password`, then `allow_mutations=true` and send **Password sign in**. Successful sign-in stores `access_token`, `refresh_token`, `user_id` in the local environment. Turn mutations off afterward. An already authenticated staging account can supply those three values locally instead.
4. Run **02 Read-only Supabase**. The snapshot stores `generation` locally for later explicit writes. QA reads require real staging `qa_build`, `commit_sha`, `run_id` values. An empty array is a valid transport response, not proof that a CI build passed.
5. Run only the intended folder or individual requests. Do not run the whole collection. Disabled guards skip requests; a skipped request is NOT a passed API test. Inspect runner counts. Every response test asserts one exact status; do not widen expected statuses to make a deployment failure pass.

Default values deliberately point at `.invalid`, disable mutations, and separately disable reset/deletion. All pre-request failures call `skipRequest()` before throwing. Redirect following is disabled to avoid sending credentials to another origin. Verify this setting stays off in any runner/import conversion. Old Postman/Newman versions without `skipRequest` are unsupported; do not run them with real credentials.

## Stateful and destructive checks

- **01 Auth** is manual, not a linear runner suite. Email, password, token rotation and logout have side effects. OTP/PKCE operations require a real email callback/code and matching verifier. A new link/recovery request creates a new verifier; finish one flow before starting another. Signup/OTP expected status is the GoTrue success contract; current gateway/configuration/rate-limit errors should fail rather than be accepted. Watch OTP uses `create_user=false`.
- **03 Explicit writes** has both generation-aware recipe/shopping puts and legacy direct-write **denial** tests. A v6-fenced backend must reject legacy writes with 403/42501. An older backend may accept these writes and the test must fail. Do not run against an account with personal data. The QA upload is a synthetic **untested** transport fixture with deliberately synthetic evidence identity, not a real qualification verdict and not something the app would upload as qualified evidence.
- **04 Destructive reset scenario** is an ordered runner folder. Set `allow_mutations=true` and `allow_account_reset=I_ACCEPT_SYNTHETIC_ACCOUNT_ERASURE` only on an isolated synthetic account. It resets all account data, retries the same UUID, writes one retained row, checks stale put and both reset-conflict paths return HTTP409 / `PT409`, then verifies generation, row count and retained data did not change. Prevent all other writers for this account while it runs. Run this folder alone in one session. Generation integers must fit JavaScript's safe range; snapshots reject larger values rather than round them silently.
- `reset_request_id`, `old_generation`, and `generation` persist locally so a lost response can be reconciled. If reset result is uncertain, STOP: retain UUID and original generation and retry request02/03 unchanged, or investigate status. Do not restart from request01 because it would replace `old_generation`. Do not assign a fresh UUID to guess recovery. After a fully verified scenario, explicitly clear `reset_request_id` before a new scenario. A second completed reset makes the earlier UUID no longer the latest receipt.
- **05 Anon denial** requires the project's legacy anon JWT locally (`legacy_anon_jwt`, role=anon), not a publishable key as a fake bearer. Expected SQL denial is401/42501. Gateway401 with another error body is not proof of SQL permissions. If your project has no legacy anon JWT, leave these unrun and use the SQL fixture evidence instead; never use admin credentials.
- **06 Edge** publishes a synthetic shared recipe, reads it, and exercises telemetry/feedback. These create staging rows and consume rate-limit budget. `parse-recipe` is referenced by an unused/dormant client path but has no server implementation in this repository. Its four future templates require `parse_deployed=true` and expect successful recipe envelopes; leave them skipped until an implementation exists. No remote AI provider/key is invented.
- **07 Account deletion** is separate, last and manual. It removes the synthetic identity, user recipes and shared recipes. This is not cleanup for a personal account. Verify `{deleted:true}` and then verify sign-in/session rejection outside this template before declaring account erasure proven. Do not automatically retry deletion after an uncertain response.
- **08 External** uses no auth/apikey headers. Set only one `approved_external_host` at a time. Inputs are parameterized HTTPS recipe/social/image/legal/share URLs. `encoded_social_url` must be percent-encoded. These are contract probes, not a browser, crawler, anti-bot bypass or an exhaustive test of arbitrary URLs.200 is required;403/429/timeouts fail and must not be hidden. No credentials belong in query strings.
- **09 Edge CORS** checks supported preflight methods; this is not app behavior or deployment proof.

## Coverage and validation

`COVERAGE.md` and `coverage.json` list every included route/method variant and exclusions from source inventory across iPhone, Watch, App Clip and edge code at commit841c14ee. Sentry ingestion is SDK-managed; local Apple frameworks are not REST endpoints; service-role downstream dependencies are tested through public edge entry points, not exposed as client templates. Storage has no direct source caller.100% live behavior, browser, device, authorization or branch coverage is not claimed.

Offline checks:

```sh
python3 tools/postman/build_collection.py
node tools/postman/validate_collection.cjs
```

The generator is deterministic, does no network IO and restores only placeholder values. The validation executes scripts with mocks, tests fail-closed guards and contract assertions; it is NOT a Postman import, real Supabase run, native test or deployment check. No paid tool, CI workflow or application source change is required. Import/run the selected safe requests in current Postman for actual evidence.
