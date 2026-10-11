#!/usr/bin/env python3
"""ate backend-e2e: automates Tier A items against the real Supabase project with temporary, admin-created,
pre-confirmed users (no emails sent). Writes build/e2e/results.json and (with --upload) qa_results rows (source='ci').

Secrets: SUPABASE_ACCESS_TOKEN (Management API) -> anon + service_role keys fetched at runtime. Never printed.
"""
import argparse, json, os, sys, time, traceback, uuid, urllib.request, urllib.error

REF = os.environ.get("SUPABASE_PROJECT_REF", "ploncuhexmwydjxljuhe")
URL = f"https://{REF}.supabase.co"
SHARE_PAGE = os.environ.get("ATE_SHARE_PAGE", "https://melusi-k.github.io/ate-legal/r/?s=")
HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "..", "AteTests", "Fixtures", "sync_fixtures.json")
IPHONE_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1")


def http(method, url, headers=None, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    h = {"User-Agent": "ate-backend-e2e", **(headers or {})}
    if data is not None: h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(); code = r.status
    except urllib.error.HTTPError as e:
        raw = e.read(); code = e.code
    try: j = json.loads(raw) if raw else None
    except Exception: j = raw.decode(errors="replace")
    return code, j


class Ctx:
    def __init__(self):
        tok = os.environ["SUPABASE_ACCESS_TOKEN"]
        self.mgmt = {"Authorization": f"Bearer {tok}"}
        code, keys = http("GET", f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true", self.mgmt)
        assert code == 200, f"api-keys {code}"
        k = {x["name"]: x["api_key"] for x in keys if x.get("type") == "legacy"}
        self.anon, self.service = k["anon"], k["service_role"]
        for v in (self.anon, self.service):
            if os.environ.get("GITHUB_ACTIONS"): print(f"::add-mask::{v}")
        self.users = []; self.slugs = []

    def svc(self):
        return {"apikey": self.service, "Authorization": f"Bearer {self.service}"}

    def anon_h(self, bearer=None):
        return {"apikey": self.anon, "Authorization": f"Bearer {bearer or self.anon}"}

    def new_user(self, password="Ate-e2e-" + uuid.uuid4().hex[:10] + "1"):
        email = f"ate-e2e+{uuid.uuid4().hex[:12]}@example.com"
        code, j = http("POST", f"{URL}/auth/v1/admin/users", self.svc(),
                       {"email": email, "password": password, "email_confirm": True,
                        "user_metadata": {"ate_e2e": True}})
        assert code in (200, 201), f"admin create user {code} {j}"
        self.users.append(j["id"])
        return {"id": j["id"], "email": email, "password": password}

    def sign_in(self, u):
        code, j = http("POST", f"{URL}/auth/v1/token?grant_type=password", self.anon_h(),
                       {"email": u["email"], "password": u["password"]})
        assert code == 200, f"password grant {code} {j}"
        return j

    def cleanup(self):
        for s in self.slugs:
            http("DELETE", f"{URL}/rest/v1/shared_recipes?slug=eq.{s}", self.svc())
        for uid in self.users:
            http("DELETE", f"{URL}/rest/v1/user_recipes?user_id=eq.{uid}", self.svc())
            http("DELETE", f"{URL}/auth/v1/admin/users/{uid}", self.svc())
        # Sweep leftovers from crashed runs.
        code, j = http("GET", f"{URL}/auth/v1/admin/users?per_page=200", self.svc())
        for u in (j or {}).get("users", []) if isinstance(j, dict) else []:
            if (u.get("email") or "").startswith("ate-e2e+"):
                http("DELETE", f"{URL}/auth/v1/admin/users/{u['id']}", self.svc())


# ---------- sync helpers (port of SyncMerge.merge in Ate/Services/Sync.swift) ----------
def merge(local, remote):
    data, stamps, tomb = dict(local["data"]), dict(local["stamps"]), dict(local["tombstones"])
    rstamp = {}
    for r in remote:
        rstamp[r["id"]] = r["updated_at"]
        ls = round(max(stamps.get(r["id"], -1), tomb.get(r["id"], -1)))
        if not r["updated_at"] > ls: continue
        if r["deleted"]:
            data.pop(r["id"], None); stamps.pop(r["id"], None); tomb[r["id"]] = r["updated_at"]
        elif r.get("data") is not None:
            data[r["id"]] = r["data"]; stamps[r["id"]] = r["updated_at"]; tomb.pop(r["id"], None)
    push = sorted(k for k in data if round(stamps.get(k, 0)) > rstamp.get(k, -1))
    pdel = sorted(k for k in tomb if round(tomb.get(k, 0)) > rstamp.get(k, -1))
    return {"data": data, "stamps": stamps, "tombstones": tomb, "push": push, "pushDeletes": pdel}


def rows_for(uid, ids, res):
    out = []
    for i in ids["push"]:
        out.append({"user_id": uid, "kind": "recipe", "id": i, "data": res["data"][i], "updated_at": int(res["stamps"][i]), "deleted": False})
    for i in ids["pushDeletes"]:
        out.append({"user_id": uid, "kind": "recipe", "id": i, "data": None, "updated_at": int(res["tombstones"][i]), "deleted": True})
    return out


def upsert(ctx, token, rows):
    h = {**ctx.anon_h(token), "Prefer": "resolution=merge-duplicates,return=minimal"}
    return http("POST", f"{URL}/rest/v1/user_recipes?on_conflict=user_id,kind,id", h, rows)


def pull(ctx, token, uid):
    code, j = http("GET", f"{URL}/rest/v1/user_recipes?select=id,data,updated_at,deleted&kind=eq.recipe&user_id=eq.{uid}", ctx.anon_h(token))
    assert code == 200, f"pull {code} {j}"
    return j


# ---------- checks ----------
def t_auth02(ctx):
    code, cfg = http("GET", f"https://api.supabase.com/v1/projects/{REF}/config/auth", ctx.mgmt)
    assert code == 200, f"config/auth {code}"
    mn, chars = cfg.get("password_min_length"), cfg.get("password_required_characters") or ""
    assert mn and mn >= 8, f"password_min_length={mn}"
    assert "abcdefghijklmnopqrstuvwxyz" in chars.lower() and "0123456789" in chars, f"required chars={chars!r}"
    # Weak password is rejected before any email is sent.
    code, j = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": f"ate-e2e+weak{uuid.uuid4().hex[:8]}@example.com", "password": "abc"})
    assert code in (400, 422) and "weak" in json.dumps(j).lower(), f"weak signup {code} {j}"
    code, j2 = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": f"ate-e2e+weak{uuid.uuid4().hex[:8]}@example.com", "password": "onlyletters"})
    assert code in (400, 422), f"letters-only signup {code} {j2}"
    # Duplicate (already confirmed) email: Supabase fakes success with an empty identities array; the app keys off that.
    u = ctx.new_user()
    code, j = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": u["email"], "password": "Another-pass-123"})
    ids = (j or {}).get("identities", (j or {}).get("user", {}).get("identities")) if isinstance(j, dict) else None
    assert code == 200 and ids == [], f"duplicate signup {code} identities={ids}"
    return f"min {mn}, letters+digits required; weak/letters-only passwords rejected (weak_password); duplicate email → 200 with identities=[]"


def t_auth06(ctx):
    u = ctx.new_user(); s = ctx.sign_in(u)
    code, j = http("POST", f"{URL}/auth/v1/token?grant_type=refresh_token", ctx.anon_h(), {"refresh_token": s["refresh_token"]})
    assert code == 200 and j.get("access_token") and j["refresh_token"] != s["refresh_token"], f"refresh {code}"
    upsert(ctx, j["access_token"], [{"user_id": u["id"], "kind": "recipe", "id": "after-refresh", "data": {"t": 1}, "updated_at": 1, "deleted": False}])
    assert any(r["id"] == "after-refresh" for r in pull(ctx, j["access_token"], u["id"])), "refreshed token can't sync"
    code, _ = http("GET", f"{URL}/rest/v1/user_recipes?select=id", ctx.anon_h("not-a-jwt"))
    assert code in (401, 403), f"garbage token accepted {code}"
    return "refresh_token grant rotates tokens; refreshed session syncs; invalid token → 401"


def t_auth07(ctx):
    u = ctx.new_user(); a = ctx.sign_in(u)["access_token"]; b = ctx.sign_in(u)["access_token"]
    assert a != b
    upsert(ctx, a, [{"user_id": u["id"], "kind": "recipe", "id": "from-a", "data": {"t": "A"}, "updated_at": 10, "deleted": False}])
    upsert(ctx, b, [{"user_id": u["id"], "kind": "recipe", "id": "from-b", "data": {"t": "B"}, "updated_at": 11, "deleted": False}])
    ia = {r["id"] for r in pull(ctx, a, u["id"])}; ib = {r["id"] for r in pull(ctx, b, u["id"])}
    assert ia == ib == {"from-a", "from-b"}, f"{ia} {ib}"
    # RLS: another user sees none of it
    other = ctx.sign_in(ctx.new_user())["access_token"]
    code, j = http("GET", f"{URL}/rest/v1/user_recipes?select=id&user_id=eq.{u['id']}", ctx.anon_h(other))
    assert code == 200 and j == [], f"RLS leak {j}"
    return "two live sessions for one user both push and pull each other's rows; other users see nothing (RLS)"


def t_sync(ctx):
    fx = json.load(open(FIXTURES))["scenarios"]
    u = ctx.new_user(); dev_a = ctx.sign_in(u)["access_token"]; dev_b = ctx.sign_in(u)["access_token"]
    notes = []
    for sc in fx:
        # namespace ids per scenario so they don't collide on the server
        p = sc["name"][:12] + "-"
        ren = lambda d: {p + k: v for k, v in d.items()}
        local = {"data": ren(sc["local"]["data"]), "stamps": ren(sc["local"]["stamps"]), "tombstones": ren(sc["local"]["tombstones"])}
        remote = [{**r, "id": p + r["id"]} for r in sc["remote"]]
        # device B wrote the remote state
        code, j = upsert(ctx, dev_b, [{"user_id": u["id"], "kind": "recipe", **r} for r in remote])
        assert code in (200, 201, 204), f"{sc['name']} seed {code} {j}"
        # device A pulls, merges, pushes
        server = [r for r in pull(ctx, dev_a, u["id"]) if r["id"].startswith(p)]
        res = merge(local, server)
        exp = sc["expect"]
        assert res["data"] == ren(exp["data"]), f"{sc['name']} data {res['data']}"
        assert sorted(res["tombstones"]) == sorted(p + t for t in exp["tombstones"]), f"{sc['name']} tomb"
        assert res["push"] == [p + x for x in exp["push"]] and res["pushDeletes"] == [p + x for x in exp["pushDeletes"]], f"{sc['name']} push {res['push']} {res['pushDeletes']}"
        rows = rows_for(u["id"], res, res)
        if rows:
            code, j = upsert(ctx, dev_a, rows); assert code in (200, 201, 204), f"{sc['name']} push {code} {j}"
            code, j = upsert(ctx, dev_a, rows); assert code in (200, 201, 204), f"{sc['name']} idempotent re-push {code} {j}"
        # device B pulls and converges to A's view
        after = {r["id"]: r for r in pull(ctx, dev_b, u["id"]) if r["id"].startswith(p)}
        for k, v in res["data"].items():
            assert after[k]["data"] == v and not after[k]["deleted"], f"{sc['name']} B sees {after.get(k)}"
        for k in res["pushDeletes"]:
            assert after[k]["deleted"], f"{sc['name']} tombstone not propagated"
        again = merge({"data": res["data"], "stamps": res["stamps"], "tombstones": res["tombstones"]}, list(after.values()))
        assert not again["push"] and not again["pushDeletes"], f"{sc['name']} second sync not a no-op"
        notes.append(sc["name"])
    # duplicate id in one batch must fail cleanly (PostgREST 21000) rather than corrupt
    code, _ = upsert(ctx, dev_a, [{"user_id": u["id"], "kind": "recipe", "id": "dup", "data": {"v": 1}, "updated_at": 1, "deleted": False}] * 2)
    assert code >= 400, f"duplicate ids in one batch accepted {code}"
    return f"{len(notes)} fixture scenarios converge across two clients (LWW, tombstones, idempotent re-push, stale refs); in-batch dup id rejected"


SAMPLE = {"title": "E2E Chakalaka", "description": "CI share check", "servings": 4, "timeMinutes": 30, "tags": ["ci"],
          "ingredients": [{"name": "baked beans", "quantity": 1, "unit": "can", "notes": ""},
                          {"name": "carrots", "quantity": 2, "unit": "", "notes": "grated"}],
          "steps": [{"order": 1, "instruction": "Fry the onion and peppers.", "timeSeconds": 300},
                    {"order": 2, "instruction": "Add carrots and beans, simmer.", "timeSeconds": 600}],
          "imageURL": "http://insecure.example.com/x.jpg"}


def t_delete_account(ctx):
    """Verify the production delete endpoint removes only the disposable caller's cloud data."""
    victim = ctx.new_user()
    token = ctx.sign_in(victim)["access_token"]
    marker = "delete-e2e-" + uuid.uuid4().hex[:12]
    code, j = upsert(ctx, token, [{"user_id": victim["id"], "kind": "recipe", "id": marker,
                                   "data": {"title": "Deletion test"}, "updated_at": 1, "deleted": False}])
    assert code in (200, 201, 204), f"seed deletion test recipe {code} {j}"
    card = {"title": "Delete E2E " + uuid.uuid4().hex[:8], "servings": 1,
            "ingredients": [{"name": "test", "quantity": 1, "unit": "", "notes": ""}],
            "steps": [{"order": 1, "instruction": "test", "timeSeconds": None}]}
    code, j = http("POST", f"{URL}/functions/v1/publish-recipe", ctx.anon_h(token), {"card": card})
    assert code == 200 and j.get("slug"), f"seed deletion test share {code} {j}"
    share_slug = j["slug"]
    ctx.slugs.append(share_slug)
    code, j = http("POST", f"{URL}/functions/v1/delete-account", ctx.anon_h(token), {})
    assert code == 200 and j.get("deleted") is True, f"delete-account success path {code} {j}"
    code, rows = http("GET", f"{URL}/rest/v1/user_recipes?select=id&user_id=eq.{victim['id']}", ctx.svc())
    assert code == 200 and not rows, f"account deletion left synced recipes: {rows}"
    code, rows = http("GET", f"{URL}/rest/v1/shared_recipes?select=slug&slug=eq.{share_slug}", ctx.svc())
    assert code == 200 and not rows, f"account deletion left shares: {rows}"
    code, _ = http("GET", f"{URL}/auth/v1/admin/users/{victim['id']}", ctx.svc())
    assert code == 404, f"account still exists after deletion: {code}"
    return "synced recipe and share removed, then disposable Auth user deleted"


def t_share(ctx, shots):
    card = {**SAMPLE, "title": f"E2E Chakalaka {uuid.uuid4().hex[:6]}"}
    tok = ctx.sign_in(ctx.new_user())["access_token"]  # signed-in share, like the app
    code, j = http("POST", f"{URL}/functions/v1/publish-recipe", ctx.anon_h(tok), {"card": card})
    assert code == 200 and j.get("slug"), f"publish {code} {j}"
    slug = j["slug"]; ctx.slugs.append(slug)
    code, row = http("GET", f"{URL}/rest/v1/shared_recipes?slug=eq.{slug}&select=image_url,card", ctx.svc())
    assert row and row[0]["image_url"] is None and row[0]["card"].get("imageURL") is None, f"http cover kept: {row}"
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(user_agent=IPHONE_UA, viewport={"width": 390, "height": 844})
        pg.goto(SHARE_PAGE + slug, wait_until="networkidle")
        pg.wait_for_function("t => document.body.innerText.includes(t)", arg=card["title"], timeout=20000)
        body = pg.inner_text("body")
        for t in [card["title"], "baked beans", "carrots", "Fry the onion", "simmer"]:
            assert t in body, f"share page missing {t!r}"
        hrefs = pg.eval_on_selector_all("a", "els => els.map(e => [e.innerText.trim(), e.getAttribute('href')])")
        opener = [h for t, h in hrefs if "open in ate" in t.lower()]
        assert opener and opener[0] == f"ate://recipe/{slug}", f"Open in ate href {opener} (all: {hrefs[:8]})"
        os.makedirs(shots, exist_ok=True); pg.screenshot(path=os.path.join(shots, "share-page-iphone.png"), full_page=True)
        b.close()
    return f"published {slug} (http cover dropped); page renders title/ingredients/steps; Open in ate → ate://recipe/{slug}"


def owner_id(ctx):
    if os.environ.get("ATE_QA_OWNER_ID"): return os.environ["ATE_QA_OWNER_ID"]
    code, j = http("GET", f"{URL}/rest/v1/qa_results?select=user_id&source=eq.device&order=ts.desc&limit=1", ctx.svc())
    return j[0]["user_id"] if code == 200 and j else None


def upload(ctx, results, build, run_url):
    uid = owner_id(ctx)
    if not uid: print("no owner with device results yet; skipping upload"); return
    rows = [{"user_id": uid, "build": build, "item_id": i, "status": r["status"], "note": r["note"][:400], "auto": True,
             "source": "ci", "run_url": run_url, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())} for i, r in results.items()]
    h = {**ctx.svc(), "Prefer": "resolution=merge-duplicates,return=minimal"}
    code, j = http("POST", f"{URL}/rest/v1/qa_results?on_conflict=user_id,build,item_id,source", h, rows)
    print(f"qa_results upload: {code} ({len(rows)} rows)" + ("" if code < 300 else f" {j}"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true"); ap.add_argument("--extra", help="JSON results file to merge (e.g. simulator items)")
    ap.add_argument("--no-checks", action="store_true", help="only upload --extra (simulator/release jobs)")
    ap.add_argument("--out", default="build/e2e"); ap.add_argument("--build", default=os.environ.get("ATE_BUILD_LABEL", "ci"))
    a = ap.parse_args()
    ctx = Ctx(); results = {}
    def run(ids, fn, *args):
        try: note = fn(ctx, *args); st = "pass"
        except Exception as e: note = f"{type(e).__name__}: {e}"[:400]; st = "fail"; traceback.print_exc()
        for i in ids: results[i] = {"status": st, "note": note}
        print(f"{'✅' if st == 'pass' else '❌'} {', '.join(ids)}: {note}")
    try:
        if a.no_checks: raise StopIteration
        run(["A-AUTH-02"], t_auth02)
        run(["A-AUTH-06"], t_auth06)
        run(["A-AUTH-07"], t_auth07)
        run(["A-SYNC-02", "A-SYNC-03"], t_sync)
        run(["A-SHARE-03", "A-SHARE-04"], t_share, os.path.join(a.out, "screens"))
        run(["A-SEC-07"], t_delete_account)
        import security_checks
        for ids, fn in security_checks.CHECKS: run(ids, fn)
    except StopIteration:
        pass
    finally:
        if not a.no_checks: ctx.cleanup()
    if a.extra and os.path.exists(a.extra): results.update(json.load(open(a.extra)))
    os.makedirs(a.out, exist_ok=True)
    json.dump(results, open(os.path.join(a.out, "results.json"), "w"), indent=2)
    with open(os.path.join(a.out, "summary.md"), "w") as f:
        f.write("### backend-e2e\n\n| Item | Result | Note |\n|---|---|---|\n")
        for i, r in sorted(results.items()): f.write(f"| {i} | {'✅' if r['status']=='pass' else '❌'} {r['status']} | {r['note'].replace('|','/')} |\n")
        if getattr(ctx, "findings", None):
            f.write("\n#### Security review: open findings\n\n" + "".join(f"- {x}\n" for x in ctx.findings))
    if a.upload:
        run_url = os.environ.get("GITHUB_SERVER_URL", "") and f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
        upload(ctx, results, a.build, run_url or None)
    sys.exit(1 if any(r["status"] == "fail" for r in results.values()) else 0)


if __name__ == "__main__":
    main()
