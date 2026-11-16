#!/usr/bin/env python3
"""Select the required iPhone 18 Pro / available iOS 27.x simulator for CI tests."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any

EXPECTED_DEVICE = "iPhone 18 Pro"
EXPECTED_RUNTIME_MAJOR = 27
EXPECTED_RUNTIME_LABEL = "iOS 27.x"


def runtime_version(runtime: str) -> tuple[int, ...] | None:
    """Accept only numeric stable iOS 27 runtimes, not other platforms or majors."""
    match = re.fullmatch(rf"(?:com\.apple\.CoreSimulator\.SimRuntime\.)?iOS-({EXPECTED_RUNTIME_MAJOR})-(\d+)(?:-(\d+))?", runtime)
    return tuple(int(part or 0) for part in match.groups()) if match else None


def select_device(devices: dict[str, list[dict[str, Any]]]) -> str | None:
    matches: list[tuple[tuple[int, ...], str]] = []
    for runtime, entries in devices.items():
        version = runtime_version(runtime)
        if version is None:
            continue
        for device in entries:
            if (
                device.get("name") == EXPECTED_DEVICE
                and device.get("isAvailable", True)
                and device.get("udid")
            ):
                matches.append((version, str(device["udid"])))
    if not matches:
        return None
    latest = max(version for version, _ in matches)
    return min(udid for version, udid in matches if version == latest)


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
            f"ERROR: required {EXPECTED_DEVICE} simulator on {EXPECTED_RUNTIME_LABEL} "
            "is not available. Use an available iOS 27.x runtime; "
            "no fallback device will be selected.",
            file=sys.stderr,
        )
        print("Available iOS simulators:", file=sys.stderr)
        print("\n".join(available) if available else "(none)", file=sys.stderr)
        return 1

    runtime = next(runtime for runtime, entries in devices.items()
                   if any(str(device.get("udid")) == udid for device in entries))
    print(f"Selected {EXPECTED_DEVICE} on {runtime}: {udid}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
