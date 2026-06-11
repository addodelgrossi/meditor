#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/Meditor.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/dist/AppStoreValidation}"
source "$ROOT_DIR/script/app_store_connect_auth.sh"

"$ROOT_DIR/script/validate_release.sh" "$ARCHIVE_PATH"
rm -rf "$EXPORT_PATH"

if ! xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT_DIR/Configuration/ValidationOptions.plist" \
  "${XCODE_AUTH_ARGS[@]}"; then
  cat >&2 <<'EOF'
App Store validation could not finish. Confirm that an App Store Connect
macOS app record exists for com.addodelgrossi.meditor and that all agreements
for team ADDO DEL GROSSI are active, then retry.
EOF
  exit 1
fi
