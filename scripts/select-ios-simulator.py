#!/usr/bin/env python3
"""Select the required iPhone 18 Pro / iOS 27.0 simulator for CI tests."""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Any

EXPECTED_DEVICE = "iPhone 18 Pro"
EXPECTED_RUNTIME = "iOS-27-0"


def select_device(devices: dict[str, list[dict[str, Any]]]) -> str | None:
    matches: list[str] = []
    for runtime, entries in devices.items():
        if runtime.rsplit(".", 1)[-1] != EXPECTED_RUNTIME:
            continue
        for device in entries:
            if (
                device.get("name") == EXPECTED_DEVICE
                and device.get("isAvailable", True)
                and device.get("udid")
            ):
                matches.append(str(device["udid"]))
    return sorted(matches)[0] if matches else None


def main() -> int:
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            check=True,
            capture_output=True,
            text=True,
        )
        devices = json.loads(result.stdout).get("devices", {})
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"ERROR: unable to enumerate available iOS simulators: {error}", file=sys.stderr)
        return 1

    udid = select_device(devices)
    if udid is None:
        available = [
            f"{runtime}: {device.get('name', 'unknown')} ({device.get('udid', 'no UDID')})"
            for runtime, entries in devices.items()
            if "iOS" in runtime
            for device in entries
        ]
        print(
            f"ERROR: required {EXPECTED_DEVICE} simulator on {EXPECTED_RUNTIME.replace('-', '.')} "
            "is not available. Use the xcode-27 runner image with Xcode 27.1; "
            "no fallback device will be selected.",
            file=sys.stderr,
        )
        print("Available iOS simulators:", file=sys.stderr)
        print("\n".join(available) if available else "(none)", file=sys.stderr)
        return 1

    print(f"Selected {EXPECTED_DEVICE} on iOS 27.0: {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
