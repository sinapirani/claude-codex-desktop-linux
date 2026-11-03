#!/usr/bin/env bash
# Regenerate gentoo/app-misc/<app>/Manifest for the release in
# upstream/<app>.env. Downloads (or reuses cached) .debs, verifies their SHA256
# against upstream/<app>.env, then records size + BLAKE2B + SHA512 like
# `ebuild ... manifest` would.
#
# Usage: scripts/gentoo-manifest.sh APP      (claude-desktop | chatgpt)
#   MANIFEST_ARCHES="AMD64" limits the run to one architecture (local testing)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=apps.sh
. scripts/apps.sh
app_load "${1:-}" || { echo "usage: scripts/gentoo-manifest.sh APP" >&2; exit 1; }
# shellcheck disable=SC1090
. "upstream/$APP.env"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-linux"
mkdir -p "$cache"
manifest=gentoo/app-misc/$APP/Manifest
: >"$manifest.new"

for a in ${MANIFEST_ARCHES:-AMD64 ARM64}; do
  url_var="DEB_${a}_URL"; sha_var="DEB_${a}_SHA256"
  url=${!url_var}; sha=${!sha_var}
  name=$(basename "$url")             # <app>_<ver>_<arch>.deb
  f="$cache/$name"
  if [[ ! -f "$f" ]] || ! echo "$sha  $f" | sha256sum -c --quiet - 2>/dev/null; then
    echo ">> downloading $name" >&2
    curl -fL --retry 3 -C - -o "$f.part" "$url"
    mv "$f.part" "$f"
  fi
  echo "$sha  $f" | sha256sum -c --quiet - || { echo "SHA256 mismatch: $f" >&2; exit 1; }
  printf 'DIST %s %s BLAKE2B %s SHA512 %s\n' "$name" "$(stat -Lc %s "$f")" \
    "$(b2sum "$f" | cut -d' ' -f1)" "$(sha512sum "$f" | cut -d' ' -f1)" >>"$manifest.new"
done
sort "$manifest.new" >"$manifest"
rm -f "$manifest.new"
echo "wrote $manifest" >&2
