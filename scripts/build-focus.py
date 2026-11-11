#!/usr/bin/env python3
"""Render a reviewed build focus from the target source, never checkout HEAD."""
import json
from pathlib import PurePosixPath
import re
import subprocess
import sys

RECORD = "docs/build-focus.json"


def git(*args):
    return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()


def build_focus(source):
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise ValueError("Build focus requires a full source SHA")
    source = git("rev-parse", "--verify", source + "^{commit}")
    # Missing on old source commits is explicit, not a guess based on newer HEAD.
    try:
        raw = git("show", source + ":" + RECORD)
    except subprocess.CalledProcessError:
        return "No main feature focus was recorded for this source."
    data = json.loads(raw)
    for field in ("title", "summary"):
        value = data.get(field)
        if not isinstance(value, str) or not value.strip() or len(value) > 600 or any(c in value for c in "\n\r\x00"):
            raise ValueError("Build focus needs a non-empty single-line " + field)
    anchor = data.get("source_commit", "")
    if not re.fullmatch(r"[0-9a-f]{40}", anchor):
        raise ValueError("Build focus requires a full source anchor")
    subprocess.run(["git", "merge-base", "--is-ancestor", anchor, source], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    evidence = data.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("Build focus needs runtime source evidence")
    for item in evidence:
        path, blob = item.get("path", ""), item.get("blob", "")
        p = PurePosixPath(path)
        if p.is_absolute() or ".." in p.parts or not path.startswith("Ate/") or not path.endswith(".swift"):
            raise ValueError("Build focus evidence must be an app Swift source path")
        if not re.fullmatch(r"[0-9a-f]{40}", blob):
            raise ValueError("Build focus evidence requires a full blob SHA")
        if git("rev-parse", anchor + ":" + path) != blob or git("rev-parse", source + ":" + path) != blob:
            raise ValueError("Build focus runtime evidence changed; review and update the focus")
    # Inclusion and unchanged source are mechanical guards, not semantic proof or QA.
    return data["title"].strip() + "\n\n" + data["summary"].strip()


if __name__ == "__main__":
    try:
        print("### Main feature focus\n\n" + build_focus(sys.argv[1]) + "\n")
    except (ValueError, KeyError, IndexError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit("Build focus validation failed: " + str(error))
