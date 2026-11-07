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
ordered = sorted(eligible, reverse=True)
print(ordered[0][1] if ordered else "")
# A labelled upgrade window helps testers who skipped recent internal builds.
# Keep this separate from the exact delta; never call earlier work new in this build.
print(ordered[min(4, len(ordered) - 1)][1] if ordered else "")
PYBASE
)
SOURCE=$(printf '%s\n' "$selection" | head -1)
prev=$(printf '%s\n' "$selection" | sed -n '2p')
catchup=$(printf '%s\n' "$selection" | sed -n '3p')
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
python3 - "$SOURCE" "$prev" "$catchup" <<'PYTEST'
import subprocess, sys
source, previous, catchup = sys.argv[1:]
def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()
window = (catchup + ".." if catchup else "") + source
if catchup and catchup != previous:
    print("### Recent-build catch-up (not all new in this build)")
    print(f"For upgrades from `{catchup}` through this source. This covers up to five earlier same-channel ancestor builds; the exact new-build baseline is listed above.\n")
    history = git("log", "--no-merges", "--format=%s", window)
    print("\n".join("- " + line for line in history.splitlines()) if history else "No source changes in this window.")
    print()
paths = set(git("diff", "--name-only", catchup, source).splitlines()) if catchup else set(git("ls-tree", "-r", "--name-only", source).splitlines())
# Suggestions are tied to changed source areas, not generated claims that a feature shipped or passed.
rules = [
 ("Journal and Insights navigation", ("Journal", "Insights", "AteApp.swift", "AppStore.swift"),
  "Open the Journal tab, then Insights & Cooking History. Return to Journal. Open an existing entry and confirm its text, date and available actions. If the Journal tab is not present in this source, use the existing Insights entry point; do not infer a navigation change from a test-only edit."),
 ("Recipe sharing and sheet dismissal", ("KeyFlowsQATests.swift", "Share", "RecipeDetail", "RecipeSheet"),
  "Open a saved recipe, choose Share link, close the system share sheet, and reopen Share. Confirm the recipe stays usable and sharing options appear once. Cancel without sending anything."),
 ("Cooking history and return navigation", ("CookingTracker", "CookMode", "CookSession", "CookingHistory"),
  "Finish a short recipe in Cook Mode. Open Journal > Insights & Cooking History, select today, and open that recipe. Close it and confirm the history remains reachable. Leaving without Finish must remain resumable; cooking is not an eaten-food log."),
 ("Food diary and saved nutrition values", ("NutritionDiary", "NutritionGoals", "CanonicalNutrition"),
  "Open the available Food diary or Journal food-entry route. Add a clearly named test entry, edit its quantity, close and reopen the app, and check the saved values. Delete only your test entry. Missing nutrients must stay unavailable, not invented zeros."),
]
selected = [(title, steps) for title, terms, steps in rules if any(any(term in p for term in terms) for p in paths)]
print("### What to test")
print("These are suggested checks from changed files in the labelled source window, not test results or proof that every related feature changed. Unmerged work is excluded.\n")
if selected:
    for title, _ in selected: print("- " + title + ".")
else:
    print("- No mapped app journey changed in this source window. Review the source-change list; build/workflow/test changes alone do not establish a visible app change.")
print("\n### How to test")
print("1. Install this exact build and confirm its number in Settings > About. Keep existing data; do not reset or clear all data for these checks.")
for i, (title, steps) in enumerate(selected, 2): print(f"{i}. **{title}:** {steps}")
if not selected: print("2. Launch the app and check your usual saved recipe and Journal entry still open. CI/workflow-only changes require their linked run evidence, not a device-only claim.")
print("\n**Not proven by these notes:** source inclusion is not device acceptance. A build/run link is not a full QA pass. Failed, skipped, queued or unrun checks remain unverified; use the release's actual QA evidence. If a step fails, report the build number, screen, steps and a screenshot.\n")
PYTEST
cat <<FOOT

---
**Version** $VERSION · **Build** $BUILD · **Commit** [\`${SOURCE::7}\`](https://github.com/melusi-k/ate-ios/commit/$SOURCE) · [CI run]($RUN)

**Install:** download \`$IPA\` ($KIND). Unsigned builds install with Sideloadly or AltStore. With a free Apple ID the app expires after 7 days and needs Developer Mode (Settings › Privacy & Security). Settings › About shows the installed build.
FOOT
