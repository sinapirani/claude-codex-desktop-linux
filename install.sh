#!/usr/bin/env bash
# Install Claude Desktop on (almost) any Linux distro.
#
#   curl -fsSL https://raw.githubusercontent.com/sinapirani/claude-desktop-linux/main/install.sh | bash
#
# Detects your distro and uses the best method:
#   Arch family      -> builds arch/PKGBUILD, installs with pacman
#   Fedora / RHEL    -> builds rpm/claude-desktop.spec, installs with dnf
#   openSUSE         -> builds rpm/claude-desktop.spec, installs with zypper
#   Gentoo           -> adds the overlay, emerges app-misc/claude-desktop
#   Void (glibc)     -> builds void/ template with xbps-src, installs with xbps
#   Debian / Ubuntu  -> installs Anthropic's official .deb (it adds Anthropic's
#                       apt repo, so updates come through apt)
#   anything else    -> builds an AppImage and adds it to your app menu
#
# Options:
#   --method M    force a method: arch | rpm | gentoo | void | deb | appimage
#   --cowork      also install QEMU + UEFI firmware for Cowork (local VM)
#   --uninstall   remove Claude Desktop installed by this script
#   --dry-run     show what would happen, change nothing
#   -y, --yes     don't ask for confirmation
#   -h, --help    show this help
#
# Re-run the script to update (the Debian method updates through apt).
set -euo pipefail

REPO="sinapirani/claude-desktop-linux"
TARBALL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-linux"

method="" cowork=0 uninstall=0 dry=0 yes=0
usage() {
  cat <<'EOF_USAGE'
Install Claude Desktop on (almost) any Linux distro.

  curl -fsSL https://raw.githubusercontent.com/sinapirani/claude-desktop-linux/main/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- --cowork      (pass options like this)

Options:
  --method M    force a method: arch | rpm | gentoo | void | deb | appimage
  --cowork      also install QEMU + UEFI firmware for Cowork (local VM)
  --uninstall   remove Claude Desktop installed by this script
  --dry-run     show what would happen, change nothing
  -y, --yes     don't ask for confirmation
  -h, --help    show this help
EOF_USAGE
}
while (( $# )); do
  case "$1" in
    --method) method=${2:-}; shift ;;
    --method=*) method=${1#*=} ;;
    --cowork) cowork=1 ;;
    --uninstall) uninstall=1 ;;
    --dry-run) dry=1 ;;
    -y|--yes) yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

# ---------- output helpers -------------------------------------------------
if [[ -t 1 ]]; then b=$'\e[1m' g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' n=$'\e[0m'; else b= g= y= r= n=; fi
say()  { echo "${b}==>${n} $*"; }
warn() { echo "${y}warning:${n} $*" >&2; }
die()  { echo "${r}error:${n} $*" >&2; exit 1; }
run()  { echo "  ${g}\$${n} $*"; (( dry )) || "$@"; }
in_dir() { local d=$1; shift; echo "  ${g}\$${n} (cd $d && $*)"; (( dry )) || (cd "$d" && "$@"); }

# Root helper for privileged steps (not used when already root)
SUDO=""
if (( EUID != 0 )); then
  if command -v sudo >/dev/null; then SUDO=sudo
  elif command -v doas >/dev/null; then SUDO=doas; fi
fi
root() {
  if (( EUID != 0 )) && [[ -z $SUDO ]]; then die "need root for: $* (install sudo or run as root)"; fi
  # shellcheck disable=SC2086
  run $SUDO "$@"
}
as_root_tee() {  # as_root_tee [-a] FILE  (stdin -> FILE as root)
  # shellcheck disable=SC2086
  $SUDO tee "$@" >/dev/null
}

# ---------- system checks ---------------------------------------------------
[[ "$(uname -s)" == Linux ]] || die "this installer is for Linux"
case "$(uname -m)" in
  x86_64)  ARCH=x86_64  DEBARCH=amd64 ;;
  aarch64|arm64) ARCH=aarch64 DEBARCH=arm64 ;;
  *) die "unsupported CPU architecture $(uname -m): Anthropic publishes only x86_64 and aarch64 builds" ;;
esac

[[ -r /etc/os-release ]] && . /etc/os-release
ID=${ID:-unknown}; ID_LIKE=${ID_LIKE:-}
ids=" $ID $ID_LIKE "

glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)
if [[ -z "$glibc" ]]; then
  die "no glibc found (musl-based distros like Alpine or Void-musl can't run the official build)"
fi
if [[ "$(printf '%s\n' 2.34 "$glibc" | sort -V | head -n1)" != 2.34 ]]; then
  die "glibc $glibc is too old; Claude Desktop needs 2.34 or newer"
fi

detect_method() {
  if [[ -e /run/ostree-booted ]]; then echo appimage; return; fi   # Silverblue, Bazzite, ...
  case "$ids" in
    *" nixos "*) die "NixOS isn't supported (the app expects a standard filesystem layout)" ;;
    *" arch "*|*" archarm "*|*" manjaro "*|*" endeavouros "*|*" cachyos "*|*" garuda "*|*" artix "*) echo arch ;;
    *" fedora "*|*" rhel "*|*" centos "*) echo rpm ;;
    *" suse "*|*" opensuse "*|*opensuse-*) echo rpm ;;
    *" gentoo "*) echo gentoo ;;
    *" void "*) echo void ;;
    *" debian "*|*" ubuntu "*) echo deb ;;
    *)
      if   command -v pacman >/dev/null; then echo arch
      elif command -v dnf >/dev/null || command -v zypper >/dev/null; then echo rpm
      elif command -v emerge >/dev/null; then echo gentoo
      elif command -v xbps-install >/dev/null; then echo void
      elif command -v apt-get >/dev/null; then echo deb
      else echo appimage; fi ;;
  esac
}
[[ -n "$method" ]] || method=$(detect_method)
case "$method" in arch|rpm|gentoo|void|deb|appimage) ;; *) die "unknown method: $method" ;; esac

# rpm flavour
pm=""
if [[ $method == rpm ]]; then
  if command -v zypper >/dev/null; then pm=zypper
  elif command -v dnf >/dev/null; then pm=dnf
  else die "rpm method needs dnf or zypper"; fi
fi

# ---------- plan + confirmation --------------------------------------------
action=$([[ $uninstall == 1 ]] && echo "Uninstall" || echo "Install")
say "$action Claude Desktop"
echo "  distro:  ${PRETTY_NAME:-$ID} ($ARCH, glibc $glibc)"
echo "  method:  $method${pm:+ ($pm)}"
(( cowork )) && echo "  extras:  Cowork (QEMU + UEFI firmware)"
if (( ! yes && ! dry )); then
  if [[ -r /dev/tty ]]; then
    read -r -p "Continue? [Y/n] " ans </dev/tty || ans=n
    [[ -z "$ans" || "$ans" == [Yy]* ]] || { echo "aborted"; exit 1; }
  else
    die "no terminal to confirm on; re-run with --yes"
  fi
fi

# ---------- uninstall --------------------------------------------------------
appimage_path="$HOME/.local/share/claude-desktop/Claude.AppImage"
desktop_user="$HOME/.local/share/applications/com.anthropic.Claude.desktop"
if (( uninstall )); then
  case "$method" in
    arch)   root pacman -R --noconfirm claude-desktop ;;
    rpm)    if [[ $pm == zypper ]]; then root zypper -n remove claude-desktop; else root dnf -y remove claude-desktop; fi ;;
    gentoo) root emerge --ask=n --depclean app-misc/claude-desktop || root emerge --ask=n -C app-misc/claude-desktop ;;
    void)   root xbps-remove -y claude-desktop ;;
    deb)    root apt-get remove -y claude-desktop ;;
    appimage)
      run rm -f "$appimage_path" "$desktop_user"
      run rm -f "$HOME"/.local/share/icons/hicolor/*/apps/claude-desktop.png ;;
  esac
  say "done"
  exit 0
fi

# ---------- get the recipes ---------------------------------------------------
here=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ -n "$here" && -f "$here/upstream.env" && -d "$here/arch" ]]; then
  src="$here"
else
  say "Downloading recipes from github.com/$REPO"
  command -v curl >/dev/null || die "curl is required"
  curl -fsSL "$TARBALL" | tar -xz -C "$work"
  src=$(echo "$work"/claude-desktop-linux-*)
fi
# shellcheck disable=SC1091
. "$src/upstream.env"
say "Claude Desktop $VERSION"

# Download the official .deb and check it against Anthropic's signed index hash
fetch_deb() {
  local url_var="DEB_${DEBARCH^^}_URL" sha_var="DEB_${DEBARCH^^}_SHA256"
  local url=${!url_var} sha=${!sha_var}
  local f="$CACHE/$(basename "$url")"
  mkdir -p "$CACHE"
  if ! { [[ -f "$f" ]] && echo "$sha  $f" | sha256sum -c --quiet - 2>/dev/null; }; then
    say "Downloading $(basename "$url") (~170 MB)"
    run curl -fL --retry 3 -C - -o "$f.part" "$url"
    (( dry )) || mv "$f.part" "$f"
  fi
  (( dry )) || echo "$sha  $f" | sha256sum -c --quiet - || die "SHA256 mismatch for $f"
  DEB="$f"
}

# ---------- install ------------------------------------------------------------
case "$method" in
arch)
  (( EUID != 0 )) || die "makepkg can't run as root; run this script as your normal user"
  root pacman -S --needed --noconfirm base-devel
  run cp -r "$src/arch" "$work/build"
  if [[ -f "$CACHE/claude-desktop_${VERSION}_${DEBARCH}.deb" ]]; then
    run ln -sf "$CACHE/claude-desktop_${VERSION}_${DEBARCH}.deb" "$work/build/claude-desktop-$VERSION-$DEBARCH.deb"
  fi
  in_dir "$work/build" makepkg --syncdeps --install --noconfirm
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root pacman -S --needed --noconfirm qemu-system-x86 edk2-ovmf
    else root pacman -S --needed --noconfirm qemu-system-aarch64 edk2-aarch64; fi
  fi
  ;;

rpm)
  if [[ $pm == zypper ]]; then
    root zypper -n install rpm-build binutils tar xz zstd curl
  else
    root dnf -y install rpm-build binutils tar xz zstd curl
  fi
  fetch_deb
  top="$work/rpmbuild"
  run mkdir -p "$top/SOURCES"
  run cp "$DEB" "$top/SOURCES/claude-desktop_${VERSION}_${DEBARCH}.deb"
  run rpmbuild -bb --define "_topdir $top" "$src/rpm/claude-desktop.spec"
  rpmfile="$top/RPMS/$ARCH/claude-desktop-$VERSION-1"*".$ARCH.rpm"
  if [[ $pm == zypper ]]; then
    # shellcheck disable=SC2086
    root zypper -n --no-gpg-checks install --allow-unsigned-rpm $rpmfile
    if (( cowork )); then
      if [[ $ARCH == x86_64 ]]; then root zypper -n install qemu-x86 qemu-ovmf-x86_64
      else root zypper -n install qemu-arm qemu-uefi-aarch64; fi
    fi
  else
    # shellcheck disable=SC2086
    root dnf -y install $rpmfile
    if (( cowork )); then
      if [[ $ARCH == x86_64 ]]; then root dnf -y install qemu-system-x86-core edk2-ovmf
      else root dnf -y install qemu-system-aarch64-core edk2-aarch64; fi
    fi
  fi
  ;;

gentoo)
  kw=$([[ $ARCH == x86_64 ]] && echo '~amd64' || echo '~arm64')
  conf=/etc/portage/repos.conf/claude-desktop-linux.conf
  if [[ ! -f $conf ]]; then
    root mkdir -p /etc/portage/repos.conf
    (( dry )) || printf '%s\n' "[claude-desktop-linux]" \
      "location = /var/db/repos/claude-desktop-linux" "sync-type = git" \
      "sync-uri = https://github.com/$REPO.git" \
      "sync-git-clone-extra-opts = --branch gentoo-overlay --single-branch" \
      | as_root_tee "$conf"
    echo "  wrote $conf"
  fi
  command -v git >/dev/null || root emerge --ask=n --noreplace dev-vcs/git
  root emaint sync -r claude-desktop-linux
  # package.accept_keywords / package.license may be files or directories
  add_portage_line() {
    local base=$1 line=$2 target
    if [[ -d $base ]]; then target="$base/claude-desktop"; else target=$base; fi
    if ! grep -qsF "$line" "$target"; then
      echo "  add '$line' to $target"
      (( dry )) || echo "$line" | as_root_tee -a "$target"
    fi
  }
  add_portage_line /etc/portage/package.accept_keywords "app-misc/claude-desktop $kw"
  add_portage_line /etc/portage/package.license "app-misc/claude-desktop all-rights-reserved"
  root emerge --ask=n --update app-misc/claude-desktop
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root emerge --ask=n --noreplace app-emulation/qemu sys-firmware/edk2-bin
    else warn "Cowork isn't available on Gentoo arm64 (firmware is shipped as qcow2 only)"; fi
  fi
  ;;

void)
  (( EUID != 0 )) || die "xbps-src should run as a normal user; run this script as your normal user"
  root xbps-install -Sy git bash curl
  vp="$CACHE/void-packages"
  if [[ -d $vp/.git ]]; then run git -C "$vp" pull --ff-only --depth 1
  else run git clone --depth 1 https://github.com/void-linux/void-packages "$vp"; fi
  if (( ! dry )) && ! grep -qs '^XBPS_ALLOW_RESTRICTED=yes' "$vp/etc/conf"; then
    echo XBPS_ALLOW_RESTRICTED=yes >> "$vp/etc/conf"
  fi
  run rm -rf "$vp/srcpkgs/claude-desktop"
  run cp -r "$src/void/srcpkgs/claude-desktop" "$vp/srcpkgs/"
  in_dir "$vp" ./xbps-src binary-bootstrap
  in_dir "$vp" ./xbps-src pkg claude-desktop
  root xbps-install -y --repository="$vp/hostdir/binpkgs/nonfree" claude-desktop
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root xbps-install -y qemu-system-amd64 edk2-ovmf
    else root xbps-install -y qemu-system-aarch64 edk2-ovmf; fi
  fi
  ;;

deb)
  fetch_deb
  # apt needs a world-readable path for the _apt user
  run cp "$DEB" "$work/claude-desktop.deb"
  run chmod 644 "$work/claude-desktop.deb"
  run chmod 755 "$work"
  root apt-get install -y "$work/claude-desktop.deb"
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root apt-get install -y qemu-system-x86 ovmf
    else root apt-get install -y qemu-system-arm qemu-efi-aarch64; fi
  fi
  ;;

appimage)
  fetch_deb
  run "$src/appimage/build-appimage.sh" "$ARCH" --deb "$DEB" --out "$work"
  run mkdir -p "$(dirname "$appimage_path")" "$(dirname "$desktop_user")"
  run install -m755 "$work/Claude-$VERSION-$ARCH.AppImage" "$appimage_path"
  if (( ! dry )); then
    # menu entry, icons and the claude:// link handler
    (cd "$work" && "$appimage_path" --appimage-extract 'usr/share/applications/*' >/dev/null \
                && "$appimage_path" --appimage-extract 'usr/share/icons/*' >/dev/null)
    sed "s#^Exec=claude-desktop#Exec=\"$appimage_path\"#" \
      "$work/squashfs-root/usr/share/applications/com.anthropic.Claude.desktop" > "$desktop_user"
    cp -r "$work/squashfs-root/usr/share/icons" "$HOME/.local/share/"
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$HOME/.local/share/applications" || true
    command -v xdg-mime >/dev/null && xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude || true
  fi
  echo "  installed $appimage_path (+ menu entry)"
  (( cowork )) && warn "--cowork: install QEMU and UEFI firmware with your package manager"
  ;;
esac

# ---------- after install --------------------------------------------------------
if (( ! dry )) && command -v busctl >/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  if ! busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets; then
    warn "no secret-storage service found: Claude won't stay signed in."
    echo "         Install gnome-keyring (or KWallet on KDE), then log out and back in."
  fi
fi
say "done. Start Claude from your app menu or run: claude-desktop"
[[ $method == appimage ]] && echo "    (AppImage: $appimage_path)"
exit 0
