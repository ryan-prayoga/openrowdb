#!/usr/bin/env bash
# Dev launcher: build the SwiftPM executable, wrap it in a minimal .app bundle,
# ad-hoc codesign it, and launch via Launch Services.
#
# Why the bundle? A bare `swift run` executable launches as an accessory process:
# it can't become key (no keyboard input), shows no Dock icon, and animations
# drop frames because it isn't fully registered with the window server. Wrapping
# it in a bundle and launching with `open` fixes all of that.
#
# The shippable, signed/notarized bundle is a Phase 5 Xcode concern; this is a
# throwaway dev convenience.
#
# Usage: scripts/run.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${TMPDIR:-/tmp}/OpenrowDB.app"

cd "$MAC_DIR"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/OpenrowDB"

echo "▸ Packaging bundle at $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/OpenrowDB"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>OpenrowDB</string>
  <key>CFBundleIdentifier</key><string>com.openrowdb.app</string>
  <key>CFBundleName</key><string>OpenrowDB</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null

echo "▸ Launching…"
pkill -f "OpenrowDB.app/Contents/MacOS" 2>/dev/null || true
open "$APP"
echo "✓ OpenrowDB launched."
