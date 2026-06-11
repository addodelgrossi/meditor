#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCALE="${1:-en-US}"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP="$DERIVED_DATA/Build/Products/Release/Meditor.app"
OUTPUT="$ROOT_DIR/AppStore/screenshots/$LOCALE"

cleanup() {
  pkill -x Meditor >/dev/null 2>&1 || true
}
trap cleanup EXIT

case "$LOCALE" in
  en-US) APPLE_LANGUAGE="en" ;;
  pt-BR) APPLE_LANGUAGE="pt-BR" ;;
  *) echo "usage: $0 [en-US|pt-BR]" >&2; exit 2 ;;
esac

"$ROOT_DIR/script/generate_project.sh"
xcodebuild \
  -project "$ROOT_DIR/Meditor.xcodeproj" \
  -scheme Meditor \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

mkdir -p "$OUTPUT"

window_id() {
  swift -e 'import CoreGraphics
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "Meditor" {
    if let id = window[kCGWindowNumber as String] as? Int { print(id); break }
}' 2>/dev/null
}

capture() {
  local name="$1"
  sleep 5
  local id
  id="$(window_id)"
  if [[ -z "$id" ]]; then
    echo "Could not find the Meditor window. Grant Screen Recording permission to the terminal and retry." >&2
    exit 1
  fi
  if ! screencapture -o -l "$id" "$OUTPUT/$name.png"; then
    rm -f "$OUTPUT/$name.png"
    cat >&2 <<'EOF'
macOS blocked the screenshot. Grant Screen & System Audio Recording access to
Codex or Terminal in System Settings > Privacy & Security, then retry.
EOF
    exit 1
  fi
  sips -z 1800 2880 "$OUTPUT/$name.png" >/dev/null
}

launch() {
  local source="${1:-}"
  pkill -x Meditor >/dev/null 2>&1 || true
  if [[ -n "$source" ]]; then
    /usr/bin/open -n "$APP" "$source" --args \
      -AppleLanguages "($APPLE_LANGUAGE)" \
      -ApplePersistenceIgnoreState YES
  else
    /usr/bin/open -n "$APP" --args \
      -AppleLanguages "($APPLE_LANGUAGE)" \
      -ApplePersistenceIgnoreState YES
  fi
  sleep 2
  osascript -e 'tell application "System Events" to tell process "Meditor" to set size of window 1 to {1440, 900}' >/dev/null
}

launch
capture "01-welcome"

index=2
for source in flowchart sequence architecture; do
  launch "$ROOT_DIR/AppStore/ScreenshotSources/$source.mmd"
  capture "$(printf '%02d' "$index")-$source-split"
  index=$((index + 1))
done

osascript \
  -e 'tell application "Meditor" to activate' \
  -e 'tell application "System Events" to keystroke "3" using {command down, option down}' >/dev/null
capture "05-architecture-preview"

echo "Screenshots prepared in $OUTPUT. Review all images before upload."
