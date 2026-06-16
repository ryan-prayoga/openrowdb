#!/usr/bin/env bash
# Deploy landing page + install.sh to openrowdb.ryanprayoga.dev (VPS + Caddy).
#
# Usage:
#   ./scripts/deploy-site.sh
#   ./scripts/deploy-site.sh --with-release 0.1.0   # also upload zip to mirror
#
# Requires SSH host: sshvpscf (Cloudflare tunnel)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
SITE_DIR="$MAC_DIR/site"
REMOTE="sshvpscf"
WEB_ROOT="/var/www/openrowdb.ryanprayoga.dev"
CADDY_SITE="/etc/caddy/sites/openrowdb.caddy"
WITH_RELEASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-release) WITH_RELEASE="${2:?version required}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

info() { echo "==> $*"; }

info "Preparing remote directory…"
ssh "$REMOTE" "sudo mkdir -p '${WEB_ROOT}/releases' && sudo chown -R ubuntu:ubuntu '${WEB_ROOT}'"

info "Syncing site + install.sh…"
rsync -az --delete "$SITE_DIR/" "$REMOTE:${WEB_ROOT}/"
rsync -az "$SCRIPT_DIR/install.sh" "$REMOTE:${WEB_ROOT}/install.sh"
ssh "$REMOTE" "chmod 755 '${WEB_ROOT}/install.sh'"

if [[ -n "$WITH_RELEASE" ]]; then
  ZIP="$MAC_DIR/dist/OpenrowDB-${WITH_RELEASE}.zip"
  if [[ ! -f "$ZIP" ]]; then
    "$SCRIPT_DIR/make-zip.sh" "$WITH_RELEASE"
  fi
  info "Uploading release mirror ${ZIP}…"
  rsync -az "$ZIP" "$REMOTE:${WEB_ROOT}/releases/OpenrowDB-${WITH_RELEASE}.zip"
  rsync -az "$ZIP" "$REMOTE:${WEB_ROOT}/releases/OpenrowDB.zip"
fi

info "Installing Caddy site config…"
ssh "$REMOTE" "sudo tee '${CADDY_SITE}' > /dev/null" <<'CADDY'
openrowdb.ryanprayoga.dev {
	import common_headers
	import error_pages
	root * /var/www/openrowdb.ryanprayoga.dev
	@installer path /install.sh
	handle @installer {
		header Content-Type "text/plain; charset=utf-8"
		file_server
	}
	file_server
}
CADDY

ssh "$REMOTE" "sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy"
info "Deployed: https://openrowdb.ryanprayoga.dev"