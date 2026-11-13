# Repackages Anthropic's official Claude Desktop .deb as an RPM for Fedora,
# RHEL/AlmaLinux/Rocky 9+ and openSUSE. The .deb is downloaded from
# Anthropic's apt repository; the checksums are taken from its GPG-signed
# index by scripts/upstream.sh.
#
# Build:  mkdir -p rpmbuild/SOURCES && rpmbuild -bb --undefine=_disable_source_fetch claude-desktop.spec

%global sha256_x86_64  9c5cf5d4c8b2356779a3dde7dedfe1c301a7223971597198213d815fe8ccfa55
%global sha256_aarch64 0705809bfc8c72877aab551cca99b2ff8632849897f47144096c6f18ad3848cf
%global repo https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop

%ifarch x86_64
%global debarch amd64
%global debsha %{sha256_x86_64}
%endif
%ifarch aarch64
%global debarch arm64
%global debsha %{sha256_aarch64}
%endif

# Prebuilt binaries: no debuginfo, stripping, build-id links, rpath/brp checks
%global debug_package %{nil}
%global _build_id_links none
%global __os_install_post %{nil}
%global __arch_install_post %{nil}

Name:           claude-desktop
Version:        5.11492.0
Release:        1%{?dist}
Summary:        Desktop application for Claude.ai (official build, repackaged)
License:        LicenseRef-Anthropic-Proprietary
URL:            https://claude.ai/download
Source0:        %{repo}/claude-desktop_%{version}_%{debarch}.deb
ExclusiveArch:  x86_64 aarch64
# Bundled Electron libraries must not satisfy or create system dependencies
AutoReqProv:    no

BuildRequires:  binutils
BuildRequires:  tar
BuildRequires:  xz
BuildRequires:  zstd

Requires:       glibc
Requires:       xdg-desktop-portal
Requires:       xdg-utils
Requires:       hicolor-icon-theme
%if 0%{?suse_version}
Requires:       libasound2
Requires:       libatspi0
Requires:       libdrm2
Requires:       libgbm1
Requires:       libgtk-3-0
Requires:       libnotify4
Requires:       libpipewire-0_3-0
Requires:       libsecret-1-0
Requires:       libuuid1
Requires:       libxcb1
Requires:       libXtst6
Requires:       mozilla-nss
Recommends:     (xdg-desktop-portal-gtk or xdg-desktop-portal-kde6 or xdg-desktop-portal-gnome)
Recommends:     (gnome-keyring or kwalletd6)
Recommends:     libayatana-appindicator3-1
Recommends:     bubblewrap
Recommends:     socat
Recommends:     openssh-clients
%ifarch x86_64
Suggests:       qemu-x86
Suggests:       qemu-ovmf-x86_64
%endif
%ifarch aarch64
Suggests:       qemu-arm
Suggests:       qemu-uefi-aarch64
%endif
%else
Requires:       alsa-lib
Requires:       at-spi2-core
Requires:       gtk3
Requires:       libdrm
Requires:       libnotify
Requires:       libsecret
Requires:       libuuid
Requires:       libxcb
Requires:       libXtst
Requires:       mesa-libgbm
Requires:       nss
Requires:       pipewire-libs
Recommends:     (xdg-desktop-portal-gtk or xdg-desktop-portal-kde or xdg-desktop-portal-gnome)
Recommends:     (gnome-keyring or kf6-kwallet)
Recommends:     libayatana-appindicator-gtk3
Recommends:     bubblewrap
Recommends:     socat
Recommends:     openssh-clients
%ifarch x86_64
Suggests:       qemu-system-x86-core
Suggests:       edk2-ovmf
%endif
%ifarch aarch64
Suggests:       qemu-system-aarch64-core
Suggests:       edk2-aarch64
%endif
%endif
Suggests:       trash-cli
Suggests:       gjs

%description
Claude Desktop, Anthropic's desktop application for Claude.ai, repackaged
from the official Debian build without modification.

%prep
echo "%{debsha}  %{SOURCE0}" | sha256sum -c -
rm -rf deb && mkdir deb && cd deb
ar x %{SOURCE0}
tar -xf data.tar.*
got=$(tar -xOf control.tar.* ./control | sed -n 's/^Version: //p')
[ "$got" = "%{version}" ] || { echo "deb is version $got, expected %{version}"; exit 1; }

%build
# Nothing to build: prebuilt upstream binaries.

%install
cp -a deb/usr %{buildroot}/
rm -rf %{buildroot}/usr/share/lintian %{buildroot}/usr/share/doc/claude-desktop

res=%{buildroot}/usr/lib/claude-desktop/resources
install -Dm644 $res/linux-mime/com.anthropic.Claude.xml \
  %{buildroot}%{_datadir}/mime/packages/com.anthropic.Claude.xml
install -Dm644 $res/gnome-search-provider/com.anthropic.Claude.search-provider.ini \
  %{buildroot}%{_datadir}/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini
install -Dm644 $res/gnome-search-provider/com.anthropic.Claude.SearchProvider.service \
  %{buildroot}%{_datadir}/dbus-1/services/com.anthropic.Claude.SearchProvider.service

%if 0%{?suse_version}
# Cowork looks for UEFI firmware only at Debian's paths; openSUSE keeps it in
# /usr/share/qemu. (Fedora's edk2 packages already provide the Debian paths.)
%ifarch x86_64
install -d %{buildroot}%{_datadir}/OVMF
ln -s ../qemu/ovmf-x86_64-4m-code.bin %{buildroot}%{_datadir}/OVMF/OVMF_CODE_4M.fd
ln -s ../qemu/ovmf-x86_64-4m-vars.bin %{buildroot}%{_datadir}/OVMF/OVMF_VARS_4M.fd
%endif
%ifarch aarch64
install -d %{buildroot}%{_datadir}/AAVMF
ln -s ../qemu/aavmf-aarch64-code.bin %{buildroot}%{_datadir}/AAVMF/AAVMF_CODE.fd
ln -s ../qemu/aavmf-aarch64-vars.bin %{buildroot}%{_datadir}/AAVMF/AAVMF_VARS.fd
%endif
%endif

%files
%license deb/usr/share/doc/claude-desktop/copyright
%{_bindir}/claude-desktop
%dir /usr/lib/claude-desktop
/usr/lib/claude-desktop/*
%attr(4755,root,root) /usr/lib/claude-desktop/chrome-sandbox
%{_datadir}/applications/com.anthropic.Claude.desktop
%{_datadir}/icons/hicolor/*/apps/claude-desktop.png
%{_datadir}/mime/packages/com.anthropic.Claude.xml
%dir %{_datadir}/gnome-shell
%dir %{_datadir}/gnome-shell/search-providers
%{_datadir}/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini
%{_datadir}/dbus-1/services/com.anthropic.Claude.SearchProvider.service
%if 0%{?suse_version}
%ifarch x86_64
%dir %{_datadir}/OVMF
%{_datadir}/OVMF/OVMF_CODE_4M.fd
%{_datadir}/OVMF/OVMF_VARS_4M.fd
%endif
%ifarch aarch64
%dir %{_datadir}/AAVMF
%{_datadir}/AAVMF/AAVMF_CODE.fd
%{_datadir}/AAVMF/AAVMF_VARS.fd
%endif
%endif
