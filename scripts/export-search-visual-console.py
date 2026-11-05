#!/usr/bin/env python3
"""Bounded QA screenshot transport. Not an acceptance validator."""
import base64
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1]).resolve()
manifest = root / "manifest.json"
if not manifest.is_file():
    print("SEARCH_VISUAL_NO_MANIFEST")
    sys.exit(1)
items = json.loads(manifest.read_text())
if not isinstance(items, list):
    raise SystemExit("Unexpected attachment manifest shape")
allowed = {"search-visual-pre-search", "search-visual-menu-top", "search-visual-menu-bottom"}
allowed.update("search-visual-menu-scroll-" + str(i) for i in range(1, 4))
found = {}
for item in items:
    if not isinstance(item, dict) or not isinstance(item.get("attachments"), list):
        raise SystemExit("Unexpected attachment manifest entry")
    for attachment in item["attachments"]:
        name = attachment.get("suggestedHumanReadableName", "")
        shot = next((s for s in allowed if name == s + ".png" or name.startswith(s + "_0_") and name.endswith(".png")), None)
        if shot is None:
            continue
        path = (root / attachment["exportedFileName"]).resolve()
        if root not in path.parents or not path.is_file() or shot in found:
            raise SystemExit("Missing, unconfined or duplicate named capture")
        found[shot] = path
if not found:
    raise SystemExit("No named Search visual captures")
if sum(p.stat().st_size for p in found.values()) > 8 * 1024 * 1024:
    raise SystemExit("Capture transport exceeds total bound")
for shot, path in sorted(found.items()):
    data = path.read_bytes()
    if len(data) > 2 * 1024 * 1024 or not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("Capture exceeds per-image bound or is not PNG")
    with tempfile.TemporaryDirectory() as temp:
        subprocess.run(["sips", "-s", "format", "png", str(path), "--out", str(pathlib.Path(temp) / "decoded.png")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("SEARCH_CAPTURE_BEGIN " + json.dumps({"name": shot, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}), flush=True)
    encoded = base64.b64encode(data).decode("ascii")
    for start in range(0, len(encoded), 4096):
        print("SEARCH_CAPTURE_DATA " + encoded[start:start + 4096], flush=True)
    print("SEARCH_CAPTURE_END " + shot, flush=True)
print("SEARCH_VISUAL_MISSING " + json.dumps(sorted(allowed - found.keys())), flush=True)
