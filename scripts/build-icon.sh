#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Convert the approved raster artwork without redrawing or changing its design.
SOURCE="assets/branding/focus-on-icon-peek-v6.png"
ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/FocusOn.iconset"
mkdir -p "$ICONSET" build

for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICON_WORK/FocusOn.icns"
mv -f "$ICON_WORK/FocusOn.icns" build/FocusOn.icns
