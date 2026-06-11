#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

plutil -lint Configuration/Info.plist Configuration/Meditor.entitlements \
  Configuration/MeditorQuickLook-Info.plist Configuration/MeditorQuickLook.entitlements \
  Configuration/ExportOptions.plist Configuration/ValidationOptions.plist \
  Sources/Meditor/Resources/PrivacyInfo.xcprivacy >/dev/null
plutil -lint Sources/MeditorQuickLook/en.lproj/Localizable.strings \
  Sources/MeditorQuickLook/pt-BR.lproj/Localizable.strings >/dev/null
jq -e . Sources/Meditor/Resources/Localizable.xcstrings >/dev/null
jq -e . Assets/Assets.xcassets/Contents.json Assets/Assets.xcassets/AppIcon.appiconset/Contents.json >/dev/null

test -f LICENSE
test -f Sources/Meditor/Resources/LICENSE-Meditor.txt
test -f Sources/Meditor/Resources/Mermaid/LICENSE-mermaid.txt
test -f docs/privacy/index.html
test -f docs/support/index.html
test -f docs/assets/quick-look-preview.svg

rg -q '^PRODUCT_BUNDLE_IDENTIFIER = com\.addodelgrossi\.meditor$' Configuration/Meditor.xcconfig
rg -q '^MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+$' Configuration/Meditor.xcconfig
rg -q '^CURRENT_PROJECT_VERSION = [1-9][0-9]*$' Configuration/Meditor.xcconfig
rg -q '^DEVELOPMENT_TEAM = QHURUB34Z9$' Configuration/Meditor.xcconfig
rg -q '<string>CA92\.1</string>' Sources/Meditor/Resources/PrivacyInfo.xcprivacy
rg -q '<key>com\.apple\.security\.app-sandbox</key>' Configuration/Meditor.entitlements
rg -q '<key>com\.apple\.security\.files\.user-selected\.read-write</key>' Configuration/Meditor.entitlements
rg -q '<key>com\.apple\.security\.network\.client</key>' Configuration/Meditor.entitlements
rg -q '<string>com\.addodelgrossi\.meditor\.mermaid</string>' Configuration/MeditorQuickLook-Info.plist
rg -q '<string>com\.apple\.quicklook\.preview</string>' Configuration/MeditorQuickLook-Info.plist
rg -q '<key>com\.apple\.security\.files\.user-selected\.read-only</key>' Configuration/MeditorQuickLook.entitlements
rg -q "connect-src 'none'" Sources/Meditor/Resources/renderer.html
rg -q 'quick-look-preview\.svg' README.md docs/index.html
rg -q 'quick-look-demo\.mp4' docs/index.html

if rg -q '<key>com\.apple\.security\.network\.' Configuration/MeditorQuickLook.entitlements; then
  echo "Quick Look extension must not request network entitlements" >&2
  exit 1
fi

if rg -q '<script[^>]+src="https?://' Sources/Meditor/Resources/renderer.html; then
  echo "renderer.html must not reference the network" >&2
  exit 1
fi

missing_localizations="$(jq '[.strings[] | select((.localizations["pt-BR"].stringUnit.state // "missing") != "translated")] | length' Sources/Meditor/Resources/Localizable.xcstrings)"
if [[ "$missing_localizations" != "0" ]]; then
  echo "$missing_localizations pt-BR app localizations are missing" >&2
  exit 1
fi

for locale in en-US pt-BR; do
  for field in subtitle keywords promotional_text description review_notes; do
    test -s "AppStore/$locale/$field.txt"
  done
  keyword_bytes="$(wc -c <"AppStore/$locale/keywords.txt" | tr -d ' ')"
  if (( keyword_bytes > 100 )); then
    echo "AppStore/$locale/keywords.txt exceeds 100 bytes" >&2
    exit 1
  fi
done

echo "Store assets and distribution configuration are valid."
