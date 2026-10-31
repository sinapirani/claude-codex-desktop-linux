# Claude Desktop for Linux (non-Debian distros)

Anthropic ships Claude Desktop for Linux only as a Debian/Ubuntu `.deb`.
This repo has packaging recipes that turn that **official build** into native
packages for other distros, plus an AppImage for everything else:

| Distro family | Covers | Recipe |
|---|---|---|
| Arch | Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Artix, Arch Linux ARM | [`arch/PKGBUILD`](arch/PKGBUILD) |
| Fedora / RHEL | Fedora, RHEL / AlmaLinux / Rocky 9+, Nobara | [`rpm/claude-desktop.spec`](rpm/claude-desktop.spec) |
| openSUSE | Tumbleweed, Slowroll | [`rpm/claude-desktop.spec`](rpm/claude-desktop.spec) |
| Gentoo | Gentoo | [`gentoo/`](gentoo) overlay |
| Void | Void Linux (glibc) | [`void/srcpkgs/claude-desktop/template`](void/srcpkgs/claude-desktop/template) |
| Anything else | any x86_64 / aarch64 distro with glibc ≥ 2.34 | [`appimage/build-appimage.sh`](appimage/build-appimage.sh) |

Debian, Ubuntu and their derivatives should use
[Anthropic's official package](https://claude.ai/download) directly.

**Nothing from Anthropic is stored or redistributed here.** Every recipe
downloads the `.deb` from `downloads.claude.ai` at build time and checks it
against a SHA256 taken from Anthropic's GPG-signed apt index (see
[How updates are verified](#how-updates-are-verified)).

Requirements: x86_64 or aarch64, glibc 2.34 or newer (Anthropic publishes
only these two architectures).

## Install

All recipes download about 170 MB from `downloads.claude.ai` while building.
**Cowork** (Claude's local VM feature) also needs QEMU and UEFI firmware;
the packages are listed for each distro below.

### Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Arch Linux ARM

```sh
git clone https://github.com/sinapirani/claude-desktop-linux
cd claude-desktop-linux/arch
makepkg -si
```

Update: `git pull && makepkg -si`.
Cowork: `sudo pacman -S qemu-system-x86 edk2-ovmf` (on ARM: `qemu-system-aarch64 edk2-aarch64`).

### Fedora, RHEL / AlmaLinux / Rocky 9+

```sh
sudo dnf install rpm-build binutils git
git clone https://github.com/sinapirani/claude-desktop-linux
cd claude-desktop-linux
mkdir -p rpmbuild/SOURCES
rpmbuild -bb --undefine=_disable_source_fetch --define "_topdir $PWD/rpmbuild" rpm/claude-desktop.spec
sudo dnf install ./rpmbuild/RPMS/$(uname -m)/claude-desktop-*.rpm
```

Cowork: `sudo dnf install qemu-system-x86-core edk2-ovmf` (ARM: `qemu-system-aarch64-core edk2-aarch64`).

### openSUSE Tumbleweed / Slowroll

```sh
sudo zypper install rpm-build binutils git
git clone https://github.com/sinapirani/claude-desktop-linux
cd claude-desktop-linux
mkdir -p rpmbuild/SOURCES
rpmbuild -bb --undefine=_disable_source_fetch --define "_topdir $PWD/rpmbuild" rpm/claude-desktop.spec
sudo zypper install --allow-unsigned-rpm ./rpmbuild/RPMS/$(uname -m)/claude-desktop-*.rpm
```

Cowork: `sudo zypper install qemu-x86 qemu-ovmf-x86_64` (ARM: `qemu-arm qemu-uefi-aarch64`).

### Gentoo

The overlay is published on the `gentoo-overlay` branch:

```sh
sudo tee /etc/portage/repos.conf/claude-desktop-linux.conf <<'EOF'
[claude-desktop-linux]
location = /var/db/repos/claude-desktop-linux
sync-type = git
sync-uri = https://github.com/sinapirani/claude-desktop-linux.git
sync-git-clone-extra-opts = --branch gentoo-overlay --single-branch
EOF
sudo emaint sync -r claude-desktop-linux
echo 'app-misc/claude-desktop ~amd64' | sudo tee /etc/portage/package.accept_keywords/claude-desktop
echo 'app-misc/claude-desktop all-rights-reserved' | sudo tee /etc/portage/package.license/claude-desktop
sudo emerge -av app-misc/claude-desktop
```

Use `~arm64` instead of `~amd64` on ARM. Set `USE=suid` only if your kernel
disables unprivileged user namespaces.
Cowork (amd64): `app-emulation/qemu` with `QEMU_SOFTMMU_TARGETS="x86_64"`, plus
`sys-firmware/edk2-bin`. Cowork is not wired up on Gentoo arm64, because
Gentoo ships the aarch64 firmware only as qcow2.

### Void Linux (glibc)

Void doesn't build restricted (proprietary) packages for you, so build it
with `xbps-src`:

```sh
git clone --depth 1 https://github.com/void-linux/void-packages
git clone https://github.com/sinapirani/claude-desktop-linux
cd void-packages
./xbps-src binary-bootstrap
echo XBPS_ALLOW_RESTRICTED=yes >> etc/conf
cp -r ../claude-desktop-linux/void/srcpkgs/claude-desktop srcpkgs/
./xbps-src pkg claude-desktop
sudo xbps-install --repository=hostdir/binpkgs/nonfree claude-desktop
```

Cowork: `sudo xbps-install qemu-system-amd64 edk2-ovmf` (ARM: `qemu-system-aarch64 edk2-ovmf`).

### AppImage (any other distro)

```sh
git clone https://github.com/sinapirani/claude-desktop-linux
cd claude-desktop-linux
appimage/build-appimage.sh            # or: appimage/build-appimage.sh aarch64
./Claude-*-$(uname -m).AppImage
```

Needs `curl`, plus `bsdtar` or `ar` (binutils). Limitations compared with the
native packages:

- The app doesn't appear in your menu and `claude://` sign-in links don't open
  it until you integrate the AppImage (e.g. with Gear Lever or AppImageLauncher).
- No automatic updates: re-run the script after `git pull`.
- AppImages can't use a setuid sandbox. Where unprivileged user namespaces are
  blocked (e.g. Ubuntu 24.04+), it starts with `--no-sandbox` and prints a
  warning.
- Cowork works only if your distro already provides the Debian firmware paths
  (`/usr/share/OVMF/OVMF_CODE_4M.fd` or `OVMF_CODE.fd`).

## How updates are verified

[`scripts/upstream.sh`](scripts/upstream.sh) reads Anthropic's apt repository:

1. Downloads `InRelease` and verifies its GPG signature with
   [`keys/claude-desktop-archive-keyring.asc`](keys/claude-desktop-archive-keyring.asc),
   the key Anthropic ships inside the official `.deb`
   (fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`), and
   rejects an expired index.
2. Checks each `Packages` index against the SHA256 in the signed `Release`.
3. Takes the newest version published for both amd64 and arm64, with each
   `.deb`'s SHA256.

A [scheduled workflow](.github/workflows/update.yml) runs this every 6 hours.
When Anthropic publishes a new version it updates every recipe
([`scripts/bump.sh`](scripts/bump.sh)), test-builds and installs the result
in each distro's own container, and only then pushes to `main` and tags
`v<version>-1`.

## What the recipes change

None of Anthropic's files are modified. Compared with the `.deb`, each
package:

- uses the distro's own package names for dependencies;
- installs as packaged files what the Debian `postinst` script sets up at
  install time (file-type registrations, GNOME search provider), and leaves out
  the Debian-only parts (adding Anthropic's apt repo, the AppArmor profile);
- adds two links so **Cowork** (the local VM feature) finds the UEFI firmware.
  The app only looks at Debian's paths (`/usr/share/OVMF/OVMF_CODE_4M.fd`, or
  `/usr/share/AAVMF/AAVMF_CODE.fd` on ARM); the links point those at the
  distro's own firmware files.

## Troubleshooting

- **Signed out every time you restart the app** (log line
  `safeStorage ... isEncryptionAvailable=false`): no secret-storage service is
  running. Install `gnome-keyring` (or KWallet on KDE) and log out and back in.
  Desktops like Xfce, LXQt and window managers don't start one by default.
- **New session stuck on "Starting session"**: the first session downloads
  the Claude Code runtime (~100 MB). Watch progress with
  `grep download ~/.config/Claude/logs/main.log | tail`.
- **Cowork says QEMU is missing** and suggests `sudo apt install ...`: that
  message is written for Debian. Install your distro's QEMU and UEFI firmware
  packages listed above.

## License

The scripts in this repo are MIT-licensed. Claude Desktop itself is
proprietary software © Anthropic PBC; using it is subject to Anthropic's terms.
This project is not affiliated with Anthropic.
