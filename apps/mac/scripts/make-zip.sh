#!/usr/bin/env bash
# Zip OpenrowDB.app for curl-based installs (no DMG mount required).
#
# Usage: ./scripts/make-zip.sh [VERSION]
set -euo pipefail

VERSION="${1:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
APP="$MAC_DIR/build/release/OpenrowDB.app"
DIST="$MAC_DIR/dist/OpenrowDB-${VERSION}.zip"

if [[ ! -d "$APP" ]]; then
  VERSION="$VERSION" "$SCRIPT_DIR/make-app.sh" release
fi

mkdir -p "$(dirname "$DIST")"
rm -f "$DIST"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST"
echo "==> ZIP: $DIST ($(du -sh "$DIST" | awk '{print $1}'))"