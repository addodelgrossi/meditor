#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/dist/DeveloperID/Export/Meditor.app}"
EXPECTED_TEAM_ID="${DEVELOPER_ID_TEAM:-QHURUB34Z9}"
EXPECTED_MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F ' = ' '$1 == "MARKETING_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
EXPECTED_BUILD_NUMBER="${BUILD_NUMBER:-$(awk -F ' = ' '$1 == "CURRENT_PROJECT_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
QUICK_LOOK="$APP/Contents/PlugIns/MeditorQuickLook.appex"

if [[ ! -d "$APP" ]]; then
  echo "Developer ID app not found: $APP" >&2
  exit 1
fi

if [[ ! -d "$QUICK_LOOK" ]]; then
  echo "Quick Look extension not found: $QUICK_LOOK" >&2
  exit 1
fi

validate_bundle() {
  local bundle="$1"
  local expected_identifier="$2"
  local info="$bundle/Contents/Info.plist"
  local signing_info

  test "$(plutil -extract CFBundleIdentifier raw "$info")" = "$expected_identifier"
  test "$(plutil -extract CFBundleShortVersionString raw "$info")" = "$EXPECTED_MARKETING_VERSION"
  test "$(plutil -extract CFBundleVersion raw "$info")" = "$EXPECTED_BUILD_NUMBER"

  codesign --verify --strict --verbose=2 "$bundle"
  signing_info="$(codesign -dvvv "$bundle" 2>&1)"
  grep -q '^Authority=Developer ID Application:' <<<"$signing_info"
  grep -q "^TeamIdentifier=$EXPECTED_TEAM_ID$" <<<"$signing_info"
  grep -q '^flags=.*runtime' <<<"$signing_info"
  grep -q '^Timestamp=' <<<"$signing_info"
}

codesign --verify --deep --strict --verbose=2 "$APP"
validate_bundle "$APP" "com.addodelgrossi.meditor"
validate_bundle "$QUICK_LOOK" "com.addodelgrossi.meditor.quicklook"

entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
quick_look_entitlements="$(codesign -d --entitlements :- "$QUICK_LOOK" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<<"$entitlements"
grep -q 'com.apple.security.files.user-selected.read-write' <<<"$entitlements"
grep -q 'com.apple.security.network.client' <<<"$entitlements"
grep -q 'com.apple.security.app-sandbox' <<<"$quick_look_entitlements"
grep -q 'com.apple.security.files.user-selected.read-only' <<<"$quick_look_entitlements"

if grep -q 'com.apple.security.network.' <<<"$quick_look_entitlements"; then
  echo "Developer ID Quick Look extension unexpectedly has network access" >&2
  exit 1
fi

if [[ "$(plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null <<<"$entitlements" || true)" == "true" ]] ||
  [[ "$(plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null <<<"$quick_look_entitlements" || true)" == "true" ]]; then
  echo "Developer ID release unexpectedly allows debugging" >&2
  exit 1
fi

if grep -q 'com.apple.security.temporary-exception' <<<"$entitlements$quick_look_entitlements"; then
  echo "Developer ID release contains temporary sandbox exceptions" >&2
  exit 1
fi

echo "Developer ID signatures, hardened runtime, entitlements, and metadata are valid."
