#!/usr/bin/env bash
# Build a distributable OpenrowDB.app from SwiftPM (no Xcode project required).
#
# Usage:
#   ./scripts/make-app.sh [debug|release]
#
# Environment (optional):
#   VERSION=0.1.0          CFBundleShortVersionString
#   BUILD_NUMBER=1         CFBundleVersion
#   BUNDLE_ID=com.openrowdb.mac
#   SIGN_IDENTITY=-        ad-hoc (default). Set to "Developer ID Application: …" to sign.
#
# Output: apps/mac/build/<config>/OpenrowDB.app
set -euo pipefail

CONFIG="${1:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.openrowdb.mac}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$MAC_DIR/build/$CONFIG"
APP="$BUILD_DIR/OpenrowDB.app"
RESOURCES="$MAC_DIR/OpenrowDB/Resources"
ENTITLEMENTS="$RESOURCES/OpenrowDB.entitlements"
ICNS="$MAC_DIR/Resources/AppIcon.icns"

cd "$MAC_DIR"

echo "==> Building OpenrowDB ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OpenrowDB"

echo "==> Packaging ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenrowDB"
chmod +x "$APP/Contents/MacOS/OpenrowDB"

if [[ -f "$ICNS" ]]; then
  cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "WARN: $ICNS not found — app will use the default icon."
fi

cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable OpenrowDB" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"

echo "==> Signing (${SIGN_IDENTITY})…"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP" >/dev/null
else
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/OpenrowDB"
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "==> OK: $(du -sh "$APP" | awk '{print $1}') bundle at $APP"