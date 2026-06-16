#!/usr/bin/env bash
# Notarize and staple a DMG (or .app zip) for Gatekeeper.
#
# Usage:
#   ./scripts/notarize.sh path/to/OpenrowDB-0.1.0.dmg
#
# Requires env:
#   APPLE_ID       Apple ID email
#   TEAM_ID        10-char Team ID
#   NOTARY_PASSWORD  app-specific password, OR
#   NOTARY_KEYCHAIN_PROFILE  notarytool keychain profile name (preferred)
#
# Example setup:
#   xcrun notarytool store-credentials "openrowdb-notary" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD"
#   export NOTARY_KEYCHAIN_PROFILE=openrowdb-notary
set -euo pipefail

ARTIFACT="${1:?Usage: notarize.sh <dmg-or-zip>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$ARTIFACT" ]]; then
  echo "ERROR: not found: $ARTIFACT"
  exit 1
fi

SUBMIT_ARGS=(submit "$ARTIFACT" --wait)
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  SUBMIT_ARGS+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
  : "${APPLE_ID:?Set APPLE_ID}"
  : "${TEAM_ID:?Set TEAM_ID}"
  : "${NOTARY_PASSWORD:?Set NOTARY_PASSWORD or NOTARY_KEYCHAIN_PROFILE}"
  SUBMIT_ARGS+=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD")
fi

echo "==> Submitting for notarization: $ARTIFACT"
xcrun notarytool "${SUBMIT_ARGS[@]}"

echo "==> Stapling ticket…"
xcrun stapler staple "$ARTIFACT"

echo "==> Verifying Gatekeeper acceptance…"
spctl -a -vv -t install "$ARTIFACT" || true
echo "==> Done."