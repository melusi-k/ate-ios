#!/usr/bin/env python3
"""A-CI-05: validate acceptance IDs, actual QA matrix rows, issue ownership, generated beta checks, and client secrets.
  --fix appends missing matrix rows from the checklist and regenerates BetaChecklist.swift."""
import os, re, subprocess, sys
from collections import Counter
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
ID = re.compile(r'\b([ABC]-[A-Z0-9]+-\d{2})\b')
ids = lambda p: set(ID.findall(open(p).read()))
fix = '--fix' in sys.argv
ck = open('docs/MVP_CHECKLIST.md').read()
defined = {}
for blk in re.split(r'\n(?=- \*\*[ABC]-)', ck):
    m = re.match(r'- \*\*([ABC]-[A-Z0-9]+-\d{2}) · (.+?)\*\*(?: — (\S+))?', blk)
    if not m:
        continue
    f = lambda k: (re.search(r'\*%s:\* (.*)' % k, blk) or [None, '—'])[1].strip()
    defined[m.group(1)] = dict(title=m.group(2), mark=m.group(3) or '❌',
        j=f('Journey'), acc=f('Acceptance'), ver=f('Verified by'), ev=f('Status evidence'),
        gate=f('Release gate').split(' · ')[0])
errors = []
heads = re.findall(r'^- \*\*([ABC]-[A-Z0-9]+-\d{2}) · ', ck, re.M)
errors += [f"{i}: defined more than once in MVP_CHECKLIST"
           for i in sorted({x for x in heads if heads.count(x) > 1})]

def matrix_row(i):
    d = defined[i]
    mark, j, acc, ver, ev = d['mark'], d['j'] if d['j'] != '—' else d['title'], d['acc'], d['ver'], d['ev']
    return f"| {i} | {j} | — | {acc} | {ver.split(' · ')[0]} | Not run | Not run | Not run | {mark} | {ev} |"

mx = open('docs/QA_MATRIX.md').read()
# Only a real first-column table row counts as coverage; prose references are not test cases.
matrix_ids = set(re.findall(r'^\|\s*([ABC]-[A-Z0-9]+-\d{2})\s*\|', mx, re.M))
missing = sorted(set(defined) - matrix_ids)
if missing and fix:
    mx = mx.rstrip() + "\n\n## Added from MVP_CHECKLIST (check-ids --fix)\n\n| ID | Journey | Steps | Expected | Automated test | Sim result | iPhone 17 result | Older/non-AI device result | Status | Notes |\n|---|---|---|---|---|---|---|---|---|---|\n" + "\n".join(matrix_row(i) for i in missing) + "\n"
    open('docs/QA_MATRIX.md', 'w').write(mx)
    missing = []
for i in missing:
    errors.append(f"{i}: in MVP_CHECKLIST but has no actual QA_MATRIX row")

# Gate classification is explicit metadata, never inferred from an ID prefix.
# Read the trailing metadata cells: legacy matrix rows have different evidence widths.
gates = ('Pilot', 'Public launch', 'No committed release gate')
matrix_gates = {}
for line in mx.splitlines():
    match = re.match(r'^\|\s*([ABC]-[A-Z0-9]+-\d{2})\s*\|', line)
    if not match:
        continue
    i = match.group(1)
    cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
    if i in matrix_gates:
        errors.append(f"{i}: defined more than once in QA_MATRIX")
    matrix_gates[i] = cells[-2] if len(cells) >= 4 else ''
for i, d in defined.items():
    if d['gate'] not in gates:
        errors.append(f"{i}: invalid or missing Release gate in MVP_CHECKLIST: {d['gate']}")
for i, gate in matrix_gates.items():
    if gate not in gates:
        errors.append(f"{i}: invalid or missing Release gate in QA_MATRIX: {gate}")
    if i in defined and gate != defined[i]['gate']:
        errors.append(f"{i}: Release gate differs between MVP_CHECKLIST and QA_MATRIX")

# LAUNCH_GATES is an inventory contract, not an approval of candidate thresholds.
launch = open('docs/LAUNCH_GATES.md').read()
for gate in gates:
    counts = re.findall(r'^\|[^|]*\| `'+ re.escape(gate) + r'`[^|]*\| (\d+) \|$', launch, re.M)
    if len(counts) != 1:
        errors.append(f"LAUNCH_GATES: expected exactly one count for {gate}")
        continue
    expected = int(counts[0])
    for source, actual in (
        ('MVP_CHECKLIST', Counter(d['gate'] for d in defined.values())[gate]),
        ('QA_MATRIX', Counter(matrix_gates.values())[gate]),
    ):
        if actual != expected:
            errors.append(f"{source}: {gate} count {actual} differs from LAUNCH_GATES {expected}")
totals = re.findall(r'^\| Total acceptance IDs \|\s*\| (\d+) \|$', launch, re.M)
if len(totals) != 1 or any(int(totals[0]) != n for n in (len(defined), len(matrix_gates))):
    errors.append("LAUNCH_GATES: total acceptance ID count must match checklist and matrix")

# Every checklist item must have exactly one explicit owning issue link.
for blk in re.split(r'\n(?=- \*\*[ABC]-)', ck):
    m = re.match(r'- \*\*([ABC]-[A-Z0-9]+-\d{2}) · ', blk)
    if not m:
        continue
    owner = re.search(r'^\s*- \*Owner:\* (.+)$', blk, re.M)
    if not owner or 'TBD' in owner.group(1) or not re.fullmatch(
        r'\[#\d+\]\(https://github\.com/melusi-k/ate-ios/issues/\d+\)', owner.group(1).strip()
    ):
        errors.append(f"{m.group(1)}: missing valid owning GitHub issue link in MVP_CHECKLIST")

if fix:
    subprocess.run([sys.executable, 'scripts/gen-beta-checklist.py'], check=True)
beta = ids('Ate/Logic/BetaChecklist.swift')
want = {i for i in defined if i[0] in 'AC'}
for i in sorted(want - beta):
    errors.append(f"{i}: in MVP_CHECKLIST (Tier A/C) but not in the in-app Beta checks; run scripts/gen-beta-checklist.py")
for p in ['Ate/Logic/BetaChecklist.swift', 'docs/QA_MATRIX.md', 'docs/BETA.md', 'README.md', 'docs/SECURITY_REVIEW.md']:
    if os.path.exists(p):
        for i in sorted(ids(p) - set(defined)):
            errors.append(f"{i}: cited in {p} but not defined in MVP_CHECKLIST")
before = open('Ate/Logic/BetaChecklist.swift').read()
subprocess.run([sys.executable, 'scripts/gen-beta-checklist.py'], capture_output=True, check=True)
if open('Ate/Logic/BetaChecklist.swift').read() != before:
    errors.append("Ate/Logic/BetaChecklist.swift was stale (hand-edited or not regenerated); regenerated, commit it")

for root in ['Ate', 'AteWidgets', 'AteWatch', 'Shared', 'AteShare']:
    for d, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(('.swift', '.plist', '.xcconfig', '.json')):
                t = open(os.path.join(d, f), errors='ignore').read()
                if re.search(r'service_role|SERVICE_ROLE|sb_secret_', t):
                    errors.append(f"{d}/{f}: service-role/secret key reference in client code")

print(f"{len(defined)} IDs defined; actual matrix rows {len(matrix_ids)}, beta IDs {len(beta)}")
if errors:
    print("\n".join("::error::" + e for e in errors))
    sys.exit(1)
print("IDs and ownership consistent ✓")
