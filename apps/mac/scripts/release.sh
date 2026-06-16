#!/usr/bin/env bash
# One-shot release build: .app → .dmg → optional notarize.
#
# Usage:
#   ./scripts/release.sh [VERSION]          # default 0.1.0
#   NOTARIZE=1 ./scripts/release.sh 0.1.0   # also notarize (needs Apple creds)
#
# Signed release (Developer ID):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#     ./scripts/release.sh 0.1.0
set -euo pipefail

VERSION="${1:-0.1.0}"
export VERSION

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/make-app.sh" release
"$SCRIPT_DIR/make-zip.sh" "$VERSION"
"$SCRIPT_DIR/make-dmg.sh" "$VERSION"

DMG="$SCRIPT_DIR/../dist/OpenrowDB-${VERSION}.dmg"
if [[ "${NOTARIZE:-}" == "1" ]]; then
  "$SCRIPT_DIR/notarize.sh" "$DMG"
fi

echo ""
echo "Release artifacts:"
echo "  App: $SCRIPT_DIR/../build/release/OpenrowDB.app"
echo "  DMG: $DMG"
echo ""
echo "Upload to GitHub Releases:"
echo "  gh release create v${VERSION} \"$DMG\" --title \"v${VERSION}\" --notes-file CHANGELOG.md"