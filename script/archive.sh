#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/Meditor.xcarchive}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

"$ROOT_DIR/script/generate_project.sh"
"$ROOT_DIR/script/validate_store_assets.sh"

rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean archive

"$ROOT_DIR/script/validate_release.sh" "$ARCHIVE_PATH"
echo "Archive ready: $ARCHIVE_PATH"
