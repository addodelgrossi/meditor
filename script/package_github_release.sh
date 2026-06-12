#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F ' = ' '$1 == "MARKETING_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(awk -F ' = ' '$1 == "CURRENT_PROJECT_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
DEVELOPER_ID_TEAM="${DEVELOPER_ID_TEAM:-QHURUB34Z9}"
DIST_DIR="${DEVELOPER_ID_DIST_DIR:-$ROOT_DIR/dist/DeveloperID}"
ARCHIVE_PATH="${DEVELOPER_ID_ARCHIVE_PATH:-$DIST_DIR/Meditor.xcarchive}"
EXPORT_PATH="${DEVELOPER_ID_EXPORT_PATH:-$DIST_DIR/Export}"
STAGING_PATH="${DEVELOPER_ID_STAGING_PATH:-$DIST_DIR/DMG}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/Meditor-$MARKETING_VERSION.dmg}"
CHECKSUM_PATH="${CHECKSUM_PATH:-$DMG_PATH.sha256}"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -Fq "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" >/dev/null
  fi
  if [[ -n "$MOUNT_POINT" ]]; then
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MARKETING_VERSION must use the format 1.2.3: $MARKETING_VERSION" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER must be a positive integer: $BUILD_NUMBER" >&2
  exit 2
fi

for name in APP_STORE_CONNECT_API_KEY_PATH APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_API_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required App Store Connect API credential: $name" >&2
    exit 2
  fi
done

export MARKETING_VERSION BUILD_NUMBER DEVELOPER_ID_TEAM
source "$ROOT_DIR/script/app_store_connect_auth.sh"

"$ROOT_DIR/script/generate_project.sh"
"$ROOT_DIR/script/validate_store_assets.sh"

rm -rf "$DIST_DIR" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$DIST_DIR"

# The account-free archive is re-signed with Developer ID during export.
xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM= \
  clean archive

"$ROOT_DIR/script/validate_release.sh" "$ARCHIVE_PATH"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT_DIR/Configuration/DeveloperIDExportOptions.plist" \
  "${XCODE_AUTH_ARGS[@]}"

APP="$EXPORT_PATH/Meditor.app"
"$ROOT_DIR/script/validate_developer_id.sh" "$APP"

mkdir -p "$STAGING_PATH"
ditto "$APP" "$STAGING_PATH/Meditor.app"
ln -s /Applications "$STAGING_PATH/Applications"

hdiutil create \
  -volname "Meditor" \
  -srcfolder "$STAGING_PATH" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --key "$APP_STORE_CONNECT_API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/meditor-dmg.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
"$ROOT_DIR/script/validate_developer_id.sh" "$MOUNT_POINT/Meditor.app"
spctl --assess --type execute --verbose=4 "$MOUNT_POINT/Meditor.app"
hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT"
MOUNT_POINT=""

(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" >"$CHECKSUM_PATH"
)

echo "Notarized GitHub release assets are ready:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
