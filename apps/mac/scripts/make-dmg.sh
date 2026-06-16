#!/usr/bin/env bash
# Build a distributable DMG for OpenrowDB.
#
# Usage:
#   ./scripts/make-dmg.sh [VERSION]         # defaults to 0.1.0
#
# Pre-requisites:
#   brew install create-dmg
#   A built + codesigned .app at build/Release/OpenrowDB.app
#   (build via Xcode: Product → Archive, or xcodebuild -scheme OpenrowDB)
#
# The entitlements file + hardened runtime flag is set in Xcode signing settings.
# Notarization is a separate step after DMG creation:
#   xcrun notarytool submit dist/OpenrowDB-$VERSION.dmg \
#       --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --wait

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
VERSION="${1:-0.1.0}"
APP_NAME="OpenrowDB"
BUILD_DIR="$MAC_DIR/build/Release"
DIST_DIR="$MAC_DIR/dist"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: $APP_PATH not found."
    echo "Build the app first: open Package.swift in Xcode → Product → Archive → Distribute App"
    exit 1
fi

if ! command -v create-dmg &>/dev/null; then
    echo "ERROR: create-dmg not found. Install: brew install create-dmg"
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating DMG for ${APP_NAME} ${VERSION}…"
create-dmg \
    --volname "${APP_NAME} ${VERSION}" \
    --volicon "$SCRIPT_DIR/../OpenrowDB/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 165 175 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 495 175 \
    "$DMG_PATH" \
    "$BUILD_DIR/"

echo "==> DMG written to: $DMG_PATH"
echo ""
echo "Next steps:"
echo "  1. Notarize: xcrun notarytool submit \"$DMG_PATH\" --apple-id ... --team-id ... --wait"
echo "  2. Staple:   xcrun stapler staple \"$DMG_PATH\""
echo "  3. Upload to GitHub Release as an asset."
