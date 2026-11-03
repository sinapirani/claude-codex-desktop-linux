# Copyright 2026 Sina Pirani
# Distributed under the terms of the MIT License

# Repackages Anthropic's official Claude Desktop .deb. The .deb is downloaded
# from Anthropic's apt repository; the Manifest hashes come from files whose
# SHA256 matches Anthropic's GPG-signed index (scripts/upstream.sh).

EAPI=8

inherit optfeature unpacker xdg

_REPO="https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop"

DESCRIPTION="Desktop application for Claude.ai (official build, repackaged)"
HOMEPAGE="https://claude.ai/download https://github.com/sinapirani/claude-codex-desktop-linux"
SRC_URI="
	amd64? ( ${_REPO}/claude-desktop_${PV}_amd64.deb )
	arm64? ( ${_REPO}/claude-desktop_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="suid"
RESTRICT="bindist mirror strip test"

RDEPEND="
	app-accessibility/at-spi2-core:2
	app-crypt/libsecret
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/mesa
	media-video/pipewire
	sys-apps/util-linux
	sys-apps/xdg-desktop-portal
	sys-libs/glibc
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libxcb
	x11-libs/libXtst
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_install() {
	cp -a usr "${ED}"/ || die
	rm -r "${ED}"/usr/share/lintian || die
	dodoc usr/share/doc/claude-desktop/copyright
	rm -r "${ED}"/usr/share/doc/claude-desktop || die

	if use suid; then
		fperms 4711 /usr/lib/claude-desktop/chrome-sandbox
	else
		fperms 0755 /usr/lib/claude-desktop/chrome-sandbox
	fi

	# What the Debian postinst sets up at install time
	local res=usr/lib/claude-desktop/resources
	insinto /usr/share/mime/packages
	doins "${res}"/linux-mime/com.anthropic.Claude.xml
	insinto /usr/share/gnome-shell/search-providers
	doins "${res}"/gnome-search-provider/com.anthropic.Claude.search-provider.ini
	insinto /usr/share/dbus-1/services
	doins "${res}"/gnome-search-provider/com.anthropic.Claude.SearchProvider.service

	# Cowork looks for UEFI firmware only at Debian's paths. Gentoo's edk2
	# ships the 4M image only as qcow2, so point the app's 2M fallback names
	# at the raw OvmfX64 images. (arm64: edk2 ships qcow2 only; not linked.)
	if use amd64; then
		dosym -r /usr/share/edk2/OvmfX64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd
		dosym -r /usr/share/edk2/OvmfX64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	optfeature "staying signed in (secret storage)" gnome-base/gnome-keyring kde-frameworks/kwallet-runtime
	optfeature "file chooser dialogs" sys-apps/xdg-desktop-portal-gtk kde-plasma/xdg-desktop-portal-kde
	optfeature "the tray icon" dev-libs/libayatana-appindicator
	optfeature "sandboxed Claude Code sessions" sys-apps/bubblewrap
	optfeature "SSH remote sessions" net-misc/openssh
	use amd64 && optfeature "Cowork (local VM)" "app-emulation/qemu sys-firmware/edk2-bin"
}
