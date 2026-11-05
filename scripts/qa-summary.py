#!/usr/bin/env python3
"""Turns KeyFlowsQATests xcodebuild output into a markdown QA table (flow → pass/fail)."""
import re, sys
flows = {1: "Add recipe from URL (3 cases: JSON-LD, Instagram caption, hidden-caption fallback)", 2: "Add from photo (screenshot + food-photo fallback)",
         3: "Generate & edit", 4: "Save", 5: "Share (link + text)", 6: "Open shared recipe (+ expired / not found)",
         7: "Sync account (sign in, edit, sync, 2nd launch pulls)", 8: "Timers (start/pause/resume, bar, finish chime+haptic, Live Activity)"}
# QA1 runs as three independent cases; the flow passes only when these exact three case
# names all passed - never on any one pass, a partial set, or a deprecated variant.
# Keep in sync with QA1_REQUIRED_CASES in scripts/release/readiness.py and the
# -only-testing list in .github/workflows/dogfood-qualification.yml.
QA1_REQUIRED_CASES = ("testQA1_AddFromURL_JSONLD", "testQA1_AddFromURL_InstagramCaption", "testQA1_AddFromURL_HiddenCaptionFallback")
required_cases = {1: QA1_REQUIRED_CASES}
CASE_RE = re.compile(r"Test Case '-\[\S+ (testQA(\d)_\w+)\]' (passed|failed) \(([\d.]+) seconds\)")

def parse_cases(log):
    """Flow number -> {case name -> (result, seconds)}. A failure is sticky: a later
    pass of the same case name must not launder an earlier failure."""
    cases = {}
    for m in CASE_RE.finditer(log):
        num, name, result, secs = int(m.group(2)), m.group(1), m.group(3), float(m.group(4))
        prev = cases.setdefault(num, {}).get(name)
        if prev and prev[0] == "failed":
            continue
        cases[num][name] = (result, secs)
    return cases

def flow_state(num, cs):
    """(state, observed_required, required_total) with state passed/failed/not run."""
    required = required_cases.get(num)
    if required:
        observed = sum(1 for name in required if name in cs)
        if all(cs.get(name, (None,))[0] == "passed" for name in required):
            return "passed", observed, len(required)
        return ("not run" if observed == 0 else "failed"), observed, len(required)
    if not cs:
        return "not run", 0, 1
    return ("passed" if all(r == "passed" for r, _ in cs.values()) else "failed"), len(cs), 1

def render(cases):
    icons = {"passed": "✅ pass", "failed": "❌ fail", "not run": "⚪ not run"}
    lines = ["### ✅ QA gate — key flows", "", "| # | Flow | Result | Time |", "|---|---|---|---|"]
    ok = 0
    for n, name in flows.items():
        cs = cases.get(n, {})
        state, observed, need = flow_state(n, cs)
        required = required_cases.get(n)
        total = sum(t for nm, (r, t) in cs.items() if not required or nm in required)
        detail = f" ({observed}/{need} cases)" if required else ""
        ok += state == "passed"
        lines.append(f"| {n} | {name} | {icons[state]}{detail} | {total:.0f}s |" if cs else f"| {n} | {name} | {icons[state]}{detail} | – |")
    lines += ["", f"**{ok}/{len(flows)} key flows passed.** Release is published only when all pass."]
    return "\n".join(lines)

def main(argv):
    log = open(argv[1], errors="ignore").read() if len(argv) > 1 else sys.stdin.read()
    print(render(parse_cases(log)))

if __name__ == "__main__":
    main(sys.argv)
