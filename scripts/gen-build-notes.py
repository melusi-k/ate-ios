#!/usr/bin/env python3
"""Generate build-specific About notes from the checked-out Git history."""
from pathlib import Path
import subprocess

OUTPUT = Path("Ate/Resources/BuildNotes.md")
OUTPUT.parent.mkdir(parents=True, exist_ok=True)

def git(*args):
    try:
        return subprocess.run(
            ["git", *args], check=True, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""

sha = git("rev-parse", "HEAD")
previous = git("tag", "--list", "build-*", "--sort=-v:refname")
previous_tag = next((tag for tag in previous.splitlines() if tag != f"build-{git('rev-parse', '--short', 'HEAD')}"), "")
if previous_tag and sha:
    subjects = git("log", "--no-merges", "--format=%s", f"{previous_tag}..{sha}")
else:
    subjects = git("log", "-20", "--no-merges", "--format=%s", "HEAD")

lines = [line.strip() for line in subjects.splitlines() if line.strip()]
# Avoid exposing a blank panel or a misleading generic changelog if history is unavailable.
if not lines:
    lines = ["Build notes are not available for this build."]

content = "Changes in this build\n\n" + "\n".join(f"- {line}" for line in lines) + "\n"
OUTPUT.write_text(content, encoding="utf-8")
print(f"Generated {OUTPUT} with {len(lines)} note(s).")
