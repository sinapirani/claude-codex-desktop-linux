#!/usr/bin/env bash
# Update every recipe of one app to a new upstream release.
#
# Usage: scripts/bump.sh [--check] APP [VERSION]
#   APP        claude-desktop | chatgpt
#   (no VERSION) move to the newest release in the vendor's signed apt index
#   VERSION    move to that exact release
#   --check    only report: exit 0 if up to date, 10 if an update exists
#
# Downloads both .debs (cached in ~/.cache/claude-desktop-linux) because the
# Gentoo Manifest needs their SHA512/BLAKE2B, which the apt index doesn't list.
#
# In GitHub Actions it writes changed_<app>=true|false and version_<app>=X to
# $GITHUB_OUTPUT (<app> with '-' replaced by '_').
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=apps.sh
. scripts/apps.sh

check=0
if [[ "${1:-}" == "--check" ]]; then check=1; shift; fi
app_load "${1:-}" || { echo "usage: scripts/bump.sh [--check] APP [VERSION]" >&2; exit 1; }

env_file=upstream/$APP.env
old_env=$(cat "$env_file")
new_env=$(scripts/upstream.sh "$APP" "${2:-}")
get() { sed -n "s/^$2=//p" <<<"$1"; }

old_v=$(get "$old_env" VERSION)
new_v=$(get "$new_env" VERSION)
id=${APP//-/_}
gh_out() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1" >>"$GITHUB_OUTPUT" || true; }

if [[ "$old_v" == "$new_v" ]]; then
  echo "$APP up to date: $old_v"
  gh_out "changed_$id=false"
  exit 0
fi
echo "$APP update available: $old_v -> $new_v"
if (( check )); then exit 10; fi

recipes=(arch/$APP/PKGBUILD rpm/$APP.spec void/srcpkgs/$APP/template)

# Checksums: replace old with new wherever they appear
for a in AMD64 ARM64; do
  o=$(get "$old_env" "DEB_${a}_SHA256"); n=$(get "$new_env" "DEB_${a}_SHA256")
  sed -i "s/$o/$n/g" "${recipes[@]}"
done

# Version fields, and package release numbers back to 1
sed -i -E "s/^pkgver=.*/pkgver=$new_v/; s/^pkgrel=.*/pkgrel=1/" "arch/$APP/PKGBUILD"
sed -i -E "s/^(Version:[[:space:]]+).*/\1$new_v/; s/^(Release:[[:space:]]+)[0-9]+/\11/" "rpm/$APP.spec"
sed -i -E "s/^version=.*/version=$new_v/; s/^revision=.*/revision=1/" "void/srcpkgs/$APP/template"

ebuild_dir=gentoo/app-misc/$APP
old_ebuild=$(ls "$ebuild_dir/$APP"-*.ebuild)
git mv "$old_ebuild" "$ebuild_dir/$APP-$new_v.ebuild" 2>/dev/null \
  || mv "$old_ebuild" "$ebuild_dir/$APP-$new_v.ebuild"

printf '%s\n' "$new_env" > "$env_file"
scripts/gentoo-manifest.sh "$APP"

gh_out "changed_$id=true"
gh_out "old_version_$id=$old_v"
gh_out "version_$id=$new_v"
echo "bumped $APP to $new_v"
