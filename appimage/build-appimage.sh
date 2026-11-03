#!/usr/bin/env bash
# Build an AppImage locally from the vendor's official .deb.
#
# Usage: appimage/build-appimage.sh [--app APP] [x86_64|aarch64] [--out DIR] [--deb FILE]
#   APP: claude-desktop (default) or chatgpt (Codex)
#
# The .deb is downloaded from the vendor's apt repository and checked against
# the SHA256 pinned in upstream/<app>.env (itself taken from the vendor's
# signed apt index). Nothing from Anthropic or OpenAI is stored in or
# distributed by this repo.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../scripts/apps.sh
. "$here/scripts/apps.sh"

app=claude-desktop
arch=$(uname -m)
out="$PWD"
deb=""
while (( $# )); do
  case "$1" in
    --app) app=$2; shift ;;
    --app=*) app=${1#*=} ;;
    x86_64|aarch64) arch=$1 ;;
    --out) out=$2; shift ;;
    --deb) deb=$2; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
app_load "$app"
# shellcheck disable=SC1090
. "$here/upstream/$APP.env"

# Per-app AppDir layout:
#   exe      main binary          desktop  .desktop file in usr/share/applications
#   icon     icon to put at root  label    AppImage file name prefix
case "$APP" in
  claude-desktop)
    exe=usr/lib/claude-desktop/claude-desktop
    desktop=com.anthropic.Claude.desktop
    icon=usr/share/icons/hicolor/256x256/apps/claude-desktop.png
    label=Claude ;;
  chatgpt)
    exe=usr/lib/chatgpt/ChatGPT
    desktop=chatgpt.desktop
    icon=usr/share/pixmaps/chatgpt.png
    label=ChatGPT ;;
esac

case "$arch" in
  x86_64)  url=$DEB_AMD64_URL; sha=$DEB_AMD64_SHA256 ;;
  aarch64) url=$DEB_ARM64_URL; sha=$DEB_ARM64_SHA256 ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

need() { command -v "$1" >/dev/null || { echo "missing required tool: $1 ($2)" >&2; exit 1; }; }
need curl curl
need sha256sum coreutils
need tar tar
if ! command -v bsdtar >/dev/null; then need ar "binutils (or install libarchive for bsdtar)"; fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-codex-desktop-linux"
mkdir -p "$cache" "$out"
# Work on disk next to the cache: unpacked apps are large (Codex: ~1.7 GB)
# and /tmp is often a small RAM disk.
work=$(mktemp -d "$cache/appimage.XXXXXX")
trap 'rm -rf "$work"' EXIT

# 1. Get the official .deb and verify it
if [[ -z "$deb" ]]; then
  deb="$cache/$(basename "$url")"
  if [[ ! -f "$deb" ]] || ! echo "$sha  $deb" | sha256sum -c --quiet - 2>/dev/null; then
    echo ">> downloading $url"
    curl -fL --retry 3 -C - -o "$deb.part" "$url"
    mv "$deb.part" "$deb"
  fi
fi
echo "$sha  $deb" | sha256sum -c --quiet - || { echo "SHA256 mismatch for $deb" >&2; exit 1; }

# 2. Unpack usr/ from the .deb's data.tar.* (the .deb is an ar archive)
appdir="$work/$label.AppDir"
mkdir -p "$appdir" "$work/deb"
if command -v bsdtar >/dev/null; then
  bsdtar -xf "$deb" -C "$work/deb"
else
  (cd "$work/deb" && ar x "$deb")
fi
tar -xf "$work"/deb/data.tar.* -C "$appdir" ./usr
rm -rf "$work/deb"

# 3. AppDir layout: AppRun, desktop file and icon at the root
sed -e "s#@EXEC@#$exe#" -e "s#@NAME@#$APP#" "$here/appimage/AppRun" > "$appdir/AppRun"
chmod 755 "$appdir/AppRun"
# Inside an AppImage a sandbox helper can't be setuid; leave it unprivileged.
[[ -e "$appdir/usr/lib/$APP/chrome-sandbox" ]] && chmod 0755 "$appdir/usr/lib/$APP/chrome-sandbox"
sed -E -e 's/^Exec=[^ ]+/Exec=AppRun/' \
    -e '/^#/d' \
    "$appdir/usr/share/applications/$desktop" \
    > "$appdir/$desktop"
echo "X-AppImage-Version=$VERSION" >> "$appdir/$desktop"
iconname=$(sed -n 's/^Icon=//p' "$appdir/$desktop")
cp "$appdir/$icon" "$appdir/$iconname.png"
ln -s "$iconname.png" "$appdir/.DirIcon"
rm -rf "$appdir/usr/share/lintian" "$appdir/usr/share/doc"

# 4. appimagetool (use one from PATH, else fetch the official build)
tool=$(command -v appimagetool || true)
if [[ -z "$tool" ]]; then
  tool="$cache/appimagetool-$(uname -m).AppImage"
  if [[ ! -x "$tool" ]]; then
    echo ">> downloading appimagetool"
    curl -fL --retry 3 -o "$tool" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage"
    chmod +x "$tool"
  fi
fi

target="$out/$label-$VERSION-$arch.AppImage"
echo ">> building $target"
run=("$tool")
# An appimagetool that is itself an AppImage must not need FUSE (containers, CI)
[[ "$tool" == *.AppImage ]] && run+=(--appimage-extract-and-run)
ARCH=$arch "${run[@]}" --no-appstream "$appdir" "$target"
echo ">> done: $target"
