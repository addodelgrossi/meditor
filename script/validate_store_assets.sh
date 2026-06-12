#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

plutil -lint Configuration/Info.plist Configuration/Meditor.entitlements \
  Configuration/MeditorQuickLook-Info.plist Configuration/MeditorQuickLook.entitlements \
  Configuration/ExportOptions.plist Configuration/DeveloperIDExportOptions.plist \
  Configuration/ValidationOptions.plist \
  Sources/Meditor/Resources/PrivacyInfo.xcprivacy >/dev/null
plutil -lint Sources/MeditorQuickLook/en.lproj/Localizable.strings \
  Sources/MeditorQuickLook/pt-BR.lproj/Localizable.strings >/dev/null
jq -e . Sources/Meditor/Resources/Localizable.xcstrings >/dev/null
jq -e . Assets/Assets.xcassets/Contents.json Assets/Assets.xcassets/AppIcon.appiconset/Contents.json >/dev/null

test -f LICENSE
test -f Sources/Meditor/Resources/LICENSE-Meditor.txt
test -f Sources/Meditor/Resources/Mermaid/LICENSE-mermaid.txt
test -f README.pt-BR.md
test -f CONTRIBUTING.md
test -f RELEASING.md
test -f docs/index.html
test -f docs/pt-BR/index.html
test -f docs/privacy/index.html
test -f docs/pt-BR/privacy/index.html
test -f docs/support/index.html
test -f docs/pt-BR/support/index.html
test -f docs/assets/quick-look-preview.svg
test -f docs/assets/quick-look-demo.mp4
test -f docs/assets/quick-look-demo.jpg
test -f docs/assets/docs-demo-en.mp4
test -f docs/assets/docs-demo-en.gif
test -f docs/assets/docs-demo-en.jpg
test -f docs/assets/docs-demo-pt-BR.mp4
test -f docs/assets/docs-demo-pt-BR.gif
test -f docs/assets/docs-demo-pt-BR.jpg
test -f docs/assets/workspace-en.webp
test -f docs/assets/workspace-pt-BR.webp
test -f docs/assets/social-card.png

rg -q '^PRODUCT_BUNDLE_IDENTIFIER = com\.addodelgrossi\.meditor$' Configuration/Meditor.xcconfig
rg -q '^MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+$' Configuration/Meditor.xcconfig
rg -q '^CURRENT_PROJECT_VERSION = [1-9][0-9]*$' Configuration/Meditor.xcconfig
rg -q '^APP_STORE_DEVELOPMENT_TEAM="\$\{APP_STORE_DEVELOPMENT_TEAM:-QHURUB34Z9\}"$' script/archive.sh
rg -q '^DEVELOPER_ID_TEAM="\$\{DEVELOPER_ID_TEAM:-QHURUB34Z9\}"$' script/package_github_release.sh
test "$(plutil -extract method raw Configuration/DeveloperIDExportOptions.plist)" = "developer-id"
test "$(plutil -extract signingStyle raw Configuration/DeveloperIDExportOptions.plist)" = "automatic"
test "$(plutil -extract teamID raw Configuration/DeveloperIDExportOptions.plist)" = "QHURUB34Z9"
rg -q '^    CODE_SIGN_IDENTITY: "-"$' project.yml
rg -q '^    CODE_SIGN_STYLE: Manual$' project.yml
rg -q '<string>CA92\.1</string>' Sources/Meditor/Resources/PrivacyInfo.xcprivacy
rg -q '<key>com\.apple\.security\.app-sandbox</key>' Configuration/Meditor.entitlements
rg -q '<key>com\.apple\.security\.files\.user-selected\.read-write</key>' Configuration/Meditor.entitlements
rg -q '<key>com\.apple\.security\.network\.client</key>' Configuration/Meditor.entitlements
rg -q '<string>com\.addodelgrossi\.meditor\.mermaid</string>' Configuration/MeditorQuickLook-Info.plist
rg -q '<string>com\.apple\.quicklook\.preview</string>' Configuration/MeditorQuickLook-Info.plist
rg -q '<key>com\.apple\.security\.files\.user-selected\.read-only</key>' Configuration/MeditorQuickLook.entitlements
rg -q "connect-src 'none'" Sources/Meditor/Resources/renderer.html
rg -q 'docs-demo-en\.gif' README.md
rg -q 'docs-demo-pt-BR\.gif' README.pt-BR.md
rg -q 'releases/latest' README.md README.pt-BR.md docs/index.html docs/pt-BR/index.html
rg -q 'quick-look-demo\.mp4' docs/index.html docs/pt-BR/index.html
rg -q '^  version: 1\.1\.0$' AppStore/metadata.yml
rg -q '^  build: 3$' AppStore/metadata.yml
rg -q 'explicitly choose Publish' docs/privacy/index.html AppStore/en-US/description.txt
rg -q 'escolhe explicitamente Publicar' docs/pt-BR/privacy/index.html AppStore/pt-BR/description.txt

if rg -q 'no network-based features|document content never leaves the device|não possui recursos baseados em rede|conteúdo dos documentos nunca deixa o dispositivo' \
  README.md README.pt-BR.md docs AppStore/en-US AppStore/pt-BR; then
  echo "Documentation contains an outdated claim that publishing never uses the network" >&2
  exit 1
fi

if rg -q 'DevelopmentTeam =|DEVELOPMENT_TEAM = ' \
  Meditor.xcodeproj/project.pbxproj Configuration/Meditor.xcconfig project.yml; then
  echo "Local Xcode builds must not require an Apple Developer team" >&2
  exit 1
fi

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
