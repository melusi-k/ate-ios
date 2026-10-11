# Supabase security review — project `ploncuhexmwydjxljuhe`

Reviewed 2026-10-11 against `supabase/migrations/*`, `supabase/functions/*`, the iOS client and CI. Automated checks
live in `scripts/e2e/security_checks.py` and run in **backend-e2e** on every build (A-SEC-01 … A-SEC-06); open
findings are printed under "Security review: open findings" in that job's summary.

## Scope and results

| Area | Check | Result | Evidence |
|---|---|---|---|
| RLS | RLS on every `public` table | ✅ `shared_recipes`, `user_recipes`, `qa_results` all enabled | A-SEC-01 (queries `pg_class`/`pg_policies`) |
| RLS | Deny by default, owner-only | ✅ user tables: policies only for `authenticated`, all `auth.uid() = user_id`; `qa_results` writes limited to `source='device'` | A-SEC-01, A-SEC-03 |
| RLS | Anon token | ✅ anon can't read/write `user_recipes`/`qa_results` or insert `shared_recipes` | A-SEC-02 |
| RLS | Other-user token | ✅ can't read, update, delete, spoof `user_id`, or write `ci` QA rows | A-SEC-03, A-AUTH-07 |
| Edge Functions | Auth / JWT | ✅ `delete-account` verifies the user JWT with `auth.getUser` (rejects anon/`sb_` keys); `publish-recipe` accepts a verified user JWT; `get-shared-recipe` is public read by opaque slug using a server-only service key | A-SEC-04 |
| Edge Functions | Input validation | ✅ `publish-recipe` type/length checks on every field, ≤100 ingredients/steps, 100 KB card, 200 KB body (413), https-only covers; slug regex on `get-shared-recipe` | A-SEC-04 |
| Edge Functions | Rate limits | 🟡 `publish-recipe`: 20 same-title / 10 min, 60 global / min, same card reuses its slug (429 otherwise). No per-IP/per-user limit | F-07 |
| Edge Functions | CORS | 🟡 `Access-Control-Allow-Origin: *`. Low risk: no cookies, bearer auth only; the native app doesn't need CORS | F-08 |
| Client | No service key in the app | ✅ only the publishable/anon key ships; `scripts/check-ids.py` fails CI on `service_role`/`sb_secret_` in client code | A-CI-05 |
| Storage | Bucket policies | ✅ no buckets in use (covers are https URLs or on-device files); A-SEC-06 lists any bucket and flags public ones | A-SEC-06 |
| Auth | Password policy | ✅ min 8, letters + digits required; weak passwords rejected | A-AUTH-02, A-SEC-05 |
| Auth | Email confirmation | ✅ on (`mailer_autoconfirm=false`) | A-SEC-05 |
| Auth | OTP expiry | ✅ ≤ 1 h asserted | A-SEC-05 |
| Auth | Leaked-password check (HIBP) | ⛔ off; needs the Pro plan | F-01 |
| DB | Function `search_path` | 🟡 `user_recipes_touch` must use an empty `search_path`; a later migration currently overrides the hardening migration with `public` | F-04, corrected by `20261012100000_pin_empty_trigger_search_path.sql`; apply and verify |
| DB | Anon grants | 🟡 anon still has default table grants on user tables (RLS blocks them) | F-03, fixed in migration |
| DB | `shared_recipes` listing | 🟡 public `SELECT USING (true)` still lets the anon key enumerate slugs. Native iOS now reads through `get-shared-recipe`; public table SELECT must remain until the hosted share page is migrated too | F-02 |

## Findings and fixes

| ID | Severity | Finding | Fix | State |
|---|---|---|---|---|
| F-01 | Medium | Leaked-password protection off | Dashboard › Auth › Passwords › "Prevent use of leaked passwords" (Pro plan) | **Needs you** |
| F-02 | Low | `shared_recipes` enumerable with the anon key | Native app and edge function are routed through `get-shared-recipe` in PR #20. Hosted page migration merged in `melusi-k/ate-legal#1`; the Pages deployment succeeded and the source no longer contains a direct PostgREST fallback. **Still verify a real valid share, an unknown slug, and function-outage retry behavior in a browser before revoking table SELECT. Do not revoke yet.** | In progress |
| F-03 | Low | anon holds table grants on `user_recipes`/`qa_results` | `20261011090000_security_hardening.sql`: `revoke all … from anon` + default privileges | Migration written, **apply needed** |
| F-04 | Low | trigger function uses `search_path = public` rather than the empty path recommended by Supabase | `20261012100000_pin_empty_trigger_search_path.sql` sets `search_path = ''`; A-SEC-06 now reports if the deployed function is not pinned to the empty path | Migration written, **apply + backend-e2e verification needed** |
| F-05 | Info | write privileges on `shared_recipes` for anon/authenticated are implicit | same migration revokes insert/update/delete (only the service role writes) | Migration written, **apply needed** |
| F-06 | Info | `qa_results.note` unbounded | same migration: length check | Migration written, **apply needed** |
| F-07 | Low | no per-user/IP rate limit on `publish-recipe` | Consider a `share_events(ip_hash, ts)` limiter; Auth rate limits are in the dashboard | Accepted for beta |
| F-08 | Info | CORS `*` on functions | Restrict to `https://melusi-k.github.io` once the share page calls functions | Accepted for beta |
| F-09 | Info | Edge Function "Verify JWT" gateway setting isn't in the repo (no `supabase/config.toml`) | Check in the dashboard: `delete-account` and `publish-recipe` **on**, `get-shared-recipe` **off** (public) | **Needs you** |

## Secrets inventory

| Secret | Where | Scope | Notes |
|---|---|---|---|
| Publishable / anon key | iOS app (`ATE_SUPABASE_PUBLISHABLE_KEY`), share page | public | RLS-guarded; safe to ship |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function env only | full DB | Never in client or repo (CI scan) |
| `SUPABASE_ANON_KEY`, `ATE_PUBLIC_KEYS` | Edge Function env | public | accepted keys for anonymous shares |
| `SUPABASE_ACCESS_TOKEN` | GitHub Actions secret | Management API | backend-e2e and readiness; keys fetched at runtime and masked |
| Signing secrets (`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, profiles, `TEAM_ID`) | GitHub Actions secrets | code signing | unset today (unsigned builds) |
| SMTP credentials | Supabase Auth settings | email | see docs/SMTP.md |

## You need to do (dashboard access)

1. Apply `supabase/migrations/20261011090000_security_hardening.sql` and the later `20261012100000_pin_empty_trigger_search_path.sql` (SQL editor, or `supabase db push`).
2. Auth › Passwords: turn on leaked-password protection (Pro plan) — F-01.
3. Edge Functions: confirm the Verify JWT settings in F-09.
4. Rotate `SUPABASE_ACCESS_TOKEN` if it is older than 90 days; keep it scoped to this project.
5. Re-run backend-e2e and confirm the open-findings list is empty apart from F-02, F-07, F-08.

## Sign-off checklist

- [x] RLS enabled on every table, owner-only policies (A-SEC-01)
- [x] Anon and other-user tokens tested in backend-e2e (A-SEC-02, A-SEC-03)
- [x] Edge Function auth and input validation tested (A-SEC-04)
- [x] Rate limits reviewed (F-07 accepted)
- [x] CORS reviewed (F-08 accepted)
- [x] No service key in the client (CI scan, A-CI-05)
- [x] Secrets inventory written
- [x] Storage bucket policies reviewed (no buckets in use)
- [x] Auth settings asserted: password policy, email confirm, OTP expiry (A-SEC-05)
- [ ] Leaked-password check on (F-01, needs dashboard + plan)
- [ ] Hardening migration applied (F-03 … F-06)
- [ ] Verify JWT settings confirmed (F-09)

Reviewed by Grok Bot for Melusi Khumalo, 2026-10-11. Final sign-off once the three open boxes are ticked.
