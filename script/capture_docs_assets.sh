#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-live}"
DERIVED_DATA="$ROOT_DIR/.build/docs-assets-xcode"
WORK_DIR="$ROOT_DIR/.build/docs-assets"
APP="$DERIVED_DATA/Build/Products/Release/Meditor.app"
OUTPUT_DIR="$ROOT_DIR/docs/assets"
SOURCE_DIR="$WORK_DIR/Diagrams"
SOURCE="$SOURCE_DIR/product-flow.mmd"

for command in ffmpeg magick cwebp qlmanage screencapture osascript; do
  command -v "$command" >/dev/null || {
    echo "$command is required to capture documentation assets." >&2
    exit 1
  }
done

cleanup() {
  pkill -x Meditor >/dev/null 2>&1 || true
}
trap cleanup EXIT

window_geometry() {
  swift -e 'import CoreGraphics
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "Meditor" {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Int, let y = bounds["Y"] as? Int,
          let width = bounds["Width"] as? Int, let height = bounds["Height"] as? Int
    else { continue }
    print("\(x),\(y),\(width),\(height)")
    break
}' 2>/dev/null
}

prepare_source() {
  rm -rf "$WORK_DIR"
  mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR"
  cp "$ROOT_DIR/AppStore/ScreenshotSources/flowchart.mmd" "$SOURCE"
}

build_app() {
  "$ROOT_DIR/script/generate_project.sh"
  xcodebuild \
    -project "$ROOT_DIR/Meditor.xcodeproj" \
    -scheme Meditor \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

launch_app() {
  local language="$1"
  pkill -x Meditor >/dev/null 2>&1 || true
  defaults write com.addodelgrossi.meditor appAppearance dark
  defaults write com.addodelgrossi.meditor defaultTheme dark
  /usr/bin/open -n "$APP" "$SOURCE" --args \
    -AppleLanguages "($language)" \
    -ApplePersistenceIgnoreState YES
  for _ in {1..20}; do
    [[ -n "$(window_geometry)" ]] && break
    sleep 1
  done
  [[ -n "$(window_geometry)" ]] || {
    echo "Meditor did not present a document window." >&2
    exit 1
  }
  sleep 2
}

capture_locale() {
  local locale="$1"
  local language="$2"
  local raw_video="$WORK_DIR/docs-demo-$locale.mov"
  local mp4="$OUTPUT_DIR/docs-demo-$locale.mp4"
  local poster="$OUTPUT_DIR/docs-demo-$locale.jpg"
  local gif="$OUTPUT_DIR/docs-demo-$locale.gif"
  local png="$WORK_DIR/workspace-$locale.png"
  local webp="$OUTPUT_DIR/workspace-$locale.webp"
  local palette="$WORK_DIR/palette-$locale.png"
  local updated_source
  local geometry x y width height click_x click_y

  launch_app "$language"
  geometry="$(window_geometry)"
  IFS=, read -r x y width height <<<"$geometry"
  click_x=$((x + width / 4))
  click_y=$((y + height / 2))

  updated_source="$(cat "$ROOT_DIR/AppStore/ScreenshotSources/flowchart.mmd")
    Ship --> Celebrate([Celebrate])"
  printf '%s' "$updated_source" | pbcopy

  screencapture -v -V9 -D1 -R"$geometry" -x "$raw_video" &
  local capture_pid=$!
  sleep 1
  osascript \
    -e 'tell application "Meditor" to activate' \
    -e 'tell application "System Events"' \
    -e "click at {$click_x, $click_y}" \
    -e 'keystroke "a" using command down' \
    -e 'keystroke "v" using command down' \
    -e 'end tell' >/dev/null
  sleep 4
  osascript \
    -e 'tell application "Meditor" to activate' \
    -e 'tell application "System Events" to keystroke "c" using {command down, shift down}' >/dev/null

  if ! wait "$capture_pid" || [[ ! -s "$raw_video" ]]; then
    cat >&2 <<'EOF'
macOS blocked the documentation recording. Grant Screen & System Audio Recording
and Accessibility access to Codex or Terminal, then retry.
EOF
    exit 1
  fi

  if ! screencapture -x -R"$geometry" "$png"; then
    echo "Unable to capture the Meditor documentation screenshot." >&2
    exit 1
  fi

  cwebp -quiet -q 82 -resize 1440 0 "$png" -o "$webp"

  ffmpeg -y -hide_banner -loglevel error \
    -i "$raw_video" \
    -vf "fps=30,scale=1280:-2:flags=lanczos" \
    -an -c:v libx264 -crf 24 -preset medium -pix_fmt yuv420p -movflags +faststart \
    "$mp4"
  ffmpeg -y -hide_banner -loglevel error \
    -ss 5 -i "$raw_video" -frames:v 1 \
    -vf "scale=1280:-2:flags=lanczos" -q:v 3 \
    "$poster"
  ffmpeg -y -hide_banner -loglevel error \
    -i "$raw_video" \
    -vf "fps=10,scale=900:-2:flags=lanczos,palettegen=max_colors=96" \
    "$palette"
  ffmpeg -y -hide_banner -loglevel error \
    -i "$raw_video" -i "$palette" \
    -lavfi "fps=10,scale=900:-2:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer" \
    "$gif"
}

generate_fallback_locale() {
  local locale="$1"
  local label="$2"
  local flow="$ROOT_DIR/AppStore/screenshots/pt-BR/02-flowchart-split.png"
  local architecture="$ROOT_DIR/AppStore/screenshots/pt-BR/04-architecture-split.png"
  local flow_frame="$WORK_DIR/fallback-flow-$locale.png"
  local architecture_frame="$WORK_DIR/fallback-architecture-$locale.png"
  local copied_frame="$WORK_DIR/fallback-copied-$locale.png"
  local mp4="$OUTPUT_DIR/docs-demo-$locale.mp4"
  local poster="$OUTPUT_DIR/docs-demo-$locale.jpg"
  local gif="$OUTPUT_DIR/docs-demo-$locale.gif"
  local palette="$WORK_DIR/palette-$locale.png"

  magick "$flow" -resize 1280x800! "$flow_frame"
  magick "$architecture" -resize 1280x800! "$architecture_frame"
  magick "$architecture_frame" \
    -font /System/Library/Fonts/Helvetica.ttc -fill '#1b2030e8' -stroke '#ffffff24' -strokewidth 1 \
    -draw 'roundrectangle 925,28 1240,82 27,27' \
    -fill '#7ce5b0' -stroke none -pointsize 18 -annotate +948+63 "✓  $label" \
    "$copied_frame"

  cwebp -quiet -q 82 "$flow_frame" -o "$OUTPUT_DIR/workspace-$locale.webp"
  magick "$flow_frame" -quality 88 "$poster"

  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -t 3.4 -i "$flow_frame" \
    -loop 1 -t 3.4 -i "$architecture_frame" \
    -loop 1 -t 3.4 -i "$copied_frame" \
    -filter_complex \
      "[0:v]fps=30,format=yuv420p[a];[1:v]fps=30,format=yuv420p[b];[2:v]fps=30,format=yuv420p[c];[a][b]xfade=transition=fade:duration=0.45:offset=2.95[ab];[ab][c]xfade=transition=fade:duration=0.45:offset=5.9,format=yuv420p[out]" \
    -map "[out]" -t 8.9 -an -c:v libx264 -crf 24 -preset medium -movflags +faststart \
    "$mp4"
  ffmpeg -y -hide_banner -loglevel error \
    -i "$mp4" \
    -vf "fps=10,scale=900:-2:flags=lanczos,palettegen=max_colors=96" \
    "$palette"
  ffmpeg -y -hide_banner -loglevel error \
    -i "$mp4" -i "$palette" \
    -lavfi "fps=10,scale=900:-2:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer" \
    "$gif"
}

generate_social_card() {
  local thumbnail="$WORK_DIR/social-card.svg.png"
  qlmanage -t -s 1200 -o "$WORK_DIR" "$OUTPUT_DIR/social-card.svg" >/dev/null
  magick "$thumbnail" -gravity center -crop 1200x630+0+0 +repage \
    "$OUTPUT_DIR/social-card.png"
}

generate_quick_look_fallback() {
  local thumbnail="$WORK_DIR/quick-look-preview.svg.png"
  qlmanage -t -s 1280 -o "$WORK_DIR" "$OUTPUT_DIR/quick-look-preview.svg" >/dev/null
  magick "$thumbnail" -gravity center -crop 1280x800+0+0 +repage \
    -background '#111426' -alpha remove -quality 88 "$OUTPUT_DIR/quick-look-demo.jpg"
  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -i "$OUTPUT_DIR/quick-look-demo.jpg" -t 6 \
    -vf "scale=1280:-2:flags=lanczos,format=yuv420p" \
    -an -c:v libx264 -crf 24 -preset medium -movflags +faststart \
    "$OUTPUT_DIR/quick-look-demo.mp4"
}

prepare_source
case "$MODE" in
  live)
    build_app
    capture_locale "en" "en"
    capture_locale "pt-BR" "pt-BR"
    ;;
  --from-screenshots)
    generate_fallback_locale "en" "Image copied"
    generate_fallback_locale "pt-BR" "Imagem copiada"
    generate_quick_look_fallback
    ;;
  *)
    echo "usage: $0 [live|--from-screenshots]" >&2
    exit 2
    ;;
esac
generate_social_card

echo "Documentation assets written to $OUTPUT_DIR."
