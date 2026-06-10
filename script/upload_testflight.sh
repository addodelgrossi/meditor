#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/Meditor.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/dist/AppStoreUpload}"

if [[ "${1:-}" != "--confirm-upload" ]]; then
  echo "This uploads the archive to App Store Connect." >&2
  echo "Run: $0 --confirm-upload" >&2
  exit 2
fi

"$ROOT_DIR/script/validate_release.sh" "$ARCHIVE_PATH"
rm -rf "$EXPORT_PATH"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT_DIR/Configuration/ExportOptions.plist" \
  -allowProvisioningUpdates
