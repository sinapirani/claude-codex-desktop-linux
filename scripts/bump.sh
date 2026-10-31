#!/usr/bin/env bash
# Update every recipe in this repo to a new upstream Claude Desktop release.
#
# Usage: scripts/bump.sh [--check] [VERSION]
#   (no args)  move to the newest release in Anthropic's signed apt index
#   VERSION    move to that exact release
#   --check    only report: exit 0 if up to date, 10 if an update exists
#
# Downloads both .debs (cached in ~/.cache/claude-desktop-linux) because the
# Gentoo Manifest needs their SHA512/BLAKE2B, which the apt index doesn't list.
set -euo pipefail
cd "$(dirname "$0")/.."

check=0
if [[ "${1:-}" == "--check" ]]; then check=1; shift; fi

old_env=$(cat upstream.env)
new_env=$(scripts/upstream.sh "${1:-}")
get() { sed -n "s/^$2=//p" <<<"$1"; }

old_v=$(get "$old_env" VERSION)
new_v=$(get "$new_env" VERSION)
gh_out() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1" >>"$GITHUB_OUTPUT" || true; }

if [[ "$old_v" == "$new_v" ]]; then
  echo "up to date: $old_v"
  gh_out "changed=false"
  exit 0
fi
echo "update available: $old_v -> $new_v"
if (( check )); then exit 10; fi

# Checksums: replace old with new wherever they appear
for a in AMD64 ARM64; do
  o=$(get "$old_env" "DEB_${a}_SHA256"); n=$(get "$new_env" "DEB_${a}_SHA256")
  sed -i "s/$o/$n/g" arch/PKGBUILD rpm/claude-desktop.spec void/srcpkgs/claude-desktop/template
done

# Version fields, and package release numbers back to 1
sed -i -E "s/^pkgver=.*/pkgver=$new_v/; s/^pkgrel=.*/pkgrel=1/" arch/PKGBUILD
sed -i -E "s/^(Version:[[:space:]]+).*/\1$new_v/; s/^(Release:[[:space:]]+)[0-9]+/\11/" rpm/claude-desktop.spec
sed -i -E "s/^version=.*/version=$new_v/; s/^revision=.*/revision=1/" void/srcpkgs/claude-desktop/template

ebuild_dir=gentoo/app-misc/claude-desktop
old_ebuild=$(ls "$ebuild_dir"/claude-desktop-*.ebuild)
git mv "$old_ebuild" "$ebuild_dir/claude-desktop-$new_v.ebuild" 2>/dev/null \
  || mv "$old_ebuild" "$ebuild_dir/claude-desktop-$new_v.ebuild"

printf '%s\n' "$new_env" > upstream.env
scripts/gentoo-manifest.sh

gh_out "changed=true"
gh_out "old_version=$old_v"
gh_out "version=$new_v"
echo "bumped to $new_v"
