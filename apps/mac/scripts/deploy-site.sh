#!/usr/bin/env bash
# Build the Vite landing site (web/) and deploy it + install.sh to
# openrowdb.ryanprayoga.dev (VPS + Caddy).
#
# Usage:
#   ./scripts/deploy-site.sh
#   ./scripts/deploy-site.sh --skip-build               # deploy existing web/dist
#   ./scripts/deploy-site.sh --with-release 0.1.0       # also upload zip to mirror
#
# Requires SSH host: sshvpscf (Cloudflare tunnel)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$SCRIPT_DIR/.."
REPO_ROOT="$(cd "$MAC_DIR/../.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
SITE_DIR="$WEB_DIR/dist"
REMOTE="sshvpscf"
WEB_ROOT="/var/www/openrowdb.ryanprayoga.dev"
CADDY_SITE="/etc/caddy/sites/openrowdb.caddy"
WITH_RELEASE=""
SKIP_BUILD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-release) WITH_RELEASE="${2:?version required}"; shift 2 ;;
    --skip-build) SKIP_BUILD="1"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

info() { echo "==> $*"; }

if [[ -z "$SKIP_BUILD" ]]; then
  info "Building web/ (Vite + Tailwind + ReactBits)…"
  ( cd "$WEB_DIR" && npm ci && npm run build )
fi
[[ -f "$SITE_DIR/index.html" ]] || { echo "No build at $SITE_DIR — drop --skip-build"; exit 1; }

info "Preparing remote directory…"
ssh "$REMOTE" "sudo mkdir -p '${WEB_ROOT}/releases' && sudo chown -R ubuntu:ubuntu '${WEB_ROOT}'"

info "Syncing site + install.sh…"
# --delete cleans stale assets, but never the /releases mirror or install.sh
# (install.sh is re-uploaded right after from the repo copy).
rsync -az --delete --exclude 'releases/' --exclude 'install.sh' "$SITE_DIR/" "$REMOTE:${WEB_ROOT}/"
rsync -az "$SCRIPT_DIR/install.sh" "$REMOTE:${WEB_ROOT}/install.sh"
ssh "$REMOTE" "mkdir -p '${WEB_ROOT}/releases' && chmod 755 '${WEB_ROOT}/install.sh'"

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