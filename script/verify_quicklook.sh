#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/.build/xcode}"
APP="$DERIVED_DATA/Build/Products/Debug/Meditor.app"
EXTENSION="$APP/Contents/PlugIns/MeditorQuickLook.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/script/generate_project.sh"
xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

test -d "$EXTENSION"
codesign --verify --deep --strict "$APP"
test "$(plutil -extract CFBundleIdentifier raw "$EXTENSION/Contents/Info.plist")" = \
  "com.addodelgrossi.meditor.quicklook"
test "$(plutil -extract NSExtension.NSExtensionAttributes.QLSupportedContentTypes.0 raw "$EXTENSION/Contents/Info.plist")" = \
  "com.addodelgrossi.meditor.mermaid"
test -f "$EXTENSION/Contents/Resources/renderer.html"
test -f "$EXTENSION/Contents/Resources/mermaid.min.js"
extension_entitlements="$(codesign -d --entitlements :- "$EXTENSION" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<<"$extension_entitlements"
grep -q 'com.apple.security.files.user-selected.read-only' <<<"$extension_entitlements"
if grep -q 'com.apple.security.network.' <<<"$extension_entitlements"; then
  echo "Quick Look extension unexpectedly has network access" >&2
  exit 1
fi

pluginkit -a "$EXTENSION"
"$LSREGISTER" -f -R -trusted "$APP"
qlmanage -r cache >/dev/null

if ! pluginkit -m -A -D -p com.apple.quicklook.preview |
  grep -q "com.addodelgrossi.meditor.quicklook"; then
  echo "Quick Look extension was not registered" >&2
  exit 1
fi

fixtures=()
trap 'rm -f "${fixtures[@]}"' EXIT
for file_extension in mmd mermaid; do
  fixture="$(mktemp -t meditor-quicklook).$file_extension"
  fixtures+=("$fixture")
  printf 'flowchart LR\n    Finder --> QuickLook\n' >"$fixture"

  if [[ "$(mdls -raw -name kMDItemContentType "$fixture")" != "com.addodelgrossi.meditor.mermaid" ]]; then
    echo "Finder did not resolve .$file_extension to the Meditor Mermaid content type" >&2
    exit 1
  fi
done

echo "Quick Look extension is built, signed, registered, and associated with Mermaid files."
