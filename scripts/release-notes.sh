#!/usr/bin/env bash
# Builds release notes from the exact commits included in this build (since the previous build-* tag),
# then adds a version/commit/run footer and install notes. CHANGELOG.md is project-level history and
# must not be copied into a specific release.
# Usage: scripts/release-notes.sh <version> <build> <sha> <run-url> <ipa-name> <ipa-kind>
set -euo pipefail
VERSION=$1 BUILD=$2 SHA=$3 RUN=$4 IPA=$5 KIND=${6:-unsigned}
echo "## ate $VERSION (build $BUILD)"
echo
prev=$(git tag --list 'build-*' --sort=-v:refname | grep -v "^build-$BUILD" | head -1 || true)
range=${prev:+$prev..}$SHA
log=$(git log --no-merges --format='%s' $range 2>/dev/null || git log -20 --format='%s')
printf '### Changes in this build\n'
printf '%s\n' "$log" | grep -v '^$' | sed -E 's/^/- /' || true
printf '\n'
cat <<FOOT

---
**Version** $VERSION · **Build** $BUILD · **Commit** [\`${SHA::7}\`](https://github.com/melusi-k/ate-ios/commit/$SHA) · [CI run]($RUN)

**Install:** download \`$IPA\` ($KIND). Unsigned builds install with Sideloadly or AltStore. With a free Apple ID the app expires after 7 days and needs Developer Mode (Settings › Privacy & Security). Settings › About shows the installed build.
FOOT
