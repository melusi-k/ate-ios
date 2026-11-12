#!/usr/bin/env python3
"""Arm only AteUITests in a dedicated built xctestrun for manual Duo capture."""
import plistlib
import sys
from pathlib import Path


def enable(data):
    count = 0
    if isinstance(data, dict):
        # Xcode's modern TestConfigurations and legacy per-target formats both
        # expose the test bundle path on the target dictionary.
        bundle = data.get("TestBundlePath", "")
        if isinstance(bundle, str) and bundle.endswith("/AteUITests.xctest"):
            data.setdefault("EnvironmentVariables", {})["ATE_DUO_EXPLORATION"] = "1"
            count += 1
        for value in data.values():
            if isinstance(value, (dict, list)):
                count += enable(value)
    elif isinstance(data, list):
        for value in data:
            count += enable(value)
    return count


def main():
    path = Path(sys.argv[1])
    with path.open("rb") as source:
        data = plistlib.load(source)
    count = enable(data)
    if count == 0:
        raise SystemExit("No AteUITests bundle in dedicated xctestrun; refusing silent skip")
    with path.open("wb") as dest:
        plistlib.dump(data, dest)
    print(f"Armed {count} AteUITests target(s) for opt-in Duo screenshots")


if __name__ == "__main__":
    main()
