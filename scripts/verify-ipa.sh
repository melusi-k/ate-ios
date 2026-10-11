#!/usr/bin/env bash
# Artifact smoke test for a PUBLISHED IPA: checksum, structure, versions, bundle id, extensions, entitlements,
# privacy manifest, icon and size limits. Usage: verify-ipa.sh <ipa> <sha256-file> <short-version> <build-number>
set -euo pipefail
IPA="$1"; SUMFILE="$2"; WANT_SV="$3"; WANT_BV="$4"
MAX_IPA_MB=${MAX_IPA_MB:-150}; MAX_APP_MB=${MAX_APP_MB:-400}
fail() { echo "::error::verify-ipa: $*"; exit 1; }
ok() { echo "  ✓ $*"; }

EXPECTED=$(awk '{print $1}' "$SUMFILE")
ACTUAL=$(shasum -a 256 "$IPA" | awk '{print $1}')
[ "$EXPECTED" = "$ACTUAL" ] || fail "SHA-256 mismatch (published $EXPECTED, downloaded $ACTUAL)"; ok "sha256 $ACTUAL"

SIZE_MB=$(( $(stat -f%z "$IPA" 2>/dev/null || stat -c%s "$IPA") / 1024 / 1024 ))
[ "$SIZE_MB" -le "$MAX_IPA_MB" ] || fail "IPA is ${SIZE_MB} MB (limit ${MAX_IPA_MB} MB)"; ok "IPA ${SIZE_MB} MB"

W=$(mktemp -d); unzip -q "$IPA" -d "$W" || fail "unzip failed"
A="$W/Payload/Ate.app"; [ -d "$A" ] || fail "Payload/Ate.app missing"
APP_MB=$(du -sm "$A" | awk '{print $1}'); [ "$APP_MB" -le "$MAX_APP_MB" ] || fail "app is ${APP_MB} MB"; ok "app ${APP_MB} MB unpacked"

PL="$A/Info.plist"
SV=$(plutil -extract CFBundleShortVersionString raw -o - "$PL"); BV=$(plutil -extract CFBundleVersion raw -o - "$PL")
[ "$SV" = "$WANT_SV" ] || fail "version $SV != $WANT_SV"; [ "$BV" = "$WANT_BV" ] || fail "build $BV != $WANT_BV"; ok "version $SV ($BV)"
[ "$(plutil -extract CFBundleIdentifier raw -o - "$PL")" = com.melusik.ate ] || fail "bundle id"; ok "bundle id com.melusik.ate"

[ -d "$A/PlugIns/AteWidgets.appex" ] || fail "widget extension missing"
[ "$(plutil -extract CFBundleIdentifier raw -o - "$A/PlugIns/AteWidgets.appex/Info.plist")" = com.melusik.ate.widgets ] || fail "widget bundle id"
for X in "$A"/PlugIns/*.appex; do
  [ "$(plutil -extract CFBundleVersion raw -o - "$X/Info.plist")" = "$WANT_BV" ] || fail "$(basename "$X") build number"
done; ok "extensions: $(ls "$A/PlugIns" | tr '\n' ' ')"
if [ -d "$A/Watch" ]; then
  [ -d "$A/Watch/AteWatch.app" ] || fail "Watch folder without AteWatch.app"
  [ "$(plutil -extract CFBundleVersion raw -o - "$A/Watch/AteWatch.app/Info.plist")" = "$WANT_BV" ] || fail "watch build number"; ok "watch app"
fi
[ -d "$A/Metadata.appintents" ] || fail "Metadata.appintents missing"; ok "App Intents metadata"

ENT=$(codesign -d --entitlements - "$A" 2>/dev/null || true)
echo "$ENT" | grep -q application-groups || fail "App Group entitlement missing"
echo "$ENT" | grep -q com.apple.developer.healthkit || fail "HealthKit entitlement missing"; ok "entitlements"

[ -f "$A/PrivacyInfo.xcprivacy" ] || fail "privacy manifest missing"
plutil -lint "$A/PrivacyInfo.xcprivacy" >/dev/null || fail "privacy manifest invalid"
plutil -extract NSPrivacyAccessedAPITypes json -o - "$A/PrivacyInfo.xcprivacy" >/dev/null || fail "privacy manifest has no NSPrivacyAccessedAPITypes"; ok "privacy manifest"

plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "$PL" >/dev/null || fail "CFBundleIcons missing"
ls "$A"/AppIcon*.png >/dev/null 2>&1 || grep -q AppIcon <(ls "$A") || fail "compiled app icon missing"; ok "app icon"
echo "verify-ipa: all checks passed"
