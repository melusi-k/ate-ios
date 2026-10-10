#!/usr/bin/env python3
"""Release-readiness issue generator for ate-ios.

Builds the body of .github/ISSUE_TEMPLATE/release-readiness.md pre-filled from evidence:
  * docs/QA_MATRIX.md status column (Tier A / B IDs)
  * qa_results table in Supabase (device + ci sources), if SUPABASE_ACCESS_TOKEN is set
  * the Build IPA run: job conclusions, unit / QA 8-flow / UI counts from job logs, backend-e2e artifact
  * Known issues from CHANGELOG (⚠️) and blockers from docs/MVP_CHECKLIST.md

Issue logic (idempotent; the key lives in a hidden marker in the body):
  * rolling: one open issue per channel/release line, e.g. "Release readiness: 0.1.x Tier A (Internal beta)".
    Every successful build regenerates its body and adds one "Build N: ..." comment (never twice for a build).
  * rc: workflow_dispatch with a release_type other than Internal beta (or --new) creates/updates a
    per-version issue, e.g. "Release readiness: 0.1.50 (Public beta)".
Release decision + Final signoff checkboxes are always left unchecked; only a SUGGESTION is written.

Local:  python3 scripts/release/readiness.py --dry-run [--run-id N] > /tmp/body.md
"""
import argparse, io, json, os, re, subprocess, sys, urllib.request, zipfile

REPO = os.environ.get("GITHUB_REPOSITORY", "melusi-k/ate-ios")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = os.environ.get("SUPABASE_PROJECT_REF", "ploncuhexmwydjxljuhe")
SERVER = "https://github.com"
OWNER = "@melusi-k"

# checklist item -> evidence ids. "ci:<x>" = from the run (build, unit, ui, qa<n>, e2e, smoke); "doc:<x>" = file check.
MAP = {
 "Add recipe from URL": ["A-CREATE-01", "A-CREATE-02", "ci:qa1"],
 "Add recipe from photo": ["A-CREATE-03", "ci:qa2"],
 "Add recipe from prompt": ["A-CREATE-04"],
 "Review and edit generated recipe before saving": ["A-EDIT-01", "ci:qa3"],
 "Save recipe to library": ["A-EDIT-02", "ci:qa4"],
 "Open saved recipe": ["A-EDIT-02"],
 "Edit saved recipe": ["A-EDIT-03"],
 "Delete recipe": ["A-EDIT-04"],
 "Add recipe to shopping list": ["A-EDIT-03"],
 "Cook recipe with timer": ["A-TIMER-01", "A-TIMER-02", "ci:qa8"],
 "Share recipe": ["A-SHARE-01", "ci:qa5"],
 "Open shared recipe link": ["A-SHARE-02", "A-SHARE-03", "ci:qa6"],
 "App remains usable offline": ["A-OFF-01", "A-OFF-02"],
 "Sign up works": ["A-AUTH-01"],
 "Sign in works": ["A-AUTH-09", "ci:qa7"],
 "Password reset works": ["A-AUTH-05"],
 "Magic link works": ["A-AUTH-04"],
 "Email confirmation flow works": ["A-AUTH-01"],
 "Sign out works": ["A-AUTH-03"],
 "Delete account works": ["A-AUTH-08"],
 "Rate-limited auth fails gracefully": ["A-AUTH-05", "A-AUTH-02"],
 "Expired session handling works": ["A-AUTH-06"],
 "Offline auth errors are understandable": ["A-AUTH-09", "A-OFF-02"],
 "Signed-in users can sync recipes": ["A-SYNC-01", "ci:qa7"],
 "Signed-out users still have full local functionality": ["A-OFF-01"],
 "Sync handles offline mode gracefully": ["A-SYNC-04"],
 "Local library remains stable when sync fails": ["A-SYNC-04", "A-SHARE-05"],
 "Deletions are handled safely": ["A-SYNC-03"],
 "Data integrity is preserved across relaunches": ["A-EDIT-02", "A-SYNC-06"],
 "Repeated sync attempts do not corrupt state": ["A-SYNC-02", "A-SYNC-03"],
 "Account switching does not break data": ["A-SYNC-05"],
 "Recipe publishing works": ["A-SHARE-01"],
 "Shared recipe retrieval works": ["A-SHARE-03"],
 "Deep links open correctly": ["A-SHARE-02", "A-SHARE-04"],
 "Share URL behavior is correct in real conditions": ["A-SHARE-04"],
 "Fallbacks behave gracefully when backend is unavailable": ["A-SHARE-05"],
 "AI parse failures are understandable to the user": ["A-EDIT-05", "A-CREATE-06"],
 "Production share host is correctly configured": ["B-SHARE-01"],
 "Clear empty states": ["A-EDIT-05"],
 "Clear error states": ["A-CREATE-06", "A-AUTH-02"],
 "Clear loading states": ["A-CREATE-05"],
 "Predictable navigation flow": ["A-NAV-01"],
 "Core flows work on a real iPhone": ["A-DEV-01"],
 "Accessibility basics pass": ["B-QA-02"],
 "No obvious crash paths in core flows": ["A-EDIT-03", "A-REL-01", "ci:qa"],
 "App survives backgrounding and relaunch sufficiently": ["A-TIMER-03", "A-CREATE-05"],
 "CI builds successfully": ["A-CI-01", "ci:build"],
 "Unit tests pass": ["ci:unit"],
 "UI tests pass": ["ci:ui"],
 "Version info is correct": ["A-CI-04"],
 "Signed build path works with secrets": ["B-APPLE-02"],
 "Unsigned build path works for sideload testing": ["A-CI-03", "ci:smoke"],
 "Artifact naming is consistent": ["A-CI-01"],
 "No secrets are shipped in the app bundle": ["B-PRIV-03"],
 "Privacy policy is linked and accessible": ["doc:privacy", "B-PRIV-01"],
 "Terms are linked and accessible": ["doc:terms"],
 "User data handling is honest and documented": ["B-PRIV-01"],
 "Delete-account flow is clear": ["A-AUTH-08", "B-PRIV-02"],
 "App does not claim unsupported capabilities": ["B-PRIV-03"],
}
BLOCKERS = [
 ("unresolved", "Universal links need a paid Apple Developer account plus the ate.app domain (B-APPLE-01, B-SHARE-01); `Open in ate` uses the ate:// scheme meanwhile."),
 ("accepted", "Supabase built-in mailer rate-limits confirmation/reset/magic-link emails (~2/hour) until custom SMTP (Resend) is set up, see docs/SMTP.md (A-AUTH-05)."),
 ("fixed", "Lovable web share page reads the old backend; superseded by the GitHub Pages share page melusi-k.github.io/ate-legal/r/ on the new Supabase (A-SHARE-03)."),
 ("accepted", "Apple Watch install needs a paid account or Xcode on a Mac (free-ID sideload fails with an app-integrity error)."),
 ("accepted", "Unsigned sideload builds expire after 7 days on a free Apple ID; signed/TestFlight path needs the paid account (B-APPLE-02)."),
]
DEVICE_ONLY = {"Core flows work on a real iPhone"}


def sh(*a, check=True):
    r = subprocess.run(a, capture_output=True, text=True)
    if check and r.returncode: raise RuntimeError(f"{a[:3]}: {r.stderr[:300]}")
    return r.stdout


def gh_api(path, *extra):
    return json.loads(sh("gh", "api", path, *extra) or "null")


def read(p):
    try: return open(os.path.join(ROOT, p), encoding="utf-8").read()
    except OSError: return ""


def matrix():
    out = {}
    for line in read("docs/QA_MATRIX.md").splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) >= 10 and re.match(r"^[AB]-[A-Z0-9]+-\d+$", c[0]):
            out[c[0]] = {"status": c[8], "journey": c[1], "sim": c[5], "device": c[6]}
    return out


def qa_results():
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not tok: return {}, "qa_results: not read (no SUPABASE_ACCESS_TOKEN)"
    q = ("select distinct on (item_id, source) item_id, source, status, build, note, run_url, ts "
         "from public.qa_results where status <> 'untested' order by item_id, source, ts desc")
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": q}).encode(), method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json", "User-Agent": "ate-readiness"})
    try: rows = json.load(urllib.request.urlopen(req, timeout=30))
    except Exception as e: return {}, f"qa_results: read failed ({e})"
    res = {}
    for r in rows: res.setdefault(r["item_id"], {})[r["source"]] = r
    return res, f"qa_results: {len(rows)} latest rows (device + ci)"


def find_run(run_id):
    if run_id: return gh_api(f"repos/{REPO}/actions/runs/{run_id}")
    runs = gh_api(f"repos/{REPO}/actions/workflows/build-ipa.yml/runs?branch=main&status=success&per_page=1")["workflow_runs"]
    return runs[0] if runs else None


def run_data(run):
    d = {"url": run["html_url"], "id": run["id"], "sha": run["head_sha"][:7], "ci": {}, "counts": {}, "artifacts": []}
    d["ci"]["build"] = "pass" if run.get("conclusion") == "success" else ("fail" if run.get("conclusion") == "failure" else None)
    jobs = gh_api(f"repos/{REPO}/actions/runs/{run['id']}/jobs?per_page=50")["jobs"]
    unit = [0, 0]; ui = [0, 0]; qa = {}
    for j in jobs:
        if j["conclusion"] in ("skipped", None): continue
        log = sh("gh", "api", f"repos/{REPO}/actions/jobs/{j['id']}/logs", check=False)
        for m in re.finditer(r"Test Case '-\[\S+ testQA(\d)_\w+\]' (passed|failed)", log):
            qa[int(m.group(1))] = m.group(2)
        if "ui-suite" in j["name"]:
            for m in re.finditer(r"Test Case '-\[\S+ test\w+\]' (passed|failed)", log):
                ui[0] += 1; ui[1] += m.group(1) == "failed"
        else:
            m = re.search(r"Executed (\d+) tests?, with (\d+) failures?", log)
            if m: unit[0] += int(m.group(1)); unit[1] += int(m.group(2))
        if "ui-suite" in j["name"] and j["conclusion"] == "failure" and not ui[0]: d["ci"]["ui"] = "fail"
        if "Ate alive 10 s after launch" in log: d["ci"]["smoke"] = "pass"
        elif "exited within 10 s of launch" in log: d["ci"]["smoke"] = "fail"
    if unit[0]: d["ci"]["unit"] = "pass" if unit[1] == 0 else "fail"; d["counts"]["unit"] = f"{unit[0]-unit[1]}/{unit[0]}"
    if ui[0]: d["ci"]["ui"] = "pass" if ui[1] == 0 else "fail"; d["counts"]["ui"] = f"{ui[0]-ui[1]}/{ui[0]}"
    if qa:
        for n, s in qa.items(): d["ci"][f"qa{n}"] = "pass" if s == "passed" else "fail"
        d["ci"]["qa"] = "pass" if all(s == "passed" for s in qa.values()) else "fail"
        d["counts"]["qa"] = f"{sum(s == 'passed' for s in qa.values())}/8"
    arts = gh_api(f"repos/{REPO}/actions/runs/{run['id']}/artifacts?per_page=50")["artifacts"]
    for a in arts:
        d["artifacts"].append((a["name"], f"{SERVER}/{REPO}/actions/runs/{run['id']}/artifacts/{a['id']}"))
        if a["name"] in ("backend-e2e",) and not a.get("expired"):
            try:
                z = zipfile.ZipFile(io.BytesIO(subprocess.run(["gh", "api", a["archive_download_url"]], capture_output=True).stdout))
                for n in z.namelist():
                    if n.endswith("results.json"):
                        e2e = json.loads(z.read(n)); d["e2e"] = e2e
                        ok = sum(v["status"] == "pass" for v in e2e.values()); d["counts"]["e2e"] = f"{ok}/{len(e2e)}"
                        d["ci"]["e2e"] = "pass" if ok == len(e2e) else "fail"
            except Exception as ex: print(f"e2e artifact unreadable: {ex}", file=sys.stderr)
    return d


def release_for(sha):
    rels = gh_api(f"repos/{REPO}/releases?per_page=30")
    tier = [r for r in rels if r["tag_name"].startswith("build-")]
    for r in tier:
        if sha and sha in (r["name"] or ""): return r
    return tier[0] if tier else None


def verdict(ids, mx, qr, rd):
    """-> (state, evidence list). state: pass | fail | partial | none"""
    st, ev = [], []
    for i in ids:
        if i.startswith("ci:"):
            k = i[3:]; v = (rd or {}).get("ci", {}).get(k)
            if v: st.append(v); ev.append(f"CI {k} {'✅' if v=='pass' else '❌'}")
            continue
        if i.startswith("doc:"):
            ok = os.path.exists(os.path.join(ROOT, "docs/legal", f"{i[4:]}.md")) or i[4:] in read("README.md").lower()
            st.append("pass" if ok else "none"); ev.append(f"docs/legal/{i[4:]} {'✅' if ok else '⚪'}"); continue
        r = qr.get(i, {}); dv = r.get("device"); cv = r.get("ci")
        if dv: st.append(dv["status"]); ev.append(f"{i} device {dv['status']} ({dv['build']})")
        if cv: st.append(cv["status"]); ev.append(f"{i} ci {cv['status']}")
        if not dv and not cv and i in mx:
            s = mx[i]["status"]; st.append("pass" if s == "✅" else ("blocked" if s == "⛔" else "none")); ev.append(f"{i} matrix {s}")
    if "fail" in st: return "fail", ev
    if st and all(s == "pass" for s in st): return "pass", ev
    if "pass" in st: return "partial", ev
    if "blocked" in st: return "blocked", ev
    return "none", ev


def known_issues():
    t = read("CHANGELOG.md"); m = re.search(r"### ⚠️ Known issues\n(.*?)(?:\n#|\Z)", t, re.S)
    return [l[2:].strip() for l in (m.group(1) if m else "").splitlines() if l.startswith("- ")]


ICON = {"pass": "✅", "fail": "❌", "partial": "🟡", "blocked": "⛔", "none": "⚪"}


def build_body(key, title, rtype, version, mx, qr, qnote, rd, rel):
    tpl = read(".github/ISSUE_TEMPLATE/release-readiness.md")
    tpl = re.sub(r"\A---.*?---\n+", "", tpl, flags=re.S)
    out, section, sec_states, tallies = [], None, {}, {"pass": 0, "fail": 0, "partial": 0, "blocked": 0, "none": 0}
    failing = []
    links = []
    if rd: links.append(f"[run {rd['id']}]({rd['url']})")
    if rel: links.append(f"[release {rel['tag_name']}]({rel['html_url']})")
    if rd:
        links += [f"[{n}]({u})" for n, u in rd["artifacts"] if "screenshot" in n or n == "backend-e2e"]
    links.append(f"[QA_MATRIX]({SERVER}/{REPO}/blob/main/docs/QA_MATRIX.md)")
    issues = known_issues()
    for line in tpl.splitlines():
        m = re.match(r"^### (\d)\. ", line)
        if m: section = m.group(1); sec_states[section] = []
        if line.startswith("## Known blockers"): section = None
        im = re.match(r"^- \[ \] (.+)$", line)
        if im and section:
            item = im.group(1); ids = MAP.get(item, [])
            state, ev = verdict(ids, mx, qr, rd)
            if item in DEVICE_ONLY and state == "partial": state = "none"
            sec_states[section].append(state); tallies[state] += 1
            if state == "fail": failing.append(item)
            ref = ", ".join(x for x in ids if not x.startswith(("ci:", "doc:")))
            out.append(f"- [{'x' if state == 'pass' else ' '}] {item} {ICON[state]} <sub>{ref}{' · ' if ref and ev else ''}{'; '.join(ev)}</sub>")
            continue
        if line.startswith("- Evidence:") and section:
            out.append(f"- Evidence: {' · '.join(links)}"); continue
        if line.startswith("- Known issues:") and section:
            ki = {"1": [x for x in issues if "Unsigned" in x], "2": [x for x in issues if "mail" in x.lower() or "rate" in x.lower()],
                  "4": ["Universal links pending (paid account + domain); ate:// scheme used."], "6": [x for x in issues if "Unsigned" in x]}.get(section, [])
            out.append(f"- Known issues: {'; '.join(ki) or 'none recorded'}"); continue
        if line.startswith("- Severity:") and section:
            s = sec_states[section]
            sev = "High" if "fail" in s else ("Medium" if any(x in ("none", "blocked", "partial") for x in s) else "Low")
            out.append(f"- Severity (suggested): {sev} — {s.count('pass')}/{len(s)} verified, {s.count('fail')} failing"); continue
        if line.startswith("- Target release type:"): out.append(line); continue
        if re.match(r"^  - \[ \] (Internal beta|Public beta|Public launch)$", line):
            out.append(line.replace("[ ]", "[x]") if rtype in line else line); continue
        if line.startswith("- Release date:"):
            out.append(f"- Release date: {(rel or {}).get('published_at', '')[:10] or 'TBD'}"); continue
        if re.match(r"^- Blocker \d:", line):
            if line.startswith("- Blocker 1:"):
                out += [f"- Blocker {n}: **{s}** — {t}" for n, (s, t) in enumerate(BLOCKERS, 1)]
            continue
        if line.startswith("- Blockers remaining:"):
            out.append(f"- Blockers remaining: {sum(s == 'unresolved' for s, _ in BLOCKERS)} unresolved, {sum(s == 'accepted' for s, _ in BLOCKERS)} accepted"); continue
        out.append(line)
    total = sum(tallies.values()); f = tallies["fail"]; unver = tallies["none"] + tallies["partial"] + tallies["blocked"]
    gate = "beta" if rtype != "Public launch" else "public launch"
    if f == 0 and unver == 0: sug, risk = f"Approved for {gate}", "Low"
    elif f == 0 or (rtype == "Internal beta" and f <= 3):
        sug = f"Conditional approval for {rtype}: {f} failing, {unver} not fully verified"; risk = "Medium" if f <= 2 else "High"
    else: sug, risk = f"Not approved for {rtype}: {f} failing, {unver} not fully verified", "High"
    if rtype == "Public launch" and (unver or f): sug, risk = f"Not approved for public launch: {f} failing, {unver} not fully verified", "High"
    body = "\n".join(out)
    body = body.replace("Reason:\n", f"Reason:\n- **Suggested (auto, not a decision):** {sug}. Suggested risk: **{risk}**. "
                        f"Failing: {', '.join(failing) or 'none'}.\n", 1)
    counts = (rd or {}).get("counts", {})
    head = (f"<!-- readiness-key: {key} -->\n> 🤖 Auto-generated by `scripts/release/readiness.py` from "
            f"{' · '.join(links)}. Version **{version}**, commit `{(rd or {}).get('sha','?')}`. "
            f"Legend: ✅ verified · 🟡 partly verified · ❌ failing · ⛔ blocked · ⚪ untested. "
            f"Checked boxes are evidence only; the **Release decision** and **Final signoff** are for a human.\n>\n"
            f"> Tally: {tallies['pass']}/{total} verified, {f} failing, {unver} open · "
            f"unit {counts.get('unit','n/a')} · QA 8-flow {counts.get('qa','n/a')} · UI {counts.get('ui','n/a')} · e2e {counts.get('e2e','n/a')} · {qnote}\n\n")
    return head + body, sug, risk


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release-type", default=os.environ.get("RELEASE_TYPE") or "Internal beta",
                    choices=["Internal beta", "Public beta", "Public launch"])
    ap.add_argument("--version", default=os.environ.get("RC_VERSION") or "")
    ap.add_argument("--run-id", default=os.environ.get("RUN_ID") or "")
    ap.add_argument("--new", action="store_true", help="force a per-RC issue even for Internal beta")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    run = find_run(a.run_id); rd = run_data(run) if run else None
    rel = release_for(rd["sha"] if rd else None)
    m = re.search(r"(\d+\.\d+\.\d+) \((\d+)\)", (rel or {}).get("name", "")); ver, build = (m.group(1), m.group(2)) if m else ("0.1.0", "?")
    line = ".".join(ver.split(".")[:2]) + ".x"
    rc = a.new or a.release_type != "Internal beta"
    version = a.version or ver
    if rc: key, title = f"rc|{version}|{a.release_type}", f"Release readiness: {version} ({a.release_type})"
    else: key, title = f"rolling|{line}|Tier A|{a.release_type}", f"Release readiness: {line} Tier A ({a.release_type})"
    mx = matrix(); qr, qnote = qa_results()
    body, sug, risk = build_body(key, title, a.release_type, f"{ver} (build {build})", mx, qr, qnote, rd, rel)
    c = (rd or {}).get("counts", {})
    comment = (f"<!-- readiness-build: {build} -->**Build {build}**: unit {c.get('unit','n/a')}, QA 8-flow {c.get('qa','n/a')}, "
               f"UI {c.get('ui','n/a')}, e2e {c.get('e2e','n/a')} · suggested: {sug} (risk {risk}) · "
               f"{'[run](' + rd['url'] + ')' if rd else ''} {'· [release](' + rel['html_url'] + ')' if rel else ''}")
    if a.dry_run:
        print(f"TITLE: {title}\n\n{body}\n\n---\nCOMMENT: {comment}"); return
    vlabel = f"v{version if rc else line}"
    for name, color in (("release", "0e8a16"), ("readiness", "fbca04"), (vlabel, "c5def5")):
        sh("gh", "label", "create", name, "--color", color, "-R", REPO, "--force", check=False)
    issues = gh_api(f"repos/{REPO}/issues?labels=readiness&state=open&per_page=100")
    hit = next((i for i in issues if f"readiness-key: {key} -->" in (i.get("body") or "")), None)
    if hit:
        num = hit["number"]
        gh_api(f"repos/{REPO}/issues/{num}", "-X", "PATCH", "-f", f"title={title}", "-f", f"body={body}")
        for lb in ("release", "readiness", vlabel): sh("gh", "issue", "edit", str(num), "-R", REPO, "--add-label", lb, check=False)
    else:
        url = sh("gh", "issue", "create", "-R", REPO, "--title", title, "--body", body, "--label", f"release,readiness,{vlabel}", "--assignee", "melusi-k").strip()
        num = int(url.rsplit("/", 1)[1])
    comments = gh_api(f"repos/{REPO}/issues/{num}/comments?per_page=100")
    if not any(f"readiness-build: {build} -->" in x["body"] for x in comments):
        sh("gh", "issue", "comment", str(num), "-R", REPO, "--body", comment)
    print(f"{SERVER}/{REPO}/issues/{num}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        open(os.environ["GITHUB_STEP_SUMMARY"], "a").write(f"### Release readiness\n{title}: {SERVER}/{REPO}/issues/{num}\n\n{comment}\n")


if __name__ == "__main__":
    main()
