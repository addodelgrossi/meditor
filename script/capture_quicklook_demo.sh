#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/quicklook-demo"
OUTPUT_DIR="$ROOT_DIR/docs/assets"
SOURCE="$WORK_DIR/architecture.mmd"
RAW_VIDEO="$WORK_DIR/quick-look-demo.mov"
MP4="$OUTPUT_DIR/quick-look-demo.mp4"
GIF="$OUTPUT_DIR/quick-look-demo.gif"
POSTER="$OUTPUT_DIR/quick-look-demo.jpg"

command -v ffmpeg >/dev/null || {
  echo "ffmpeg is required. Install it with: brew install ffmpeg" >&2
  exit 1
}

"$ROOT_DIR/script/verify_quicklook.sh"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cp "$ROOT_DIR/AppStore/ScreenshotSources/architecture.mmd" "$SOURCE"

app_was_running=false
if pgrep -x Meditor >/dev/null; then
  app_was_running=true
fi

osascript <<EOF
tell application "Finder"
  activate
  open POSIX file "$WORK_DIR"
  delay 1
  set bounds of front window to {120, 100, 1280, 800}
  set current view of front window to list view
  select POSIX file "$SOURCE"
end tell
EOF

sleep 1
screencapture -v -V8 -D1 -x "$RAW_VIDEO" &
capture_pid=$!
sleep 1
osascript -e 'tell application "System Events" to key code 49'
sleep 5
osascript -e 'tell application "System Events" to key code 49'

capture_succeeded=true
if ! wait "$capture_pid"; then
  capture_succeeded=false
fi

if [[ "$app_was_running" == false ]] && pgrep -x Meditor >/dev/null; then
  echo "Meditor unexpectedly opened during the Quick Look demo." >&2
  exit 1
fi

if [[ "$capture_succeeded" == false || ! -s "$RAW_VIDEO" ]]; then
  cat >&2 <<'EOF'
macOS blocked the screen recording. Grant Screen & System Audio Recording
access to Codex or Terminal in System Settings > Privacy & Security, then retry.
EOF
  exit 1
fi

ffmpeg -y -hide_banner -loglevel error \
  -i "$RAW_VIDEO" \
  -vf "fps=30,scale='min(1440,iw)':-2:flags=lanczos" \
  -an -c:v libx264 -crf 23 -preset medium -pix_fmt yuv420p -movflags +faststart \
  "$MP4"

ffmpeg -y -hide_banner -loglevel error \
  -ss 3 -i "$RAW_VIDEO" -frames:v 1 \
  -vf "scale='min(1440,iw)':-2:flags=lanczos" -q:v 3 \
  "$POSTER"

palette="$WORK_DIR/palette.png"
ffmpeg -y -hide_banner -loglevel error \
  -i "$RAW_VIDEO" \
  -vf "fps=12,scale='min(960,iw)':-2:flags=lanczos,palettegen=max_colors=128" \
  "$palette"
ffmpeg -y -hide_banner -loglevel error \
  -i "$RAW_VIDEO" -i "$palette" \
  -lavfi "fps=12,scale='min(960,iw)':-2:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer" \
  "$GIF"

echo "Quick Look demo assets written to $OUTPUT_DIR."
