#!/usr/bin/env bash
# Prepare the generated Xcode project with a version tied to the checked-out Git commit.
# This is for local development only; CI continues to use GitHub Actions run numbers.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

BASE_VERSION="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("project.yml").read_text()
match = re.search(r'^\s*MARKETING_VERSION:\s*["\']?([0-9]+\.[0-9]+)(?:\.[0-9]+)?["\']?\s*$', text, re.M)
if not match:
    raise SystemExit("Could not read major.minor from MARKETING_VERSION in project.yml")
print(match.group(1))
PY
)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
SHORT_SHA="$(git rev-parse --short=7 HEAD)"
LOCAL_VERSION="${BASE_VERSION}.${BUILD_NUMBER}"

# Temporarily override the source spec only while generating the local Xcode project.
# Always restore it, including when XcodeGen fails.
BACKUP="$(mktemp)"
cp project.yml "$BACKUP"
restore_project_spec() {
  cp "$BACKUP" project.yml
  rm -f "$BACKUP"
}
trap restore_project_spec EXIT

export LOCAL_VERSION BUILD_NUMBER SHORT_SHA
python3 - <<'PY'
import os, re
from pathlib import Path

path = Path("project.yml")
text = path.read_text()
values = {
    "MARKETING_VERSION": os.environ["LOCAL_VERSION"],
    "CURRENT_PROJECT_VERSION": os.environ["BUILD_NUMBER"],
    "ATE_GIT_SHA": os.environ["SHORT_SHA"],
    "ATE_CHANNEL": "",
}
for key, value in values.items():
    pattern = re.compile(r"^(\s*" + re.escape(key) + r":\s*).*$", re.M)
    text, count = pattern.subn(lambda m: m.group(1) + '"' + value + '"', text, count=1)
    if count != 1:
        raise SystemExit(f"Expected exactly one {key} setting in project.yml; found {count}")
path.write_text(text)
PY

echo "Generating local Xcode project:"
echo "  marketing version: $LOCAL_VERSION"
echo "  build number:      $BUILD_NUMBER (Git commit count)"
echo "  source commit:     $SHORT_SHA"
echo "  channel:           local"
xcodegen generate

echo
echo "Local Xcode project generated. project.yml has been restored to its CI-safe defaults."
echo "The generated Ate.xcodeproj may show local-only changes; do not commit those version overrides."
