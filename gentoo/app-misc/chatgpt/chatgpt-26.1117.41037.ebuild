# Copyright 2026 Sina Pirani
# Distributed under the terms of the MIT License

# Repackages OpenAI's official Codex desktop app (package "chatgpt") .deb. The
# .deb is downloaded from OpenAI's apt repository; the Manifest hashes come
# from files whose SHA256 matches OpenAI's GPG-signed index
# (scripts/upstream.sh).

EAPI=8

inherit optfeature unpacker xdg

_REPO="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt"

DESCRIPTION="Codex desktop app by OpenAI (official ChatGPT build, repackaged)"
HOMEPAGE="https://developers.openai.com/codex/app https://github.com/sinapirani/claude-codex-desktop-linux"
SRC_URI="
	amd64? ( ${_REPO}/chatgpt_${PV}_amd64.deb )
	arm64? ( ${_REPO}/chatgpt_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip test"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46:2
	app-arch/xz-utils
	app-crypt/tpm2-tss
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/libusb:1
	dev-libs/nspr
	dev-libs/nss
	>=dev-libs/openssl-3:0
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	virtual/libudev
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_install() {
	# Only usr/: etc/ holds just an AppArmor profile for Ubuntu.
	cp -a usr "${ED}"/ || die
	rm -r "${ED}"/usr/share/lintian || die
	dodoc usr/share/doc/chatgpt/copyright
	rm -r "${ED}"/usr/share/doc/chatgpt || die
}

pkg_postinst() {
	xdg_pkg_postinst
	optfeature "version control for Codex projects" dev-vcs/git
	optfeature "staying signed in (secret storage)" gnome-base/gnome-keyring kde-frameworks/kwallet-runtime
	optfeature "file chooser dialogs" sys-apps/xdg-desktop-portal-gtk kde-plasma/xdg-desktop-portal-kde
}
