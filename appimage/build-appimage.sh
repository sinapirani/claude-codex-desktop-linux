#!/usr/bin/env bash
# Build a Claude Desktop AppImage locally from Anthropic's official .deb.
#
# Usage: appimage/build-appimage.sh [x86_64|aarch64] [--out DIR] [--deb FILE]
#
# The .deb is downloaded from downloads.claude.ai and checked against the
# SHA256 pinned in upstream.env (itself taken from Anthropic's signed apt
# index). Nothing from Anthropic is stored in or distributed by this repo.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../upstream.env
. "$here/upstream.env"

arch=$(uname -m)
out="$PWD"
deb=""
while (( $# )); do
  case "$1" in
    x86_64|aarch64) arch=$1 ;;
    --out) out=$2; shift ;;
    --deb) deb=$2; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

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

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-linux"
mkdir -p "$cache" "$out"
work=$(mktemp -d)
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

# 2. Unpack data.tar.* from the .deb (an ar archive)
appdir="$work/Claude.AppDir"
mkdir -p "$appdir" "$work/deb"
if command -v bsdtar >/dev/null; then
  bsdtar -xf "$deb" -C "$work/deb"
else
  (cd "$work/deb" && ar x "$deb")
fi
tar -xf "$work"/deb/data.tar.* -C "$appdir"

# 3. AppDir layout: AppRun, desktop file and icon at the root
install -m755 "$here/appimage/AppRun" "$appdir/AppRun"
# Inside an AppImage the sandbox helper can't be setuid; leave it unprivileged.
chmod 0755 "$appdir/usr/lib/claude-desktop/chrome-sandbox"
sed -e 's/^Exec=claude-desktop /Exec=AppRun /' \
    -e '/^#/d' \
    "$appdir/usr/share/applications/com.anthropic.Claude.desktop" \
    > "$appdir/com.anthropic.Claude.desktop"
echo "X-AppImage-Version=$VERSION" >> "$appdir/com.anthropic.Claude.desktop"
cp "$appdir/usr/share/icons/hicolor/256x256/apps/claude-desktop.png" "$appdir/claude-desktop.png"
ln -s claude-desktop.png "$appdir/.DirIcon"
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

target="$out/Claude-$VERSION-$arch.AppImage"
echo ">> building $target"
run=("$tool")
# An appimagetool that is itself an AppImage must not need FUSE (containers, CI)
[[ "$tool" == *.AppImage ]] && run+=(--appimage-extract-and-run)
ARCH=$arch "${run[@]}" --no-appstream "$appdir" "$target"
echo ">> done: $target"
