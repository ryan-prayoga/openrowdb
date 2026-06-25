#!/usr/bin/env bash
# Watch .swift files for changes and auto-rebuild + relaunch OpenrowDB.
# Usage: scripts/watch.sh
set -euo pipefail

MAC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MAC_DIR"

echo "👀 Watching for .swift changes in apps/mac/..."
echo "   Press Ctrl+C to stop."
echo ""

fswatch -r -e ".*" -i "\\.swift$" \
  --exclude "\.build" \
  --exclude "dist" \
  Sources/ OpenrowDB/ \
| while read -r changed; do
    echo "📝 Changed: $(basename "$changed")"
    echo "🔨 Building..."
    if swift build -c release 2>&1 | tail -1; then
        BIN="$(swift build -c release --show-bin-path)/OpenrowDB"
        APP="${TMPDIR:-/tmp}/OpenrowDB.app"
        rm -rf "$APP"
        mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
        cp "$BIN" "$APP/Contents/MacOS/OpenrowDB"
        [ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
        cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>OpenrowDB</string>
  <key>CFBundleIdentifier</key><string>com.openrowdb.mac</string>
  <key>CFBundleName</key><string>OpenrowDB</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.7</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
        codesign --force --deep --sign - "$APP" >/dev/null 2>&1
        pkill -f "OpenrowDB.app/Contents/MacOS" 2>/dev/null || true
        sleep 0.3
        open "$APP"
        echo "✅ Relaunched!"
    else
        echo "❌ Build failed"
    fi
    echo ""
done
