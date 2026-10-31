#!/usr/bin/env bash
# Sanity-check an installed (or unpacked) Claude Desktop tree. Used by CI after
# installing each distro's package.
#
# Usage: tests/check-install.sh [ROOT]          (default ROOT=/)
#   CHECK_LIBS=0      skip the "every shared library resolves" check
#   CHECK_FIRMWARE=1  also require Cowork's QEMU + UEFI firmware paths to resolve
set -uo pipefail
root=${1:-/}
root=${root%/}
lib="$root/usr/lib/claude-desktop"
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

echo "== files"
for f in usr/bin/claude-desktop \
         usr/lib/claude-desktop/claude-desktop \
         usr/lib/claude-desktop/resources/app.asar \
         usr/share/applications/com.anthropic.Claude.desktop \
         usr/share/icons/hicolor/256x256/apps/claude-desktop.png \
         usr/share/mime/packages/com.anthropic.Claude.xml; do
  if [[ -e "$root/$f" ]]; then ok "$f"; else bad "missing $f"; fi
done
[[ -x "$lib/claude-desktop" ]] || bad "claude-desktop is not executable"

if [[ "${CHECK_LIBS:-1}" == 1 ]]; then
  echo "== shared libraries"
  while IFS= read -r -d '' f; do
    file -b "$f" | grep -q 'dynamically linked' || continue
    missing=$(LD_LIBRARY_PATH="$lib" ldd "$f" 2>&1 | grep 'not found' || true)
    if [[ -n "$missing" ]]; then bad "${f#"$root"}:"$'\n'"$missing"; fi
  done < <(find "$lib" -type f \( -perm -u+x -o -name '*.so*' -o -name '*.node' \) -print0)
  (( fail )) || ok "all dynamic ELF files resolve their libraries"
fi

if [[ "${CHECK_FIRMWARE:-0}" == 1 ]]; then
  echo "== Cowork VM paths (hardcoded Debian paths the app looks for)"
  # x86_64: the app tries OVMF_CODE_4M.fd first, then OVMF_CODE.fd (2M), and
  # derives the VARS path from whichever CODE file it picked.
  case "$(uname -m)" in
    x86_64)
      if [[ -e "$root/usr/share/OVMF/OVMF_CODE_4M.fd" ]]; then s=_4M; else s=; fi
      paths=(/usr/bin/qemu-system-x86_64 "/usr/share/OVMF/OVMF_CODE$s.fd" "/usr/share/OVMF/OVMF_VARS$s.fd") ;;
    aarch64) paths=(/usr/bin/qemu-system-aarch64 /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/AAVMF/AAVMF_VARS.fd) ;;
  esac
  for p in "${paths[@]}"; do
    if t=$(readlink -e "$root$p"); then ok "$p -> $t"; else bad "$p does not resolve"; fi
  done
fi

if (( fail )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: OK"
