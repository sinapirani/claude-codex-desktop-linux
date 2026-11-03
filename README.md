# Claude Desktop and Codex for Linux (non-Debian distros)

Anthropic ships **Claude Desktop** and OpenAI ships **Codex** (its desktop app,
packaged as `chatgpt`) for Linux only as Debian/Ubuntu `.deb` files. This repo
has packaging recipes that turn those **official builds** into native
packages for other distros, plus an AppImage for everything else:

| Distro family | Covers | Claude Desktop | Codex |
|---|---|---|---|
| Arch | Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Artix, Arch Linux ARM | [`arch/claude-desktop`](arch/claude-desktop/PKGBUILD) | [`arch/chatgpt`](arch/chatgpt/PKGBUILD) |
| Fedora / RHEL | Fedora, RHEL / AlmaLinux / Rocky 9+, Nobara | [`rpm/claude-desktop.spec`](rpm/claude-desktop.spec) | [`rpm/chatgpt.spec`](rpm/chatgpt.spec) |
| openSUSE | Tumbleweed, Slowroll | [`rpm/claude-desktop.spec`](rpm/claude-desktop.spec) | [`rpm/chatgpt.spec`](rpm/chatgpt.spec) |
| Gentoo | Gentoo | [`app-misc/claude-desktop`](gentoo/app-misc/claude-desktop) | [`app-misc/chatgpt`](gentoo/app-misc/chatgpt) |
| Void | Void Linux (glibc) | [`void/srcpkgs/claude-desktop`](void/srcpkgs/claude-desktop/template) | [`void/srcpkgs/chatgpt`](void/srcpkgs/chatgpt/template) |
| Anything else | any x86_64 / aarch64 distro with glibc | [`appimage/build-appimage.sh`](appimage/build-appimage.sh) | `appimage/build-appimage.sh --app chatgpt` |

Debian, Ubuntu and their derivatives should use the official packages
directly ([Claude](https://claude.ai/download),
[Codex](https://developers.openai.com/codex/app)); the install script does
that for you.

**Nothing from Anthropic or OpenAI is stored or redistributed here.** Every
recipe downloads the `.deb` from the vendor's own apt repository at build time
and checks it against a SHA256 taken from that repository's GPG-signed index
(see [How updates are verified](#how-updates-are-verified)).

Requirements: x86_64 or aarch64 (the only architectures either vendor
publishes), glibc 2.34+ for Claude Desktop, glibc 2.30+ for Codex.

## Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/sinapirani/claude-codex-desktop-linux/main/install.sh | bash
```

The script asks which app to install (Claude Desktop or Codex), detects your
distro, shows what it will do, and asks before changing anything. To skip the
question, pass the app: `curl -fsSL …/install.sh | bash -s -- --app codex`.

It picks:

| Your system | What it does |
|---|---|
| Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Artix | builds the PKGBUILD and installs it with pacman |
| Fedora, RHEL / Alma / Rocky 9+ | builds the RPM and installs it with dnf |
| openSUSE | builds the RPM and installs it with zypper |
| Gentoo | adds the overlay and emerges `app-misc/claude-desktop` or `app-misc/chatgpt` |
| Void (glibc) | builds the template with xbps-src and installs it |
| Debian, Ubuntu, Mint, Pop!_OS | installs the vendor's official `.deb` (updates then come through apt) |
| Silverblue, Bazzite, anything else | builds an AppImage and adds it to your app menu |

Options go after `bash -s --`:

| Option | |
|---|---|
| `--app A` | `claude` (Claude Desktop) or `codex` (OpenAI's Codex / ChatGPT desktop app); asked if not given |
| `--cowork` | also install QEMU + UEFI firmware for Cowork (Claude only) |
| `--method M` | force `arch`, `rpm`, `gentoo`, `void`, `deb` or `appimage` |
| `--dry-run` | print the plan and commands, change nothing |
| `--uninstall` | remove it again |
| `--yes` | don't ask for confirmation (without `--app` this installs Claude) |

Run it again to update. Run it as your normal user (it uses `sudo` where
needed; `makepkg` and `xbps-src` refuse to run as root). It builds in
`~/.cache/claude-desktop-linux`, not `/tmp`: Codex unpacks to about 1.7 GB.

## Manual install

The script just automates these steps. Below, `APP` is the package name:
`claude-desktop` for Claude Desktop or `chatgpt` for Codex.

```sh
APP=chatgpt   # or claude-desktop
```

The recipes download the `.deb` while building: about 170 MB for Claude
Desktop, about 530 MB for Codex.
**Cowork** (Claude's local VM feature) also needs QEMU and UEFI firmware;
the packages are listed for each distro below.

### Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Arch Linux ARM

```sh
git clone https://github.com/sinapirani/claude-codex-desktop-linux
cd claude-codex-desktop-linux/arch/$APP
makepkg -si
```

Update: `git pull && makepkg -si`.
Cowork: `sudo pacman -S qemu-system-x86 edk2-ovmf` (on ARM: `qemu-system-aarch64 edk2-aarch64`).

### Fedora, RHEL / AlmaLinux / Rocky 9+

```sh
sudo dnf install rpm-build binutils git
git clone https://github.com/sinapirani/claude-codex-desktop-linux
cd claude-codex-desktop-linux
mkdir -p rpmbuild/SOURCES
rpmbuild -bb --undefine=_disable_source_fetch --define "_topdir $PWD/rpmbuild" rpm/$APP.spec
sudo dnf install ./rpmbuild/RPMS/$(uname -m)/$APP-*.rpm
```

Cowork: `sudo dnf install qemu-system-x86-core edk2-ovmf` (ARM: `qemu-system-aarch64-core edk2-aarch64`).

### openSUSE Tumbleweed / Slowroll

```sh
sudo zypper install rpm-build binutils git
git clone https://github.com/sinapirani/claude-codex-desktop-linux
cd claude-codex-desktop-linux
mkdir -p rpmbuild/SOURCES
rpmbuild -bb --undefine=_disable_source_fetch --define "_topdir $PWD/rpmbuild" rpm/$APP.spec
sudo zypper install --allow-unsigned-rpm ./rpmbuild/RPMS/$(uname -m)/$APP-*.rpm
```

Cowork: `sudo zypper install qemu-x86 qemu-ovmf-x86_64` (ARM: `qemu-arm qemu-uefi-aarch64`).

### Gentoo

The overlay (both apps) is published on the `gentoo-overlay` branch:

```sh
sudo tee /etc/portage/repos.conf/claude-desktop-linux.conf <<'EOF'
[claude-desktop-linux]
location = /var/db/repos/claude-desktop-linux
sync-type = git
sync-uri = https://github.com/sinapirani/claude-codex-desktop-linux.git
sync-git-clone-extra-opts = --branch gentoo-overlay --single-branch
EOF
sudo emaint sync -r claude-desktop-linux
echo "app-misc/$APP ~amd64" | sudo tee /etc/portage/package.accept_keywords/$APP
echo "app-misc/$APP all-rights-reserved" | sudo tee /etc/portage/package.license/$APP
sudo emerge -av app-misc/$APP
```

Use `~arm64` instead of `~amd64` on ARM. For Claude Desktop, set `USE=suid`
only if your kernel disables unprivileged user namespaces.
Cowork (amd64): `app-emulation/qemu` with `QEMU_SOFTMMU_TARGETS="x86_64"`, plus
`sys-firmware/edk2-bin`. Cowork is not wired up on Gentoo arm64, because
Gentoo ships the aarch64 firmware only as qcow2.

### Void Linux (glibc)

Void doesn't build restricted (proprietary) packages for you, so build it
with `xbps-src`:

```sh
git clone --depth 1 https://github.com/void-linux/void-packages
git clone https://github.com/sinapirani/claude-codex-desktop-linux
cd void-packages
./xbps-src binary-bootstrap
echo XBPS_ALLOW_RESTRICTED=yes >> etc/conf
cp -r ../claude-codex-desktop-linux/void/srcpkgs/$APP srcpkgs/
./xbps-src pkg $APP
sudo xbps-install --repository=hostdir/binpkgs/nonfree $APP
```

Cowork: `sudo xbps-install qemu-system-amd64 edk2-ovmf` (ARM: `qemu-system-aarch64 edk2-ovmf`).

### AppImage (any other distro)

```sh
git clone https://github.com/sinapirani/claude-codex-desktop-linux
cd claude-codex-desktop-linux
appimage/build-appimage.sh --app $APP            # add "aarch64" to build for ARM
./Claude-*-$(uname -m).AppImage                  # Codex: ./ChatGPT-*-$(uname -m).AppImage
```

Needs `curl`, plus `bsdtar` or `ar` (binutils). Limitations compared with the
native packages:

- The app doesn't appear in your menu and `claude://` / `codex://` sign-in
  links don't open it until you integrate the AppImage (e.g. with Gear Lever
  or AppImageLauncher). The install script does this for you.
- No automatic updates: re-run the script after `git pull`.
- AppImages can't use a setuid sandbox. Where unprivileged user namespaces are
  blocked (e.g. Ubuntu 24.04+), it starts with `--no-sandbox` and prints a
  warning.
- Cowork works only if your distro already provides the Debian firmware paths
  (`/usr/share/OVMF/OVMF_CODE_4M.fd` or `OVMF_CODE.fd`).

## How updates are verified

[`scripts/upstream.sh`](scripts/upstream.sh) `APP` reads the vendor's apt
repository:

1. Downloads `InRelease` and verifies its GPG signature with the vendor's key,
   as shipped inside the official `.deb`, and rejects an expired index:
   - Claude Desktop: [`keys/claude-desktop-archive-keyring.asc`](keys/claude-desktop-archive-keyring.asc)
     (fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`),
     repository `downloads.claude.ai/claude-desktop/apt/stable`;
   - Codex: [`keys/chatgpt-archive-keyring.asc`](keys/chatgpt-archive-keyring.asc)
     ("Codex Linux Repository", fingerprint
     `3BFA 0E4A E8B8 CC16 A2D9 BA68 4A3B 4A56 6C46 60E4`), repository
     `persistent.oaistatic.com/codex-app-prod/linux/deb`.
2. Checks each `Packages` index against the SHA256 in the signed `Release`.
3. Takes the newest version published for both amd64 and arm64, with each
   `.deb`'s SHA256, and writes it to `upstream/<app>.env`.

A [scheduled workflow](.github/workflows/update.yml) runs this every 6 hours
for both apps. When a vendor publishes a new version it updates every recipe
of that app ([`scripts/bump.sh`](scripts/bump.sh) `APP`), test-builds and
installs the result in each distro's own container, and only then pushes to
`main` and tags `v<version>-1` (Claude Desktop) or `chatgpt-v<version>-1`
(Codex).

## What the recipes change

None of the vendors' files are modified. Compared with the `.deb`, each
package:

- uses the distro's own package names for dependencies;
- leaves out the Debian-only parts of the install scripts (adding the
  vendor's apt repo, the AppArmor profile that only Ubuntu's user-namespace
  restriction needs);
- Claude Desktop: installs as packaged files what the Debian `postinst` sets
  up at install time (file-type registrations, GNOME search provider), and
  adds two links so **Cowork** (the local VM feature) finds the UEFI firmware.
  The app only looks at Debian's paths (`/usr/share/OVMF/OVMF_CODE_4M.fd`, or
  `/usr/share/AAVMF/AAVMF_CODE.fd` on ARM); the links point those at the
  distro's own firmware files.

## Troubleshooting

- **Signed out every time you restart the app** (Claude log line
  `safeStorage ... isEncryptionAvailable=false`): no secret-storage service is
  running. Install `gnome-keyring` (or KWallet on KDE) and log out and back in.
  Desktops like Xfce, LXQt and window managers don't start one by default.
- **Claude: new session stuck on "Starting session"**: the first session
  downloads the Claude Code runtime (~100 MB). Watch progress with
  `grep download ~/.config/Claude/logs/main.log | tail`.
- **Claude: Cowork says QEMU is missing** and suggests `sudo apt install ...`:
  that message is written for Debian. Install your distro's QEMU and UEFI
  firmware packages listed above.
- **Codex: the command is `chatgpt`** and the menu entry is called *ChatGPT*:
  that is the name OpenAI gives the Linux build of the Codex app.

## License

The scripts in this repo are MIT-licensed. Claude Desktop is proprietary
software © Anthropic PBC and Codex / ChatGPT is proprietary software © OpenAI;
using them is subject to each vendor's terms. This project is not affiliated
with Anthropic or OpenAI.
