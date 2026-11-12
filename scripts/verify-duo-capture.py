#!/usr/bin/env python3
"""Require all named optional captures to execute, not merely skip green."""
import re
import sys
from pathlib import Path

CASES = ("testRootPortraitAndLandscape", "testModalCookPortraitAndLandscape", "testPushedCookPortraitAndLandscape")


def verify(log):
    return all(re.search(r"Test Case '-\[AteUITests\.DuoExplorationUITests " + name + r"\]' passed \(", log) for name in CASES)


if __name__ == "__main__":
    if not verify(Path(sys.argv[1]).read_text()):
        raise SystemExit("All three Duo capture cases must explicitly pass; skips/missing cases are not evidence")
    print("All three opt-in Duo screenshot cases executed and passed; visual review still required")
