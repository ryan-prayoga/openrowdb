#!/usr/bin/env bash
# Install OpenrowDB on macOS without Homebrew or Apple Developer ID.
#
# One-liner:
#   curl -fsSL https://openrowdb.ryanprayoga.dev/install.sh | bash
#
# Options (env):
#   OPENROWDB_VERSION=0.1.0     Pin a release (default: latest)
#   OPENROWDB_INSTALL_DIR=...   Target dir (default: /Applications, falls back to ~/Applications)
#   OPENROWDB_NO_OPEN=1       Skip launching the app after install
set -euo pipefail

APP_NAME="OpenrowDB"
BUNDLE="${APP_NAME}.app"
REPO="ryan-prayoga/openrowdb"
VERSION="${OPENROWDB_VERSION:-latest}"
INSTALL_ROOT="${OPENROWDB_INSTALL_DIR:-/Applications}"
MIRROR_BASE="${OPENROWDB_MIRROR_URL:-https://openrowdb.ryanprayoga.dev}"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "OpenrowDB is macOS only."
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "${major}" -lt 26 ]]; then
  die "OpenrowDB requires macOS 26 (Tahoe) or later. You have $(sw_vers -productVersion)."
fi

resolve_version() {
  if [[ "$VERSION" != "latest" ]]; then
    echo "$VERSION"
    return
  fi
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$tag" ]] || die "Could not resolve latest release from GitHub."
  echo "$tag"
}

pick_install_dir() {
  if [[ -w "$INSTALL_ROOT" ]]; then
    echo "$INSTALL_ROOT"
    return
  fi
  if [[ "$INSTALL_ROOT" == "/Applications" ]]; then
    local user_apps="${HOME}/Applications"
    mkdir -p "$user_apps"
    echo "$user_apps"
    return
  fi
  die "Install directory is not writable: $INSTALL_ROOT"
}

download_asset() {
  local ver="$1"
  local dest="$2"
  local api="https://api.github.com/repos/${REPO}/releases/tags/v${ver}"
  local url

  for suffix in zip dmg; do
    url="$(curl -fsSL "$api" 2>/dev/null | grep -o "https://[^\"]*OpenrowDB-${ver}.${suffix}" | head -1 || true)"
    if [[ -n "$url" ]]; then
      info "Downloading OpenrowDB-${ver}.${suffix} from GitHub…"
      curl -fL --progress-bar "$url" -o "${dest}.${suffix}"
      echo "${dest}.${suffix}"
      return 0
    fi
  done

  for name in "OpenrowDB-${ver}.zip" "OpenrowDB-${ver}.dmg" "OpenrowDB.zip"; do
    local mirror="${MIRROR_BASE}/releases/${name}"
    if curl -fsI "$mirror" 2>/dev/null | head -1 | grep -q '200'; then
      info "Downloading ${name} from mirror…"
      local out="${dest}${name##*.}"
      out="${dest}.${name##*.}"
      curl -fL --progress-bar "$mirror" -o "$out"
      echo "$out"
      return 0
    fi
  done

  die "No release artifact found for v${ver}. Check https://github.com/${REPO}/releases"
}

install_from_zip() {
  local zip="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  ditto -x -k "$zip" "$tmp"
  [[ -d "${tmp}/${BUNDLE}" ]] || die "Archive missing ${BUNDLE}"
  rm -rf "${dest_dir}/${BUNDLE}"
  ditto "${tmp}/${BUNDLE}" "${dest_dir}/${BUNDLE}"
}

install_from_dmg() {
  local dmg="$1"
  local mount_dir
  mount_dir="$(hdiutil attach -nobrowse -quiet "$dmg" | awk '/\/Volumes\// {print $3; exit}')"
  [[ -n "$mount_dir" && -d "${mount_dir}/${BUNDLE}" ]] || die "Could not mount DMG or find ${BUNDLE}"
  rm -rf "${dest_dir}/${BUNDLE}"
  ditto "${mount_dir}/${BUNDLE}" "${dest_dir}/${BUNDLE}"
  hdiutil detach "$mount_dir" -quiet || true
}

VERSION="$(resolve_version)"
info "Installing OpenrowDB v${VERSION}…"

dest_dir="$(pick_install_dir)"
if [[ "$dest_dir" != "/Applications" ]]; then
  info "Using ${dest_dir} (no write access to /Applications)."
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
artifact="${work}/artifact"
downloaded="$(download_asset "$VERSION" "$artifact")"

case "$downloaded" in
  *.zip) install_from_zip "$downloaded" ;;
  *.dmg) install_from_dmg "$downloaded" ;;
  *) die "Unsupported artifact: $downloaded" ;;
esac

TARGET="${dest_dir}/${BUNDLE}"
xattr -cr "$TARGET" 2>/dev/null || true

info "Installed to ${TARGET}"
info "Removed quarantine attributes (unsigned build)."

if [[ "${OPENROWDB_NO_OPEN:-}" != "1" ]]; then
  info "Launching OpenrowDB…"
  open "$TARGET"
fi

echo ""
echo "Done. OpenrowDB v${VERSION} is ready."