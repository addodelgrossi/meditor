#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/Meditor.xcarchive}"
MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F ' = ' '$1 == "MARKETING_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(awk -F ' = ' '$1 == "CURRENT_PROJECT_VERSION" { print $2 }' "$ROOT_DIR/Configuration/Meditor.xcconfig")}"
APP_STORE_DEVELOPMENT_TEAM="${APP_STORE_DEVELOPMENT_TEAM:-QHURUB34Z9}"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MARKETING_VERSION must use the format 1.2.3: $MARKETING_VERSION" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER must be a positive integer: $BUILD_NUMBER" >&2
  exit 2
fi

export MARKETING_VERSION BUILD_NUMBER
source "$ROOT_DIR/script/app_store_connect_auth.sh"

"$ROOT_DIR/script/generate_project.sh"
"$ROOT_DIR/script/validate_store_assets.sh"

rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  "${XCODE_AUTH_ARGS[@]}" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$APP_STORE_DEVELOPMENT_TEAM" \
  clean archive

"$ROOT_DIR/script/validate_release.sh" "$ARCHIVE_PATH"
echo "Archive ready: $ARCHIVE_PATH"
