#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from Resources/AppIcon.svg.
# Needs rsvg-convert (brew install librsvg). The .icns is committed, so normal
# builds do not need this tool.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/Resources/AppIcon.svg"
OUT="$ROOT/Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "Install librsvg: brew install librsvg" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sony-for-mac-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$SRC" -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) "$SRC" -o "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
