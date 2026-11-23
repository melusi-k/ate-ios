#!/bin/bash
# Advisory review-rule checks for the AGENTS.md mechanical rules.
# Prints every hit with file:line, compares per-rule counts against
# scripts/review-rules-baseline.txt, and fails only when a rule's count
# EXCEEDS its baseline (a new violation). Existing baselined hits never
# fail the job. When a rule's count drops, lower its baseline.
# No dependencies beyond bash, awk, grep, perl (all preinstalled on
# GitHub-hosted runners).
set -u
cd "$(git rev-parse --show-toplevel)"

APP_DIRS="Ate AteWatch AteWidgets AteWatchWidgets AteShare AteClip Shared SharedWidgets AteTests AteUITests AteClipTests AteModelReadinessTests"
TEST_DIRS="AteTests AteUITests AteClipTests AteModelReadinessTests"
BASELINE="scripts/review-rules-baseline.txt"

hits() { # rule_name, then hits on stdin; prints them and returns the count via stdout tail
  local rule="$1"
  local lines
  lines="$(cat)"
  local count=0
  if [ -n "$lines" ]; then
    count="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
    printf '%s\n' "$lines" | while IFS= read -r line; do
      echo "  [$rule] $line"
    done
  fi
  echo "COUNT $rule $count"
}

all_swift() { # grep pattern
  grep -rn "$1" $APP_DIRS --include='*.swift' 2>/dev/null || true
}

echo "== Review-rule checks (advisory ratchet; baseline: $BASELINE) =="

r1="$(all_swift '\.foregroundColor(' | hits foregroundcolor)"
r2="$(all_swift '\.cornerRadius(' | hits cornerradius)"
# Deprecated single-parameter onChange(of:) closure form: `{ x in` with no
# comma before `in`, or the old `perform:` argument. The two-parameter and
# zero-parameter forms are fine.
r3="$( { grep -rn '\.onChange(of:' $APP_DIRS --include='*.swift' 2>/dev/null || true; } | perl -ne '
  print if /\.onChange\(of:[^)]*\)\s*\{\s*[A-Za-z_][A-Za-z0-9_]*\s+in\b/
         && !/\.onChange\(of:[^)]*\)\s*\{[^,}]*,/;
  print if /\.onChange\(of:[^)]*,\s*perform:/;
' | hits onchange-single-param)"
# Task { ... } created inside an .onAppear { } block (brace-depth tracked).
r4="$( { find $APP_DIRS -name '*.swift' 2>/dev/null; } | sort | xargs awk '
  /\.onAppear[[:space:]]*\{/ && !inblock {
    inblock=1
    depth=gsub(/\{/,"{")-gsub(/\}/,"}")
    if ($0 ~ /Task[[:space:]]*\{/) print FILENAME ":" FNR ":" $0
    if (depth<=0) inblock=0
    next
  }
  inblock {
    depth+=gsub(/\{/,"{")-gsub(/\}/,"}")
    if ($0 ~ /Task[[:space:]]*\{/) print FILENAME ":" FNR ":" $0
    if (depth<=0) inblock=0
  }
' | hits task-in-onappear)"
r5="$( { grep -rnE '#(expect|require)\(!' $TEST_DIRS --include='*.swift' 2>/dev/null || true; } | hits expect-negation)"
r6="$( { grep -rn 'Task\.sleep' $TEST_DIRS --include='*.swift' 2>/dev/null || true; } | hits task-sleep-tests)"

printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$r1" "$r2" "$r3" "$r4" "$r5" "$r6" | grep -v '^COUNT'

echo "== Counts vs baseline =="
fail=0
for line in $(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$r1" "$r2" "$r3" "$r4" "$r5" "$r6" | grep '^COUNT' | awk '{print $2"="$3}'); do
  rule="${line%%=*}"
  count="${line##*=}"
  base="$(grep -E "^${rule}=" "$BASELINE" 2>/dev/null | head -1 | cut -d= -f2)"
  if [ -z "$base" ]; then
    echo "  $rule: $count (no baseline entry; treating baseline as 0)"
    base=0
  fi
  if [ "$count" -gt "$base" ]; then
    echo "  $rule: $count > baseline $base  <-- NEW VIOLATION"
    fail=1
  elif [ "$count" -lt "$base" ]; then
    echo "  $rule: $count < baseline $base  (nice; lower the baseline in $BASELINE)"
  else
    echo "  $rule: $count (at baseline)"
  fi
done

if [ "$fail" -eq 1 ]; then
  echo "::error::New review-rule violations found. Fix them, or fix this script if it misfires. Do not raise the baseline to land new violations."
  exit 1
fi
echo "All rules at or below baseline. Once every rule reaches zero, flip this job to strict (empty baseline) to make the checks fully blocking."
exit 0
