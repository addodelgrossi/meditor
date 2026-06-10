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
QUICK_LOOK="$APP/Contents/PlugIns/MeditorQuickLook.appex"
QUICK_LOOK_INFO="$QUICK_LOOK/Contents/Info.plist"

test "$(plutil -extract CFBundleIdentifier raw "$INFO")" = "com.addodelgrossi.meditor"
test "$(plutil -extract CFBundleShortVersionString raw "$INFO")" = "1.0.0"
test "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$INFO")" = "false"
test -f "$PRIVACY"
test -d "$QUICK_LOOK"
test -f "$QUICK_LOOK/Contents/Resources/renderer.html"
test -f "$QUICK_LOOK/Contents/Resources/mermaid.min.js"
test "$(plutil -extract CFBundleIdentifier raw "$QUICK_LOOK_INFO")" = "com.addodelgrossi.meditor.quicklook"
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$QUICK_LOOK_INFO")" = "com.apple.quicklook.preview"
test "$(plutil -extract NSExtension.NSExtensionAttributes.QLSupportedContentTypes.0 raw "$QUICK_LOOK_INFO")" = "com.addodelgrossi.meditor.mermaid"

codesign --verify --deep --strict --verbose=2 "$APP"
entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
quick_look_entitlements="$(codesign -d --entitlements :- "$QUICK_LOOK" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<<"$entitlements"
grep -q 'com.apple.security.files.user-selected.read-write' <<<"$entitlements"
grep -q 'com.apple.security.network.client' <<<"$entitlements"
grep -q "connect-src 'none'" "$APP/Contents/Resources/renderer.html"
grep -q 'com.apple.security.app-sandbox' <<<"$quick_look_entitlements"
grep -q 'com.apple.security.files.user-selected.read-only' <<<"$quick_look_entitlements"
grep -q "connect-src 'none'" "$QUICK_LOOK/Contents/Resources/renderer.html"

if grep -q 'com.apple.security.network.' <<<"$quick_look_entitlements"; then
  echo "Release Quick Look extension unexpectedly has network access" >&2
  exit 1
fi

if [[ "$(plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null <<<"$entitlements" || true)" == "true" ]]; then
  echo "Release archive unexpectedly allows debugging" >&2
  exit 1
fi

if grep -q 'com.apple.security.temporary-exception' <<<"$entitlements"; then
  echo "Release archive contains temporary sandbox exceptions" >&2
  exit 1
fi

if [[ "$(plutil -extract com.apple.security.get-task-allow raw - 2>/dev/null <<<"$quick_look_entitlements" || true)" == "true" ]]; then
  echo "Release Quick Look extension unexpectedly allows debugging" >&2
  exit 1
fi

if grep -q 'com.apple.security.temporary-exception' <<<"$quick_look_entitlements"; then
  echo "Release Quick Look extension contains temporary sandbox exceptions" >&2
  exit 1
fi

echo "Release archive signature, sandbox, privacy, and metadata are valid."
