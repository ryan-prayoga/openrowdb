#!/usr/bin/env bash
# Build a distributable DMG for OpenrowDB.
#
# Usage:
#   ./scripts/make-dmg.sh [VERSION]         # defaults to 0.1.0
#
# Pre-requisites:
#   brew install create-dmg
#   A built .app at build/release/OpenrowDB.app
#   (run ./scripts/make-app.sh release first, or let this script build it)
#
# Notarization (optional, after DMG):
#   NOTARIZE=1 ./scripts/release.sh 0.1.0
#   # or: ./scripts/notarize.sh dist/OpenrowDB-0.1.0.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
VERSION="${1:-0.1.0}"
APP_NAME="OpenrowDB"
BUILD_DIR="$MAC_DIR/build/release"
DIST_DIR="$MAC_DIR/dist"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
VOLICON="$MAC_DIR/OpenrowDB/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png"

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> No .app found — building via make-app.sh…"
  VERSION="$VERSION" "$SCRIPT_DIR/make-app.sh" release
fi

if ! command -v create-dmg &>/dev/null; then
  echo "ERROR: create-dmg not found. Install: brew install create-dmg"
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

ICON_ARGS=()
if [[ -f "$VOLICON" ]]; then
  ICON_ARGS=(--volicon "$VOLICON")
fi

echo "==> Creating DMG for ${APP_NAME} ${VERSION}…"
create-dmg \
    --volname "${APP_NAME} ${VERSION}" \
    "${ICON_ARGS[@]}" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 165 175 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 495 175 \
    "$DMG_PATH" \
    "$BUILD_DIR/"

echo "==> DMG written to: $DMG_PATH"
if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  echo "Next: NOTARIZE=1 ./scripts/release.sh ${VERSION}"
else
  echo ""
  echo "Unsigned build. Users must clear quarantine after download:"
  echo "  xattr -d com.apple.quarantine /Applications/OpenrowDB.app"
fi