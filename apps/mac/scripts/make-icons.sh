#!/usr/bin/env bash
# Generate all AppIcon sizes from a 1024x1024 master PNG.
# Usage: ./scripts/make-icons.sh
# Requires: swift (to render the master), sips (built-in on macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPICONSET="$SCRIPT_DIR/../OpenrowDB/Resources/Assets.xcassets/AppIcon.appiconset"
MASTER="$APPICONSET/icon_1024.png"

echo "==> Rendering master icon (1024x1024)…"
swift "$SCRIPT_DIR/make-icon.swift" "$MASTER"

echo "==> Resizing to all required sizes…"
for size in 16 32 64 128 256 512; do
  out="$APPICONSET/icon_${size}.png"
  sips -z "$size" "$size" "$MASTER" --out "$out" > /dev/null
  echo "    icon_${size}.png"
done

# The 1024 master is already in place as icon_1024.png.
echo "==> Done. Icons written to:"
echo "    $APPICONSET"
