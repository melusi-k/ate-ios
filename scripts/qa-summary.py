#!/usr/bin/env python3
"""Turns KeyFlowsQATests xcodebuild output into a markdown QA table (flow → pass/fail)."""
import re, sys
flows = {1: "Add recipe from URL (JSON-LD + social caption + fallback)", 2: "Add from photo (screenshot + food-photo fallback)",
         3: "Generate & edit", 4: "Save", 5: "Share (link + text)", 6: "Open shared recipe (+ expired / not found)",
         7: "Sync account (sign in, edit, sync, 2nd launch pulls)", 8: "Timers (start/pause/resume, bar, finish chime+haptic, Live Activity)"}
log = open(sys.argv[1], errors="ignore").read() if len(sys.argv) > 1 else sys.stdin.read()
res = {}
for m in re.finditer(r"Test Case '-\[\S+ testQA(\d)_\w+\]' (passed|failed) \(([\d.]+) seconds\)", log):
    res[int(m.group(1))] = (m.group(2), m.group(3))
print("### ✅ QA gate — key flows\n\n| # | Flow | Result | Time |\n|---|---|---|---|")
ok = 0
for n, name in flows.items():
    r, t = res.get(n, ("not run", "–"))
    icon = "✅ pass" if r == "passed" else ("❌ fail" if r == "failed" else "⚪ not run")
    ok += r == "passed"
    print(f"| {n} | {name} | {icon} | {t}s |" if t != "–" else f"| {n} | {name} | {icon} | – |")
print(f"\n**{ok}/{len(flows)} key flows passed.** Release is published only when all pass.")
