#!/usr/bin/env bash
# Builds release notes: CHANGELOG.md "## Unreleased" section, else commit subjects since the previous build-* tag
# (grouped feat/fix/other), then a version/commit/run footer and install notes.
# Usage: scripts/release-notes.sh <version> <build> <sha> <run-url> <ipa-name> <ipa-kind>
set -euo pipefail
VERSION=$1 BUILD=$2 SHA=$3 RUN=$4 IPA=$5 KIND=${6:-unsigned}
section=$(awk '/^## /{ if (on) exit; if (tolower($0) ~ /^## +unreleased/) { on=1; next } } on' CHANGELOG.md 2>/dev/null || true)
echo "## ate $VERSION (build $BUILD)"
echo
if printf '%s' "$section" | grep -qE '^\s*[-*] '; then
  # Drop headings with no bullets under them.
  printf '%s\n' "$section" | awk '
    /^### /{ if (h != "" && n) printf "%s%s", h, buf; h=$0 "\n"; buf=""; n=0; next }
    { if (h == "") { if ($0 ~ /[^ ]/) print; next } buf = buf $0 "\n"; if ($0 ~ /^[ ]*[-*] /) n=1 }
    END { if (h != "" && n) printf "%s%s", h, buf }'
else
  prev=$(git tag --list 'build-*' --sort=-v:refname | grep -v "^build-$BUILD$" | head -1 || true)
  range=${prev:+$prev..}$SHA
  log=$(git log --no-merges --format='%s' $range 2>/dev/null || git log -20 --format='%s')
  feat=$(printf '%s\n' "$log" | grep -E '^feat(\(.+\))?!?:' | sed -E 's/^feat(\([^)]*\))?!?: */- /' || true)
  fix=$(printf '%s\n' "$log" | grep -E '^fix(\(.+\))?!?:' | sed -E 's/^fix(\([^)]*\))?!?: */- /' || true)
  other=$(printf '%s\n' "$log" | grep -vE '^(feat|fix)(\(.+\))?!?:' | grep -v '^$' | sed -E 's/^/- /' || true)
  [ -n "$feat" ] && printf '### ✨ New\n%s\n\n' "$feat"
  [ -n "$fix" ] && printf '### 🐛 Fixed\n%s\n\n' "$fix"
  [ -n "$other" ] && printf '### 🔧 Other\n%s\n\n' "$other"
  [ -z "$feat$fix$other" ] && printf -- '- Rebuild of %s\n\n' "${SHA::7}"
fi
cat <<FOOT

---
**Version** $VERSION · **Build** $BUILD · **Commit** [\`${SHA::7}\`](https://github.com/melusi-k/ate-ios/commit/$SHA) · [CI run]($RUN)

**Install:** download \`$IPA\` ($KIND). Unsigned builds install with Sideloadly or AltStore. With a free Apple ID the app expires after 7 days and needs Developer Mode (Settings › Privacy & Security). Settings › About shows the installed build.
FOOT
