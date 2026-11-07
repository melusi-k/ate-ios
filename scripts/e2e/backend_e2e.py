#!/usr/bin/env python3
"""ate backend-e2e: automates Tier A items against the real Supabase project with temporary, admin-created,
pre-confirmed users (no emails sent). Writes build/e2e/results.json and (with --upload) qa_results rows (source='ci').

Secrets: SUPABASE_ACCESS_TOKEN (Management API) -> anon + service_role keys fetched at runtime. Fail closed:
exception text and tracebacks are never logged (only the type name plus the check and line it failed at),
because they can carry credentials and redaction cannot be proven complete
(py/clear-text-logging-sensitive-data). Console output is a static check-id + status line: CodeQL does not
treat scrub() as a sanitizer, so check-authored notes are never printed - they are scrubbed (registered secrets
in raw/JSON-escaped/URL-encoded form, plus linear-time JWT/Bearer/key=value patterns and a linear
quoted-key/value scanner) and written only to results.json, summary.md and qa_results, as before. Residual
risk: a secret transformed upstream into an unregistered, unmatched form inside a stored note could persist in
those artifacts - review any new check that handles credentials.
"""
import argparse, json, os, re, sys, time, uuid, urllib.error, urllib.parse, urllib.request

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


REDACTED = "[redacted]"
_SENSITIVE_VALUES = set()


def register_secret(value, known_vector=False):
    """Register a runtime secret so scrub() strips it from every logged output.

    Values shorter than 6 chars are ignored so common substrings are never blanked out,
    unless known_vector=True marks an intentional short test vector (its exact form is
    then scrubbed wherever it appears - deliberately fail-safe, may mangle lookalikes).
    """
    if isinstance(value, str) and value and (len(value) >= 6 or known_vector):
        _SENSITIVE_VALUES.add(value)


# Secret shapes redacted even when the exact value was never registered (e.g. a token echoed
# inside an upstream response body). Regex safety (py/redos): repeats are either bounded (JWT
# segments capped at 4096 chars, far beyond real tokens, which caps backtracking on adversarial
# "eyJeyJ..." runs) or a single unanchored repeat with no following required pattern (Bearer,
# key=value). No nested quantifiers, no ambiguous alternation.
_SCRUB_PATTERNS = [
    # JWTs (Supabase access/refresh/anon/service tokens): header.payload.signature
    (re.compile(r"eyJ[A-Za-z0-9_-]{8,4096}\.[A-Za-z0-9_-]{8,4096}\.[A-Za-z0-9_-]{4,4096}"), REDACTED),
    # Authorization: Bearer <token>
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}"), r"\1" + REDACTED),
    # key=value forms in URLs and error text: password=..., refresh_token=..., ...
    (re.compile(r"(?i)\b((?:password|passwd|pwd|secret|api[-_]?key|apikey|access[-_]?token|refresh[-_]?token)=)[^\s&]{3,}"), r"\1" + REDACTED),
]

# Quoted "key": "value" pairs (JSON or dict-repr) are redacted by a hand-written linear
# scanner, not a regex: quote-aware value matching with escapes cannot be expressed without
# ambiguous alternation or backreference lookaheads.
_SENSITIVE_KEYS = ("password", "passwd", "pwd", "secret", "api_key", "api-key", "apikey",
                   "access_token", "access-token", "refresh_token", "refresh-token", "authorization")


def _match_quoted_kv(text, i):
    """If text[i] starts a quoted sensitive 'key': "value" pair, return (end, redacted text) with
    end just past the redacted region; else None. Keys are compared by lowercasing only the
    fixed-length candidate slice - never a lowercased copy of the whole text, whose length can
    differ (e.g. "İ".lower() is two chars) and misalign every later index, missing real keys.
    The value walk is linear: a backslash skips the next char, the opening quote char closes
    the value. Unterminated values redact to end (fail closed)."""
    n = len(text); c = text[i]
    for key in _SENSITIVE_KEYS:
        if i + 1 + len(key) >= n or text[i + 1:i + 1 + len(key)].lower() != key or text[i + 1 + len(key)] != c:
            continue
        k = i + 2 + len(key)
        while k < n and text[k] in " \t": k += 1
        if k >= n or text[k] != ":": continue
        k += 1
        while k < n and text[k] in " \t": k += 1
        if k >= n or text[k] not in "'\"": continue
        q = text[k]; v = k + 1
        while v < n:
            if text[v] == "\\": v += 2; continue
            if text[v] == q: break
            v += 1
        closed = v < n
        return (v + 1 if closed else n), text[i:k + 1] + REDACTED + (q if closed else "")
    return None


def _redact_quoted_kv(text):
    out = []; i = 0; n = len(text)  # per-char O(1): key probes compare fixed-length slices only
    while i < n:
        m = _match_quoted_kv(text, i) if text[i] in "'\"" else None
        if m:
            end, red = m; out.append(red); i = end
        else:
            out.append(text[i]); i += 1
    return "".join(out)


def _variants(value):
    """Exact forms a registered secret can take in log text: raw, JSON-escaped, URL-encoded."""
    forms = {value, json.dumps(value)[1:-1], urllib.parse.quote(value, safe=""), urllib.parse.quote_plus(value)}
    return sorted(forms, key=len, reverse=True)


def scrub(text):
    """Return text with every secret-shaped value and every registered secret (raw, JSON-escaped
    and URL-encoded forms) redacted. Shape patterns run BEFORE registered-value replacement: a
    short registered vector (e.g. "abc") could otherwise split a JWT and leave its tail logged."""
    if not isinstance(text, str):
        text = str(text)
    for pattern, repl in _SCRUB_PATTERNS:
        text = pattern.sub(repl, text)
    text = _redact_quoted_kv(text)
    for v in sorted(_SENSITIVE_VALUES, key=len, reverse=True):
        for form in _variants(v):
            text = text.replace(form, REDACTED)
    return text


# Fail closed on the exception path: only the exception type name plus a fixed message is ever
# logged. Raw exception text and tracebacks can carry response bodies, echoed URLs or source-line
# literals containing credentials, and CodeQL does not treat scrub() as a sanitizer - so neither
# is emitted. scrub() stays as defence in depth on the pass path (check-authored return notes).
_WITHHELD = "(details withheld: exception text may contain credentials)"


def fail_closed(where, exc):
    """Fail closed for setup/cleanup errors (these run outside run_check): exception type name
    plus a fixed message on stderr, no exception text, no traceback. Request-URL errors land here."""
    sys.stderr.write(f"{where}: {type(exc).__name__} {_WITHHELD}\n")
    raise SystemExit(1)


def run_check(ctx, results, ids, fn, *args):
    """Run one check and record per-id results. Failures record only the exception type name,
    check name and innermost frame location. The console line is static - ids and status only:
    CodeQL does not treat scrub() as a sanitizer, so check-authored notes are never printed.
    Notes (scrubbed, capped at 400 chars) live in results.json, summary.md and qa_results."""
    try: note = fn(ctx, *args); st = "pass"
    except Exception as e:
        # Diagnosable without exception text: check name + innermost frame function:line.
        tb = e.__traceback__
        while tb and tb.tb_next: tb = tb.tb_next
        at = f" at {tb.tb_frame.f_code.co_name}:{tb.tb_lineno}" if tb else ""
        note = f"{type(e).__name__} in {getattr(fn, '__name__', '?')}{at} {_WITHHELD}"; st = "fail"
    note = "" if note is None else scrub(str(note))[:400]  # every current check returns a str; None stays clean
    for i in ids: results[i] = {"status": st, "note": note}
    # Static shape only: ids are code constants, st is a "pass"/"fail" literal. Nothing derived
    # from fn return values, response bodies or exception objects reaches this sink.
    print(f"{'✅' if st == 'pass' else '❌'} {', '.join(ids)}: {st}")


class Ctx:
    def __init__(self):
        tok = os.environ["SUPABASE_ACCESS_TOKEN"]
        register_secret(tok)
        self.mgmt = {"Authorization": f"Bearer {tok}"}
        code, keys = http("GET", f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true", self.mgmt)
        assert code == 200, f"api-keys {code}"
        k = {x["name"]: x["api_key"] for x in keys if x.get("type") == "legacy"}
        self.anon, self.service = k["anon"], k["service_role"]
        register_secret(self.anon); register_secret(self.service)
        # Intentional, CI-only: echoing each key as ::add-mask:: is GitHub's masking mechanism -
        # the runner then masks the value in all log output. Runs only under GITHUB_ACTIONS.
        for v in (self.anon, self.service):
            if os.environ.get("GITHUB_ACTIONS"): print(f"::add-mask::{v}")
        self.users = []; self.slugs = []

    def svc(self):
        return {"apikey": self.service, "Authorization": f"Bearer {self.service}"}

    def anon_h(self, bearer=None):
        return {"apikey": self.anon, "Authorization": f"Bearer {bearer or self.anon}"}

    def new_user(self, password="Ate-e2e-" + uuid.uuid4().hex[:10] + "1"):
        register_secret(password)
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
        register_secret(j.get("access_token")); register_secret(j.get("refresh_token"))
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
    # Weak password is rejected before any email is sent. The intentional weak vectors are
    # registered (short allowed for known vectors) so an upstream echo can never log them.
    register_secret("abc", known_vector=True); register_secret("onlyletters", known_vector=True)
    code, j = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": f"ate-e2e+weak{uuid.uuid4().hex[:8]}@example.com", "password": "abc"})
    assert code in (400, 422) and "weak" in json.dumps(j).lower(), f"weak signup {code} {j}"
    code, j2 = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": f"ate-e2e+weak{uuid.uuid4().hex[:8]}@example.com", "password": "onlyletters"})
    assert code in (400, 422), f"letters-only signup {code} {j2}"
    # Duplicate (already confirmed) email: Supabase fakes success with an empty identities array; the app keys off that.
    u = ctx.new_user()
    dup_password = "Another-pass-123"  # synthetic e2e vector, registered so it can never reach logs
    register_secret(dup_password)
    code, j = http("POST", f"{URL}/auth/v1/signup", ctx.anon_h(), {"email": u["email"], "password": dup_password})
    ids = (j or {}).get("identities", (j or {}).get("user", {}).get("identities")) if isinstance(j, dict) else None
    assert code == 200 and ids == [], f"duplicate signup {code} identities={ids}"
    # The note is a constant: config values read under password-named keys (CodeQL name-taint)
    # never leave this function. The actual minimum stays enforced by the asserts above.
    return "min length >= 8 enforced, letters+digits required; weak/letters-only passwords rejected (weak_password); duplicate email → 200 with identities=[]"


def t_auth06(ctx):
    u = ctx.new_user(); s = ctx.sign_in(u)
    code, j = http("POST", f"{URL}/auth/v1/token?grant_type=refresh_token", ctx.anon_h(), {"refresh_token": s["refresh_token"]})
    assert code == 200 and j.get("access_token") and j["refresh_token"] != s["refresh_token"], f"refresh {code}"
    register_secret(j.get("access_token")); register_secret(j.get("refresh_token"))
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

        # Hosted unknown-slug contract: the browser must show a not-found state, not a blank page.
        unknown = "missing" + uuid.uuid4().hex[:12]
        not_found = b.new_page(user_agent=IPHONE_UA, viewport={"width": 390, "height": 844})
        not_found.goto(SHARE_PAGE + unknown, wait_until="networkidle")
        not_found_body = not_found.locator("body").inner_text(timeout=20000).lower()
        # The hosted page uses an explicit unavailable state rather than necessarily
        # saying "not found". Require both a known not-found heading and recovery guidance
        # so a blank page or generic shell text cannot satisfy this acceptance check.
        has_not_found_state = any(marker in not_found_body for marker in (
            "not found", "could not find", "couldn't find", "doesn't exist",
            "this recipe isn't on the table anymore",
        ))
        has_recovery_guidance = any(marker in not_found_body for marker in (
            "link may have expired", "been removed", "been mistyped",
        ))
        assert has_not_found_state and has_recovery_guidance, (
            "hosted unknown-slug page lacks the explicit unavailable state and guidance: "
            f"{not_found_body[:500]!r}"
        )
        not_found.close()

        # Fault-inject only the public lookup function. The browser must show a retryable
        # failure and must not fall back to directly enumerating/reading shared_recipes.
        outage = b.new_page(user_agent=IPHONE_UA, viewport={"width": 390, "height": 844})
        intercepted = {"lookup": 0, "postgrest": 0}
        def route_share_api(route):
            url = route.request.url
            if "/rest/v1/shared_recipes" in url:
                intercepted["postgrest"] += 1
            if "/functions/v1/get-shared-recipe" in url:
                intercepted["lookup"] += 1
                route.fulfill(status=503, content_type="application/json",
                              body=json.dumps({"error": "temporarily unavailable", "retryable": True}))
            else:
                route.continue_()
        outage.route("**/*", route_share_api)
        outage.goto(SHARE_PAGE + slug, wait_until="networkidle")
        outage_body = outage.locator("body").inner_text(timeout=20000).lower()
        assert intercepted["lookup"] > 0, "hosted page did not call get-shared-recipe during outage test"
        assert intercepted["postgrest"] == 0, "hosted page fell back to direct shared_recipes PostgREST access"
        assert any(s in outage_body for s in ("retry", "try again", "temporarily unavailable", "could not load", "couldn't load")), f"hosted outage page lacks retryable error state: {outage_body[:500]!r}"
        outage.close()
        b.close()
    return (f"published {slug}; valid recipe and Open in Ate link; hosted unknown slug has explicit not-found state; "
            "503 lookup outage shows retryable error without PostgREST fallback")


def owner_id(ctx):
    if os.environ.get("ATE_QA_OWNER_ID"): return os.environ["ATE_QA_OWNER_ID"]
    code, j = http("GET", f"{URL}/rest/v1/qa_results?select=user_id&source=eq.device&order=ts.desc&limit=1", ctx.svc())
    return j[0]["user_id"] if code == 200 and j else None


def upload(ctx, results, build, run_url):
    uid = owner_id(ctx)
    if not uid: print("no owner with device results yet; skipping upload"); return
    rows = [{"user_id": uid, "build": build, "item_id": i, "status": r["status"], "note": r["note"][:400], "auto": True,
             "source": "ci", "run_url": run_url, "commit_sha": os.environ.get("GITHUB_SHA"),
             "run_id": int(os.environ["GITHUB_RUN_ID"]) if os.environ.get("GITHUB_RUN_ID", "").isdigit() else None,
             "run_number": int(os.environ["GITHUB_RUN_NUMBER"]) if os.environ.get("GITHUB_RUN_NUMBER", "").isdigit() else None,
             "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())} for i, r in results.items()]
    h = {**ctx.svc(), "Prefer": "resolution=merge-duplicates,return=minimal"}
    code, j = http("POST", f"{URL}/rest/v1/qa_results?on_conflict=user_id,build,item_id,source", h, rows)
    print(f"qa_results upload: {code} ({len(rows)} rows)")  # response body never logged: it can echo row content


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true"); ap.add_argument("--extra", help="JSON results file to merge (e.g. simulator items)")
    ap.add_argument("--no-checks", action="store_true", help="only upload --extra (simulator/release jobs)")
    ap.add_argument("--out", default="build/e2e"); ap.add_argument("--build", default=os.environ.get("ATE_BUILD_LABEL", "ci"))
    a = ap.parse_args()
    try: ctx = Ctx()
    except Exception as e: fail_closed("e2e setup failed", e)
    results = {}
    def run(ids, fn, *args):
        run_check(ctx, results, ids, fn, *args)
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
        if not a.no_checks:
            try: ctx.cleanup()
            except Exception as e: fail_closed("e2e cleanup failed", e)
    if a.extra and os.path.exists(a.extra): results.update(json.load(open(a.extra)))
    os.makedirs(a.out, exist_ok=True)
    json.dump(results, open(os.path.join(a.out, "results.json"), "w"), indent=2)
    with open(os.path.join(a.out, "summary.md"), "w") as f:
        f.write("### backend-e2e\n\n| Item | Result | Note |\n|---|---|---|\n")
        for i, r in sorted(results.items()): f.write(f"| {i} | {'✅' if r['status']=='pass' else '❌'} {r['status']} | {r['note'].replace('|','/')} |\n")
        if getattr(ctx, "findings", None):
            f.write("\n#### Security review: open findings\n\n" + "".join(f"- {scrub(x)}\n" for x in ctx.findings))
    if a.upload:
        run_url = os.environ.get("GITHUB_SERVER_URL", "") and f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
        upload(ctx, results, a.build, run_url or None)
    sys.exit(1 if any(r["status"] == "fail" for r in results.values()) else 0)


if __name__ == "__main__":
    main()
