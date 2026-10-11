#!/usr/bin/env python3
"""A-CI-05: one source of truth for item IDs. docs/MVP_CHECKLIST.md defines every ID; docs/QA_MATRIX.md must list
every ID, Ate/Logic/BetaChecklist.swift must be the generated copy of Tier A + Tier C, and no doc may cite an
unknown ID. Also fails if a service-role key or SUPABASE_SERVICE name shows up in client code.
  --fix  appends missing QA-matrix rows from the checklist and regenerates BetaChecklist.swift."""
import os, re, subprocess, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
ID = re.compile(r'\b([ABC]-[A-Z0-9]+-\d{2})\b')
ids = lambda p: set(ID.findall(open(p).read()))
fix = '--fix' in sys.argv
ck = open('docs/MVP_CHECKLIST.md').read()
defined = {}
for blk in re.split(r'\n(?=- \*\*[ABC]-)', ck):
    m = re.match(r'- \*\*([ABC]-[A-Z0-9]+-\d{2}) · (.+?)\*\*(?: — (\S+))?', blk)
    if not m: continue
    f = lambda k: (re.search(r'\*%s:\* (.*)' % k, blk) or [None, '—'])[1].strip()
    defined[m.group(1)] = dict(title=m.group(2), mark=m.group(3) or '❌', j=f('Journey'), acc=f('Acceptance'), ver=f('Verified by'), ev=f('Status evidence'))
errors = []
heads = re.findall(r'^- \*\*([ABC]-[A-Z0-9]+-\d{2}) · ', ck, re.M)
errors += [f"{i}: defined more than once in MVP_CHECKLIST" for i in sorted({x for x in heads if heads.count(x) > 1})]

def matrix_row(i):
    d = defined[i]; mark, j, acc, ver, ev = d['mark'], d['j'] if d['j'] != '—' else d['title'], d['acc'], d['ver'], d['ev']
    return f"| {i} | {j} | — | {acc} | {ver.split(' · ')[0]} | Not run | Not run | Not run | {mark} | {ev} |"

mx = open('docs/QA_MATRIX.md').read()
missing = sorted(set(defined) - ids('docs/QA_MATRIX.md'))
if missing and fix:
    mx = mx.rstrip() + "\n\n## Added from MVP_CHECKLIST (check-ids --fix)\n\n| ID | Journey | Steps | Expected | Automated test | Sim result | iPhone 17 result | Older/non-AI device result | Status | Notes |\n|---|---|---|---|---|---|---|---|---|---|\n" + "\n".join(matrix_row(i) for i in missing) + "\n"
    open('docs/QA_MATRIX.md', 'w').write(mx); missing = []
for i in missing: errors.append(f"{i}: in MVP_CHECKLIST but not in QA_MATRIX")

if fix: subprocess.run([sys.executable, 'scripts/gen-beta-checklist.py'], check=True)
beta = ids('Ate/Logic/BetaChecklist.swift')
want = {i for i in defined if i[0] in 'AC'}
for i in sorted(want - beta): errors.append(f"{i}: in MVP_CHECKLIST (Tier A/C) but not in the in-app Beta checks; run scripts/gen-beta-checklist.py")
for p in ['Ate/Logic/BetaChecklist.swift', 'docs/QA_MATRIX.md', 'docs/BETA.md', 'README.md', 'docs/SECURITY_REVIEW.md']:
    if os.path.exists(p):
        for i in sorted(ids(p) - set(defined)): errors.append(f"{i}: cited in {p} but not defined in MVP_CHECKLIST")
before = open('Ate/Logic/BetaChecklist.swift').read()
subprocess.run([sys.executable, 'scripts/gen-beta-checklist.py'], capture_output=True, check=True)
if open('Ate/Logic/BetaChecklist.swift').read() != before:
    errors.append("Ate/Logic/BetaChecklist.swift was stale (hand-edited or not regenerated); regenerated, commit it")

for root in ['Ate', 'AteWidgets', 'AteWatch', 'Shared', 'AteShare']:
    for d, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(('.swift', '.plist', '.xcconfig', '.json')):
                t = open(os.path.join(d, f), errors='ignore').read()
                if re.search(r'service_role|SERVICE_ROLE|sb_secret_', t): errors.append(f"{d}/{f}: service-role/secret key reference in client code")

print(f"{len(defined)} IDs defined; matrix {len(ids('docs/QA_MATRIX.md'))}, beta {len(beta)}")
if errors:
    print("\n".join("::error::" + e for e in errors)); sys.exit(1)
print("IDs consistent ✓")
