#!/usr/bin/env python3
"""Shared iOS simulator selector for CI.

Prefers the newest available iPhone that matches the chosen iOS version,
falling back to the latest available iPhone on any iOS runtime.
"""

import json
import subprocess
import sys


def list_devices():
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(out.stdout).get("devices", {})


def select_simulator(prefer_ios_version="iOS-26", prefer_name="iPhone 17"):
    devices = list_devices()

    candidates = []
    for ios_ver, devs in devices.items():
        if prefer_ios_version in ios_ver:
            for dev in devs:
                if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
                    if dev.get("name") == prefer_name:
                        candidates.append((ios_ver, dev))

    if not candidates:
        for ios_ver, devs in devices.items():
            if prefer_ios_version in ios_ver:
                for dev in devs:
                    if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
                        candidates.append((ios_ver, dev))

    if not candidates:
        ios_versions = []
        for ios_ver in devices.keys():
            if "iOS" in ios_ver:
                ios_versions.append(ios_ver)
        for ios_ver in sorted(ios_versions, reverse=True):
            for dev in devices.get(ios_ver, []):
                if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
                    candidates.append((ios_ver, dev))

    if not candidates:
        print("No available iPhone simulator found.", file=sys.stderr)
        sys.exit(1)

    ios_ver, dev = candidates[0]
    return dev["udid"], ios_ver, dev["name"]


if __name__ == "__main__":
    udid, ios_ver, device_name = select_simulator()
    print(f"SIM_ID={udid}")
    print(f"SIM_IOS={ios_ver}")
    print(f"SIM_NAME={device_name}")
