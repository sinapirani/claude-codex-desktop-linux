#!/usr/bin/env bash
# Regenerate gentoo/app-misc/claude-desktop/Manifest for the release in
# upstream.env. Downloads (or reuses cached) .debs, verifies their SHA256
# against upstream.env, then records size + BLAKE2B + SHA512 like
# `ebuild ... manifest` would.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./upstream.env

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-linux"
mkdir -p "$cache"
manifest=gentoo/app-misc/claude-desktop/Manifest
: >"$manifest.new"

# MANIFEST_ARCHES="AMD64" limits the run to one architecture (local testing)
for a in ${MANIFEST_ARCHES:-AMD64 ARM64}; do
  url_var="DEB_${a}_URL"; sha_var="DEB_${a}_SHA256"
  url=${!url_var}; sha=${!sha_var}
  name=$(basename "$url")             # claude-desktop_<ver>_<arch>.deb
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
