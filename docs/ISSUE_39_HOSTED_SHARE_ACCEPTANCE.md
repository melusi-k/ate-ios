# Issue #39 — hosted share and production security acceptance

This checklist is deliberately evidence-based. A green app-side share test is not evidence that the deployed browser page handles an unknown slug or a function outage.

## Hosted browser matrix (Playwright, backend-e2e)

Run `scripts/e2e/backend_e2e.py` with the normal backend-e2e secrets and Playwright Chromium installed.

- [ ] **Valid share:** publish a disposable recipe through the authenticated `publish-recipe` function; verify the deployed Pages URL renders title, ingredients, and steps; verify “Open in Ate” targets `ate://recipe/<slug>`.
- [ ] **Unknown slug:** request a random non-existent slug in a real browser; verify an explicit not-found state (not a blank page or an unhandled exception).
- [ ] **Transient lookup outage:** fault-inject HTTP 503 for `get-shared-recipe`; verify a user-visible retryable error and verify the browser does not fall back to direct `/rest/v1/shared_recipes` reads.
- [ ] **Cleanup:** remove test shares/users even when a test fails; keep screenshots and backend-e2e JSON/Markdown results as CI artifacts.

## Production security acceptance

The automated checks in `scripts/e2e/security_checks.py` are necessary but do not prove dashboard configuration or migration deployment. Attach fresh, timestamped evidence for each item:

- [ ] RLS enabled for every public table; owner isolation and anon restrictions pass.
- [ ] `publish-recipe` requires a verified user JWT; `get-shared-recipe` is intentionally public and only returns the selected public recipe fields; `delete-account` requires a verified user JWT.
- [ ] SQL grants, default privileges, trigger `search_path`, and `shared_recipes` write restrictions match the checked-in hardening migrations.
- [ ] Edge Function gateway “Verify JWT” settings confirmed in the deployed project; service-role key is server-only.
- [ ] CORS, rate limits, retention/deletion behavior, and Supabase Security Advisor findings reviewed and recorded.
- [ ] Existing open findings F-01 through F-09 in `docs/SECURITY_REVIEW.md` have a verified disposition or remain explicitly blocked with an owner.

## Critical safety gate

**Do not revoke anon SELECT on `shared_recipes` until the hosted valid-share, unknown-slug, and injected-outage browser checks pass on the deployed Pages site.** If outage testing detects direct PostgREST fallback, treat it as a security acceptance failure and fix the hosted page in its owning repository before changing production grants.

Passing CI proves only the checks that ran against the deployed service at that time. It does not automatically close issue #39 or satisfy manual/dashboard-only items.
