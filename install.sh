#!/usr/bin/env bash
# Install Claude Desktop or Codex (OpenAI's ChatGPT desktop app) on (almost)
# any Linux distro.
#
#   curl -fsSL https://raw.githubusercontent.com/sinapirani/claude-codex-desktop-linux/main/install.sh | bash
#
# Asks which app to install (or pass --app), detects your distro and uses the
# best method:
#   Arch family      -> builds arch/<app>/PKGBUILD, installs with pacman
#   Fedora / RHEL    -> builds rpm/<app>.spec, installs with dnf
#   openSUSE         -> builds rpm/<app>.spec, installs with zypper
#   Gentoo           -> adds the overlay, emerges app-misc/<app>
#   Void (glibc)     -> builds void/ template with xbps-src, installs with xbps
#   Debian / Ubuntu  -> installs the vendor's official .deb (it adds the
#                       vendor's apt repo, so updates come through apt)
#   anything else    -> builds an AppImage and adds it to your app menu
#
# Options:
#   --app A       claude (Claude Desktop) | codex (OpenAI's ChatGPT/Codex app)
#   --method M    force a method: arch | rpm | gentoo | void | deb | appimage
#   --cowork      also install QEMU + UEFI firmware for Cowork (Claude only)
#   --uninstall   remove the app installed by this script
#   --dry-run     show what would happen, change nothing
#   -y, --yes     don't ask for confirmation (without --app: installs Claude)
#   -h, --help    show this help
#
# Re-run the script to update (the Debian method updates through apt).
set -euo pipefail

REPO="sinapirani/claude-codex-desktop-linux"
TARBALL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-linux"

app="" method="" cowork=0 uninstall=0 dry=0 yes=0
usage() {
  cat <<'EOF_USAGE'
Install Claude Desktop or Codex (OpenAI's ChatGPT desktop app) on (almost)
any Linux distro.

  curl -fsSL https://raw.githubusercontent.com/sinapirani/claude-codex-desktop-linux/main/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- --app codex   (pass options like this)

Options:
  --app A       claude (Claude Desktop) | codex (OpenAI's ChatGPT/Codex app)
                (asked interactively when not given)
  --method M    force a method: arch | rpm | gentoo | void | deb | appimage
  --cowork      also install QEMU + UEFI firmware for Cowork (Claude only)
  --uninstall   remove the app installed by this script
  --dry-run     show what would happen, change nothing
  -y, --yes     don't ask for confirmation (without --app: installs Claude)
  -h, --help    show this help
EOF_USAGE
}
while (( $# )); do
  case "$1" in
    --app) app=${2:-}; shift ;;
    --app=*) app=${1#*=} ;;
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

# ---------- which app --------------------------------------------------------
if [[ -z "$app" ]]; then
  if (( yes )) || [[ ! -r /dev/tty ]]; then
    app=claude
  else
    echo "${b}Which app do you want to $([[ $uninstall == 1 ]] && echo uninstall || echo install)?${n}"
    echo "  1) Claude Desktop  (Anthropic)"
    echo "  2) Codex           (OpenAI's ChatGPT desktop app)"
    read -r -p "Choose [1/2]: " ans </dev/tty || ans=""
    case "$ans" in
      1|[Cc]laude*) app=claude ;;
      2|[Cc]odex*|[Cc]hat[Gg][Pp][Tt]*) app=codex ;;
      *) die "no app chosen (answer 1 or 2, or pass --app claude|codex)" ;;
    esac
  fi
fi

# Per-app settings:
#   PKG       package name (same as the vendor's .deb)
#   TITLE     name shown to the user
#   BIN       command the package installs
#   GLIBC     oldest glibc the vendor's build supports
#   DEB_MB    approximate download size
#   DESKTOP   .desktop file name;  SCHEME  URL scheme the app handles
#   AI_NAME   AppImage file name prefix
case "$app" in
  claude|claude-desktop)
    PKG=claude-desktop TITLE="Claude Desktop" BIN=claude-desktop GLIBC=2.34 DEB_MB=170
    DESKTOP=com.anthropic.Claude.desktop SCHEME=claude AI_NAME=Claude VENDOR=Anthropic ;;
  codex|chatgpt)
    PKG=chatgpt TITLE="Codex (ChatGPT desktop app)" BIN=chatgpt GLIBC=2.30 DEB_MB=530
    DESKTOP=chatgpt.desktop SCHEME=codex AI_NAME=ChatGPT VENDOR=OpenAI ;;
  *) die "unknown app: $app (use claude or codex)" ;;
esac
if (( cowork )) && [[ $PKG != claude-desktop ]]; then
  warn "--cowork is a Claude Desktop feature; ignoring it for $TITLE"
  cowork=0
fi

# ---------- system checks ---------------------------------------------------
[[ "$(uname -s)" == Linux ]] || die "this installer is for Linux"
case "$(uname -m)" in
  x86_64)  ARCH=x86_64  DEBARCH=amd64 ;;
  aarch64|arm64) ARCH=aarch64 DEBARCH=arm64 ;;
  *) die "unsupported CPU architecture $(uname -m): $VENDOR publishes only x86_64 and aarch64 builds" ;;
esac

[[ -r /etc/os-release ]] && . /etc/os-release
ID=${ID:-unknown}; ID_LIKE=${ID_LIKE:-}
ids=" $ID $ID_LIKE "

glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)   # "glibc 2.39"
glibc=${glibc#glibc }
if [[ -z "$glibc" ]]; then
  die "no glibc found (musl-based distros like Alpine or Void-musl can't run the official build)"
fi
if [[ "$(printf '%s\n' "$GLIBC" "$glibc" | sort -V | head -n1)" != "$GLIBC" ]]; then
  die "glibc $glibc is too old; $TITLE needs $GLIBC or newer"
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
say "$action $TITLE"
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

# Packages to install for the commands that are missing: missing_pkgs cmd=pkg ...
missing_pkgs() {
  local pair out=()
  for pair; do command -v "${pair%%=*}" >/dev/null || out+=("${pair#*=}"); done
  echo "${out[*]}"
}

# ---------- uninstall --------------------------------------------------------
appimage_dir="$HOME/.local/share/$PKG"
appimage_path="$appimage_dir/$AI_NAME.AppImage"
desktop_user="$HOME/.local/share/applications/$DESKTOP"
if (( uninstall )); then
  case "$method" in
    arch)   root pacman -R --noconfirm "$PKG" ;;
    rpm)    if [[ $pm == zypper ]]; then root zypper -n remove "$PKG"; else root dnf -y remove "$PKG"; fi ;;
    gentoo) root emerge --ask=n --depclean "app-misc/$PKG" || root emerge --ask=n -C "app-misc/$PKG" ;;
    void)   root xbps-remove -y "$PKG" ;;
    deb)    root apt-get remove -y "$PKG" ;;
    appimage)
      run rm -rf "$appimage_dir"
      run rm -f "$desktop_user"
      [[ $PKG == claude-desktop ]] && run rm -f "$HOME"/.local/share/icons/hicolor/*/apps/claude-desktop.png ;;
  esac
  say "done"
  exit 0
fi

# ---------- get the recipes ---------------------------------------------------
here=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
# Build on disk next to the download cache, not in /tmp: the unpacked apps are
# large (Codex: ~1.7 GB, twice while packaging) and /tmp is often a RAM disk.
mkdir -p "$CACHE"
work=$(mktemp -d "$CACHE/work.XXXXXX")
trap 'rm -rf "$work"' EXIT
if [[ -n "$here" && -f "$here/upstream/$PKG.env" && -d "$here/arch/$PKG" ]]; then
  src="$here"
else
  say "Downloading recipes from github.com/$REPO"
  command -v curl >/dev/null || die "curl is required"
  curl -fsSL "$TARBALL" | tar -xz -C "$work"
  src=$(echo "$work"/claude-codex-desktop-linux-*)
fi
# shellcheck disable=SC1090
. "$src/upstream/$PKG.env"
say "$TITLE $VERSION"

# Download the official .deb and check it against the vendor's signed index hash
fetch_deb() {
  local url_var="DEB_${DEBARCH^^}_URL" sha_var="DEB_${DEBARCH^^}_SHA256"
  local url=${!url_var} sha=${!sha_var}
  local f="$CACHE/$(basename "$url")"
  if ! { [[ -f "$f" ]] && echo "$sha  $f" | sha256sum -c --quiet - 2>/dev/null; }; then
    say "Downloading $(basename "$url") (~$DEB_MB MB)"
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
  run cp -r "$src/arch/$PKG" "$work/build"
  if [[ -f "$CACHE/${PKG}_${VERSION}_${DEBARCH}.deb" ]]; then
    run ln -sf "$CACHE/${PKG}_${VERSION}_${DEBARCH}.deb" "$work/build/$PKG-$VERSION-$DEBARCH.deb"
  fi
  in_dir "$work/build" makepkg --syncdeps --install --noconfirm
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root pacman -S --needed --noconfirm qemu-system-x86 edk2-ovmf
    else root pacman -S --needed --noconfirm qemu-system-aarch64 edk2-aarch64; fi
  fi
  ;;

rpm)
  need=$(missing_pkgs rpmbuild=rpm-build ar=binutils tar=tar xz=xz zstd=zstd curl=curl)
  if [[ -n $need ]]; then
    # shellcheck disable=SC2086
    if [[ $pm == zypper ]]; then root zypper -n install $need; else root dnf -y install $need; fi
  fi
  fetch_deb
  top="$work/rpmbuild"
  run mkdir -p "$top/SOURCES"
  run ln -s "$DEB" "$top/SOURCES/${PKG}_${VERSION}_${DEBARCH}.deb"
  run rpmbuild -bb --define "_topdir $top" "$src/rpm/$PKG.spec"
  rpmfile="$top/RPMS/$ARCH/$PKG-$VERSION-1"*".$ARCH.rpm"
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
    if [[ -d $base ]]; then target="$base/$PKG"; else target=$base; fi
    if ! grep -qsF "$line" "$target"; then
      echo "  add '$line' to $target"
      (( dry )) || echo "$line" | as_root_tee -a "$target"
    fi
  }
  add_portage_line /etc/portage/package.accept_keywords "app-misc/$PKG $kw"
  add_portage_line /etc/portage/package.license "app-misc/$PKG all-rights-reserved"
  root emerge --ask=n --update "app-misc/$PKG"
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root emerge --ask=n --noreplace app-emulation/qemu sys-firmware/edk2-bin
    else warn "Cowork isn't available on Gentoo arm64 (firmware is shipped as qcow2 only)"; fi
  fi
  ;;

void)
  (( EUID != 0 )) || die "xbps-src should run as a normal user; run this script as your normal user"
  need=$(missing_pkgs git=git curl=curl)
  # shellcheck disable=SC2086
  [[ -z $need ]] || root xbps-install -Sy $need
  vp="$CACHE/void-packages"
  if [[ -d $vp/.git ]]; then run git -C "$vp" pull --ff-only --depth 1
  else run git clone --depth 1 https://github.com/void-linux/void-packages "$vp"; fi
  if (( ! dry )) && ! grep -qs '^XBPS_ALLOW_RESTRICTED=yes' "$vp/etc/conf"; then
    echo XBPS_ALLOW_RESTRICTED=yes >> "$vp/etc/conf"
  fi
  # Containers without user namespaces: XBPS_CHROOT_CMD=uchroot ./install.sh
  if (( ! dry )) && [[ -n "${XBPS_CHROOT_CMD:-}" ]] && ! grep -qs "^XBPS_CHROOT_CMD=$XBPS_CHROOT_CMD" "$vp/etc/conf"; then
    echo "XBPS_CHROOT_CMD=$XBPS_CHROOT_CMD" >> "$vp/etc/conf"
  fi
  run rm -rf "$vp/srcpkgs/$PKG"
  run cp -r "$src/void/srcpkgs/$PKG" "$vp/srcpkgs/"
  in_dir "$vp" ./xbps-src binary-bootstrap
  in_dir "$vp" ./xbps-src pkg "$PKG"
  root xbps-install -y --repository="$vp/hostdir/binpkgs/nonfree" "$PKG"
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root xbps-install -y qemu-system-amd64 edk2-ovmf
    else root xbps-install -y qemu-system-aarch64 edk2-ovmf; fi
  fi
  ;;

deb)
  fetch_deb
  # apt needs a world-readable path for the _apt user (not under $HOME)
  debtmp=$(mktemp -d)
  trap 'rm -rf "$work" "$debtmp"' EXIT
  run cp "$DEB" "$debtmp/$PKG.deb"
  run chmod 644 "$debtmp/$PKG.deb"
  run chmod 755 "$debtmp"
  root apt-get install -y "$debtmp/$PKG.deb"
  if (( cowork )); then
    if [[ $ARCH == x86_64 ]]; then root apt-get install -y qemu-system-x86 ovmf
    else root apt-get install -y qemu-system-arm qemu-efi-aarch64; fi
  fi
  ;;

appimage)
  fetch_deb
  run "$src/appimage/build-appimage.sh" --app "$PKG" "$ARCH" --deb "$DEB" --out "$work"
  run mkdir -p "$appimage_dir" "$(dirname "$desktop_user")"
  run install -m755 "$work/$AI_NAME-$VERSION-$ARCH.AppImage" "$appimage_path"
  if (( ! dry )); then
    # menu entry, icon and the URL-scheme handler
    if [[ $PKG == claude-desktop ]]; then
      (cd "$work" && "$appimage_path" --appimage-extract "usr/share/applications/$DESKTOP" >/dev/null \
                  && "$appimage_path" --appimage-extract 'usr/share/icons/*' >/dev/null)
      sed "s#^Exec=[^ ]*#Exec=\"$appimage_path\"#" \
        "$work/squashfs-root/usr/share/applications/$DESKTOP" > "$desktop_user"
      cp -r "$work/squashfs-root/usr/share/icons" "$HOME/.local/share/"
    else
      # Codex ships only a 1024px icon in pixmaps/: point the entry at it directly
      (cd "$work" && "$appimage_path" --appimage-extract "usr/share/applications/$DESKTOP" >/dev/null \
                  && "$appimage_path" --appimage-extract 'usr/share/pixmaps/*' >/dev/null)
      install -m644 "$work/squashfs-root/usr/share/pixmaps/$PKG.png" "$appimage_dir/$PKG.png"
      sed -e "s#^Exec=[^ ]*#Exec=\"$appimage_path\"#" -e "s#^Icon=.*#Icon=$appimage_dir/$PKG.png#" \
        "$work/squashfs-root/usr/share/applications/$DESKTOP" > "$desktop_user"
    fi
    command -v update-desktop-database >/dev/null && update-desktop-database -q "$HOME/.local/share/applications" || true
    command -v xdg-mime >/dev/null && xdg-mime default "$DESKTOP" "x-scheme-handler/$SCHEME" || true
  fi
  echo "  installed $appimage_path (+ menu entry)"
  (( cowork )) && warn "--cowork: install QEMU and UEFI firmware with your package manager"
  ;;
esac

# ---------- after install --------------------------------------------------------
if (( ! dry )) && command -v busctl >/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  if ! busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets; then
    warn "no secret-storage service found: $TITLE may not stay signed in."
    echo "         Install gnome-keyring (or KWallet on KDE), then log out and back in."
  fi
fi
if [[ $method == appimage ]]; then
  say "done. Start $TITLE from your app menu or run: $appimage_path"
else
  say "done. Start $TITLE from your app menu or run: $BIN"
fi
exit 0
