#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP="$DERIVED_DATA/Build/Products/Debug/Meditor.app"

"$ROOT_DIR/script/generate_project.sh"

xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP/Contents/MacOS/Meditor"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "Meditor"'
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x Meditor >/dev/null
    codesign --verify --deep --strict "$APP"
    ;;
  *)
    echo "usage: $0 [run|debug|logs|verify]" >&2
    exit 2
    ;;
esac
