"""Supabase security review checks (docs/SECURITY_REVIEW.md, A-SEC-xx). Imported by backend_e2e.py.
Hard asserts = must hold; `ctx.findings` collects open, non-blocking findings for the review doc."""
import json, uuid
from backend_e2e import http, URL, REF, upsert  # noqa: E402

def sql(ctx, q):
    code, j = http("POST", f"https://api.supabase.com/v1/projects/{REF}/database/query", ctx.mgmt, {"query": q})
    assert code in (200, 201), f"database/query {code} {j}"
    return j

def finding(ctx, s):
    ctx.findings = getattr(ctx, "findings", []) + [s]

def t_rls_every_table(ctx):
    rows = sql(ctx, "select c.relname, c.relrowsecurity rls, (select count(*) from pg_policy p where p.polrelid=c.oid) pols "
                    "from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')")
    off = [r["relname"] for r in rows if not r["rls"]]
    assert not off, f"RLS disabled on: {off}"
    nopol = [r["relname"] for r in rows if r["pols"] == 0]
    if nopol: finding(ctx, f"tables with RLS but no policies (deny-all, fine if intended): {nopol}")
    pols = sql(ctx, "select tablename, policyname, roles::text, cmd, qual, with_check from pg_policies where schemaname='public'")
    for p in pols:
        if p["tablename"] in ("user_recipes", "qa_results"):
            assert "anon" not in p["roles"] and "public" not in p["roles"], f"{p['policyname']} grants {p['roles']}"
            assert "auth.uid()" in (p["qual"] or "") + (p["with_check"] or ""), f"{p['policyname']} not owner-scoped"
    return f"RLS on all {len(rows)} public tables; user tables owner-only ({len(pols)} policies reviewed)"

def t_anon_denied(ctx):
    for t in ("user_recipes", "qa_results"):
        code, j = http("GET", f"{URL}/rest/v1/{t}?select=*&limit=1", ctx.anon_h())
        assert code in (401, 403) or j == [], f"anon read {t}: {code} {j}"
        code, j = http("POST", f"{URL}/rest/v1/{t}", ctx.anon_h(), {"user_id": str(uuid.uuid4())})
        assert code in (401, 403, 400), f"anon insert {t}: {code}"
    code, _ = http("POST", f"{URL}/rest/v1/shared_recipes", ctx.anon_h(), {"slug": "zzhack" + uuid.uuid4().hex[:6], "title": "x", "card": {}})
    assert code in (401, 403), f"anon direct insert into shared_recipes: {code}"
    code, j = http("GET", f"{URL}/rest/v1/shared_recipes?select=slug&limit=5", ctx.anon_h())
    if code == 200 and j: finding(ctx, "shared_recipes is listable with the anon key (public SELECT USING true): slugs are enumerable")
    return "anon key cannot read or write user_recipes / qa_results, or insert shared_recipes directly"

def t_other_user(ctx):
    a = ctx.new_user(); ta = ctx.sign_in(a)["access_token"]
    b = ctx.new_user(); tb = ctx.sign_in(b)["access_token"]
    upsert(ctx, ta, [{"user_id": a["id"], "kind": "recipe", "id": "sec-a", "data": {"t": 1}, "updated_at": 1, "deleted": False}])
    h = {**ctx.anon_h(tb), "Prefer": "return=representation"}
    code, j = http("PATCH", f"{URL}/rest/v1/user_recipes?user_id=eq.{a['id']}", h, {"data": {"pwned": True}})
    assert code in (200, 204) and not j, f"other user UPDATE affected rows: {j}"
    code, j = http("DELETE", f"{URL}/rest/v1/user_recipes?user_id=eq.{a['id']}", h)
    assert not j, f"other user DELETE affected rows: {j}"
    code, j = upsert(ctx, tb, [{"user_id": a["id"], "kind": "recipe", "id": "spoof", "data": {}, "updated_at": 1, "deleted": False}])
    assert code in (401, 403), f"insert as another user_id: {code}"
    code, j = http("POST", f"{URL}/rest/v1/qa_results", ctx.anon_h(tb), {"user_id": b["id"], "build": "x", "item_id": "x", "status": "pass", "source": "ci"})
    assert code in (401, 403), f"user wrote a source=ci QA row: {code}"
    code, j = http("GET", f"{URL}/rest/v1/user_recipes?select=data&user_id=eq.{a['id']}", ctx.anon_h(ta))
    assert j and j[0]["data"] == {"t": 1}, f"owner row changed: {j}"
    return "other-user token can't read, update, delete, spoof user_id, or write ci QA rows"

def t_functions(ctx):
    f = f"{URL}/functions/v1"
    code, _ = http("POST", f"{f}/delete-account", {}, {})
    assert code == 401, f"delete-account without token: {code}"
    code, _ = http("POST", f"{f}/delete-account", ctx.anon_h(), {})
    assert code == 401, f"delete-account with anon key: {code}"
    code, _ = http("POST", f"{f}/publish-recipe", {"Content-Type": "application/json"}, {"card": {}})
    assert code == 401, f"publish-recipe without key: {code}"
    code, _ = http("POST", f"{f}/publish-recipe", ctx.anon_h("eyJhbGciOiJIUzI1NiJ9.e30.forged"), {"card": {}})
    assert code == 401, f"publish-recipe forged JWT: {code}"
    code, j = http("POST", f"{f}/publish-recipe", ctx.anon_h(), {"card": {"title": "x", "servings": 1, "ingredients": "nope", "steps": []}})
    assert code == 400, f"publish-recipe bad body: {code} {j}"
    code, j = http("POST", f"{f}/publish-recipe", ctx.anon_h(), {"card": {"title": "x" * 500, "servings": 1, "ingredients": [], "steps": [{"instruction": "a"}]}})
    assert code == 400, f"publish-recipe overlong title: {code}"
    code, j = http("POST", f"{f}/publish-recipe", ctx.anon_h(), {"card": {"title": "x", "servings": 1, "ingredients": [{"name": "y" * 150_000}], "steps": []}})
    assert code in (400, 413), f"publish-recipe oversized: {code}"
    code, _ = http("GET", f"{f}/get-shared-recipe?slug=../../etc", ctx.anon_h())
    assert code == 400, f"get-shared-recipe slug validation: {code}"
    code, j = http("OPTIONS", f"{f}/publish-recipe", {"Origin": "https://evil.example"})
    finding(ctx, "Edge Functions answer CORS with Access-Control-Allow-Origin: * (low risk: no cookies; auth is bearer-only)")
    return "delete-account requires a user JWT; publish-recipe rejects missing/forged auth, bad shape, overlong and oversized input; slug validated"

def t_auth_settings(ctx):
    code, cfg = http("GET", f"https://api.supabase.com/v1/projects/{REF}/config/auth", ctx.mgmt)
    assert code == 200, f"config/auth {code}"
    assert (cfg.get("password_min_length") or 0) >= 8, "password_min_length < 8"
    assert cfg.get("mailer_autoconfirm") is False, "email confirmation disabled (mailer_autoconfirm=true)"
    otp = cfg.get("mailer_otp_exp") or 0
    assert 0 < otp <= 3600, f"email OTP expiry {otp}s (> 1 h)"
    if not cfg.get("password_hibp_enabled"): finding(ctx, "leaked-password protection (HaveIBeenPwned) is OFF; needs Pro plan / dashboard toggle")
    if (cfg.get("rate_limit_email_sent") or 0) > 30: finding(ctx, f"rate_limit_email_sent={cfg.get('rate_limit_email_sent')}/h")
    if cfg.get("security_refresh_token_reuse_interval") is None: finding(ctx, "refresh-token reuse interval not set")
    return (f"min length {cfg.get('password_min_length')}, email confirm on, OTP {otp}s, HIBP {'on' if cfg.get('password_hibp_enabled') else 'OFF'}, "
            f"email rate {cfg.get('rate_limit_email_sent')}/h, otp rate {cfg.get('rate_limit_otp')}")

def t_storage_and_functions_sql(ctx):
    b = sql(ctx, "select id, public, file_size_limit, allowed_mime_types from storage.buckets")
    pub = [x["id"] for x in b if x["public"]]
    if pub: finding(ctx, f"public storage buckets: {pub}")
    fn = sql(ctx, "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
                  "where n.nspname='public' and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))")
    if fn: finding(ctx, f"public functions without a fixed search_path: {[x['proname'] for x in fn]}")
    grants = sql(ctx, "select table_name, privilege_type from information_schema.role_table_grants "
                      "where grantee='anon' and table_schema='public' and table_name in ('user_recipes','qa_results')")
    if grants: finding(ctx, f"anon still holds table grants (RLS blocks them; revoke for defence in depth): {sorted({g['table_name'] for g in grants})}")
    return f"{len(b)} storage bucket(s), {len(pub)} public; {len(fn)} function(s) lacking search_path"

CHECKS = [
    (["A-SEC-01"], t_rls_every_table), (["A-SEC-02"], t_anon_denied), (["A-SEC-03"], t_other_user),
    (["A-SEC-04"], t_functions), (["A-SEC-05"], t_auth_settings), (["A-SEC-06"], t_storage_and_functions_sql),
]
