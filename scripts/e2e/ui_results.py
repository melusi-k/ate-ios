#!/usr/bin/env python3
"""Maps xcodebuild UI-test log lines to Tier A items → JSON for backend_e2e.py --extra (source='ci')."""
import json, re, sys
MAP = {"test37_KilledMidGenerationRecovers": ["A-CREATE-05"],
       "test38_ExpiredSessionRefreshes": ["A-AUTH-06"]}
log, out = sys.argv[1], sys.argv[2]
res = {}
for line in open(log, errors="replace"):
    m = re.search(r"Test Case '-\[\S+ (test\w+)\]' (passed|failed) \(([\d.]+) seconds\)", line)
    if m and m.group(1) in MAP:
        for i in MAP[m.group(1)]:
            res[i] = {"status": "pass" if m.group(2) == "passed" else "fail", "note": f"Simulator UI test {m.group(1)} {m.group(2)} in {m.group(3)}s"}
json.dump(res, open(out, "w"), indent=2); print(json.dumps(res, indent=2))
