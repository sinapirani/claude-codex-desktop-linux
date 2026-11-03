# Repackages OpenAI's official Codex desktop app (package "chatgpt") .deb as
# an RPM for Fedora, RHEL/AlmaLinux/Rocky 9+ and openSUSE. The .deb is
# downloaded from OpenAI's apt repository; the checksums are taken from its
# GPG-signed index by scripts/upstream.sh.
#
# Build:  mkdir -p rpmbuild/SOURCES && rpmbuild -bb --undefine=_disable_source_fetch chatgpt.spec

%global sha256_x86_64  f3af8afec5d25c228eb6f4dbd9cfde0fea7ca5e4b42aff0145a1ded273d01b2d
%global sha256_aarch64 4719adfb33fe68e7becdb8169cea5945a297ebb7e3aa9966de7c2a945242bc2b
%global repo https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt

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
# 1.7 GB of files: the distro default (zstd level 19) takes far too long
%global _binary_payload w3.zstdio

Name:           chatgpt
Version:        26.1029.61003
Release:        1%{?dist}
Summary:        Codex desktop app by OpenAI (official ChatGPT build, repackaged)
License:        LicenseRef-OpenAI-Proprietary
URL:            https://developers.openai.com/codex/app
Source0:        %{repo}/chatgpt_%{version}_%{debarch}.deb
ExclusiveArch:  x86_64 aarch64
# Bundled Electron and Node libraries must not satisfy or create system
# dependencies
AutoReqProv:    no

BuildRequires:  binutils
BuildRequires:  tar
BuildRequires:  xz

# Libraries by soname, so the same list works on Fedora, RHEL and openSUSE
# (both 64-bit architectures use the "(64bit)" marker).
Requires:       glibc
Requires:       libasound.so.2()(64bit)
Requires:       libatk-1.0.so.0()(64bit)
Requires:       libatk-bridge-2.0.so.0()(64bit)
Requires:       libatspi.so.0()(64bit)
Requires:       libcairo.so.2()(64bit)
Requires:       libcrypto.so.3()(64bit)
Requires:       libcups.so.2()(64bit)
Requires:       libdbus-1.so.3()(64bit)
Requires:       libexpat.so.1()(64bit)
Requires:       libgbm.so.1()(64bit)
Requires:       libgdk_pixbuf-2.0.so.0()(64bit)
Requires:       libGL.so.1()(64bit)
Requires:       libglib-2.0.so.0()(64bit)
Requires:       libgtk-3.so.0()(64bit)
Requires:       libnotify.so.4()(64bit)
Requires:       libnspr4.so()(64bit)
Requires:       libnss3.so()(64bit)
Requires:       libpango-1.0.so.0()(64bit)
Requires:       libtss2-esys.so.0()(64bit)
Requires:       libtss2-mu.so.0()(64bit)
Requires:       libtss2-tcti-device.so.0()(64bit)
Requires:       libudev.so.1()(64bit)
Requires:       libusb-1.0.so.0()(64bit)
Requires:       libX11.so.6()(64bit)
Requires:       libxcb.so.1()(64bit)
Requires:       libXcomposite.so.1()(64bit)
Requires:       libXdamage.so.1()(64bit)
Requires:       libXext.so.6()(64bit)
Requires:       libXfixes.so.3()(64bit)
Requires:       libxkbcommon.so.0()(64bit)
Requires:       libXrandr.so.2()(64bit)
Requires:       xdg-utils
Requires:       xz
Recommends:     git
%if 0%{?suse_version}
Recommends:     (xdg-desktop-portal-gtk or xdg-desktop-portal-kde6 or xdg-desktop-portal-gnome)
Recommends:     (gnome-keyring or kwalletd6)
%else
Recommends:     (xdg-desktop-portal-gtk or xdg-desktop-portal-kde or xdg-desktop-portal-gnome)
Recommends:     (gnome-keyring or kf6-kwallet)
%endif

%description
Codex, OpenAI's desktop app (shipped as "ChatGPT"), repackaged from the
official Debian build without modification.

%prep
echo "%{debsha}  %{SOURCE0}" | sha256sum -c -
rm -rf deb && mkdir deb && cd deb
ar x %{SOURCE0}
tar -xf data.tar.* ./usr
got=$(tar -xOf control.tar.* ./control | sed -n 's/^Version: //p')
[ "$got" = "%{version}" ] || { echo "deb is version $got, expected %{version}"; exit 1; }

%build
# Nothing to build: prebuilt upstream binaries.

%install
# Only usr/: the .deb's etc/ holds just an AppArmor profile for Ubuntu.
cp -a deb/usr %{buildroot}/
rm -rf %{buildroot}/usr/share/lintian %{buildroot}/usr/share/doc/chatgpt

%files
%license deb/usr/share/doc/chatgpt/copyright
%{_bindir}/chatgpt
%dir /usr/lib/chatgpt
/usr/lib/chatgpt/*
%{_datadir}/applications/chatgpt.desktop
%{_datadir}/pixmaps/chatgpt.png
%{_datadir}/metainfo/com.openai.chatgpt.metainfo.xml
%{_datadir}/swcatalog/xml/com.openai.chatgpt.xml
