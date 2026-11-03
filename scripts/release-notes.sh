#!/usr/bin/env bash
# Builds source-history notes from an eligible same-channel ancestor build tag,
# then adds a version/commit/run footer and install notes. CHANGELOG.md is project-level history and
# must not be copied into a specific release.
# Usage: scripts/release-notes.sh <version> <build> <sha> <run-url> <ipa-name> <ipa-kind>
set -euo pipefail
VERSION=$1 BUILD=$2 SHA=$3 RUN=$4 IPA=$5 KIND=${6:-unsigned}
# Resolve a baseline from actual source ancestry, not global tag ordering. The
# artifact filename is already channel-bound by Build IPA; no new workflow input.
selection=$(python3 - "$VERSION" "$BUILD" "$SHA" "$IPA" <<'PYBASE'
import re
import subprocess
import sys

def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()

version, build, sha, ipa = sys.argv[1:]
if not re.fullmatch(r"[0-9a-f]{40}", sha):
    raise SystemExit("Expected full source commit SHA")
if not build.isdigit() or int(build) < 1:
    raise SystemExit("Expected positive build number")
match = re.fullmatch(r"Ate-" + re.escape(version) + r"-build" + re.escape(build) + r"(-[^/]+)?\.ipa", ipa)
if not match:
    raise SystemExit("IPA name does not match version/build/channel convention")
if git("rev-parse", "--is-shallow-repository") != "false":
    raise SystemExit("Full git history is required for release-note ancestry")
# Resolve before printing notes. Invalid targets must not fall back to checkout HEAD.
commit = git("rev-parse", "--verify", sha + "^{commit}")
if not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("Expected full source commit")
suffix = match[1] or ""
# The workflow channel is a free string. Preserve any filename-safe suffix that
# is already a valid tag suffix, instead of inventing an alphanumeric enum.
git("check-ref-format", "refs/tags/build-" + build + suffix)
eligible = []
for tag in git("tag", "--merged", commit, "--list", "build-*").splitlines():
    candidate = re.fullmatch(r"build-([1-9][0-9]*)(-.+)?", tag)
    if candidate and int(candidate[1]) < int(build) and (candidate[2] or "") == suffix:
        eligible.append((int(candidate[1]), tag))
print(commit)
print(max(eligible)[1] if eligible else "")
PYBASE
)
SOURCE=$(printf '%s\n' "$selection" | head -1)
prev=$(printf '%s\n' "$selection" | sed -n '2p')
range=${prev:+$prev..}$SOURCE
# No arbitrary HEAD/last-20 fallback: failure must stay visible and source-bound.
log=$(git log --no-merges --format='%s' "$range")
echo "## ate $VERSION (build $BUILD)"
echo
printf '### Source changes in this build\n'
if [ -n "$prev" ]; then
  printf 'Baseline: `%s` (same channel, lower build number, ancestor of this source).\n\n' "$prev"
else
  printf 'No earlier same-channel ancestor build tag exists in this checkout. Listing all non-merge source history through this commit, not a previous-release delta.\n\n'
fi
if [ -n "$log" ]; then
  printf '%s\n' "$log" | sed -E 's/^/- /'
else
  printf 'No new non-merge source commits since `%s`.\n' "$prev"
fi
printf '\n'
cat <<FOOT

---
**Version** $VERSION · **Build** $BUILD · **Commit** [\`${SOURCE::7}\`](https://github.com/melusi-k/ate-ios/commit/$SOURCE) · [CI run]($RUN)

**Install:** download \`$IPA\` ($KIND). Unsigned builds install with Sideloadly or AltStore. With a free Apple ID the app expires after 7 days and needs Developer Mode (Settings › Privacy & Security). Settings › About shows the installed build.
FOOT
