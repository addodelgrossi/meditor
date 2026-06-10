#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-$ROOT_DIR/dist/Meditor.xcarchive}"
APP="$ARCHIVE_PATH/Products/Applications/Meditor.app"

if [[ ! -d "$APP" ]]; then
  echo "Archive app not found: $APP" >&2
  exit 1
fi

INFO="$APP/Contents/Info.plist"
PRIVACY="$APP/Contents/Resources/PrivacyInfo.xcprivacy"

test "$(plutil -extract CFBundleIdentifier raw "$INFO")" = "com.addodelgrossi.meditor"
test "$(plutil -extract CFBundleShortVersionString raw "$INFO")" = "1.0.0"
test "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$INFO")" = "false"
test -f "$PRIVACY"

codesign --verify --deep --strict --verbose=2 "$APP"
entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<<"$entitlements"
grep -q 'com.apple.security.files.user-selected.read-write' <<<"$entitlements"
grep -q 'com.apple.security.network.client' <<<"$entitlements"
grep -q "connect-src 'none'" "$APP/Contents/Resources/renderer.html"

if [[ "$(plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null <<<"$entitlements" || true)" == "true" ]]; then
  echo "Release archive unexpectedly allows debugging" >&2
  exit 1
fi

if grep -q 'com.apple.security.temporary-exception' <<<"$entitlements"; then
  echo "Release archive contains temporary sandbox exceptions" >&2
  exit 1
fi

echo "Release archive signature, sandbox, privacy, and metadata are valid."
