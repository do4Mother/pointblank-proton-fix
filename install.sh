#!/usr/bin/env bash
# Installs "proton-cachyos-pbfix": the official proton-cachyos 11.0-20261005-slr
# release with two patched DLLs and a byte-patched ntdll.so that fix the
# Point Blank (ID) crashes on Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/do4Mother/pointblank-proton-fix/main/install.sh | bash
#
# Options:  --heroic | --steam | --dir <path> | --uninstall
set -euo pipefail

REPO_RAW="${PBFIX_REPO_RAW:-https://raw.githubusercontent.com/do4Mother/pointblank-proton-fix/main}"
TAG="cachyos-11.0-20261005-slr"
TARBALL="proton-cachyos-11.0-20261005-slr-x86_64.tar.xz"
RELEASE_URL="${PBFIX_RELEASE_URL:-https://github.com/CachyOS/proton-cachyos/releases/download/${TAG}}"
TARBALL_URL="${RELEASE_URL}/${TARBALL}"
SUM_URL="${RELEASE_URL}/proton-cachyos-11.0-20261005-slr-x86_64.sha512sum"
NAME="proton-cachyos-pbfix"

# sha1: original file in the release -> patched file from this repo
NTDLL_REL="files/lib/wine/i386-windows/ntdll.dll"
NTDLL_ORIG="21e0a301011e7c12e7012f257d6b7c339cb76e98"
NTDLL_NEW="f711607fda0c6be1363de328efa3a18875e9ee53"
D3D11_REL="files/lib/wine/dxvk/i386-windows/d3d11.dll"
D3D11_ORIG="62220b85e6d32bceea4da5a5d74cec9af994340e"
D3D11_NEW="0acf5a46885246884a8f3b8d539d17b8ba4bde13"

# ntdll.so address-space cap (see patches/patch_ntdll_so_addr_cap.py):
# file offset, original bytes, patched bytes, sha1 before -> after
NTSO32_REL="files/lib/wine/i386-unix/ntdll.so"
NTSO32_OFF=$((0x99b1e)); NTSO32_FROM="8b8368100000"; NTSO32_TO="b80000fcff90"
NTSO32_ORIG="23f0745fa5ef9f3b39ced2c6211eb236a68f70e1"
NTSO32_NEW="576c2f2b460b9fa83aa21f5e8a12d0028b74f4a9"
NTSO64_REL="files/lib/wine/x86_64-unix/ntdll.so"
NTSO64_OFF=$((0x9aeeb)); NTSO64_FROM="b8ffffffff"; NTSO64_TO="b8fffffbff"
NTSO64_ORIG="8d1c0f3d8cec3dae5472f94d8337b6728aebe703"
NTSO64_NEW="27cc7094a4da326fe7f0c35bea969d8c4f601ea8"

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
sha1() { sha1sum "$1" | cut -d' ' -f1; }
hexat() { od -An -v -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'; }
# bytepatch <file> <offset> <expected-hex> <new-hex>
bytepatch() {
    [ "$(hexat "$1" "$2" $(( ${#3} / 2 )))" = "$3" ] || die "unexpected bytes in $1"
    printf "$(printf '%s' "$4" | sed 's/../\\x&/g')" |
        dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}

for c in curl tar sha1sum sha512sum xz od dd; do
    command -v "$c" >/dev/null || die "missing command: $c"
done

# --- pick install directory -------------------------------------------------
heroic_dirs=("$HOME/.config/heroic/tools/proton"
             "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/proton")
steam_dirs=("$HOME/.steam/root/compatibilitytools.d"
            "$HOME/.local/share/Steam/compatibilitytools.d"
            "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d")

first_existing_parent() {
    for d in "$@"; do [ -d "$(dirname "$d")" ] && { echo "$d"; return; }; done
}

mode="auto"; dest_root=""
while [ $# -gt 0 ]; do
    case "$1" in
        --heroic) mode=heroic ;;
        --steam) mode=steam ;;
        --dir) shift; dest_root="${1:?--dir needs a path}"; mode=dir ;;
        --uninstall) mode=uninstall ;;
        -h|--help) sed -n '2,9p' "$0" 2>/dev/null || true; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

if [ "$mode" = uninstall ]; then
    for d in "${heroic_dirs[@]}" "${steam_dirs[@]}"; do
        [ -d "$d/$NAME" ] && { rm -rf "${d:?}/$NAME"; msg "removed $d/$NAME"; }
    done
    exit 0
fi

case "$mode" in
    heroic) dest_root="$(first_existing_parent "${heroic_dirs[@]}")" ;;
    steam)  dest_root="$(first_existing_parent "${steam_dirs[@]}")" ;;
    auto)   dest_root="$(first_existing_parent "${heroic_dirs[@]}")"
            [ -n "$dest_root" ] || dest_root="$(first_existing_parent "${steam_dirs[@]}")" ;;
esac
[ -n "$dest_root" ] || die "no Heroic or Steam install found; use --dir <path>"
mkdir -p "$dest_root"
dest="$dest_root/$NAME"

# --- download & verify ------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

msg "Downloading $TARBALL (~350 MB)"
curl -fL --progress-bar -o "$work/$TARBALL" "$TARBALL_URL"
curl -fsSL -o "$work/sum" "$SUM_URL"
msg "Verifying release checksum"
(cd "$work" && sha512sum -c sum) || die "release checksum mismatch"

msg "Downloading patched DLLs"
curl -fsSL -o "$work/ntdll.dll" "$REPO_RAW/bin/ntdll.dll"
curl -fsSL -o "$work/d3d11.dll" "$REPO_RAW/bin/d3d11.dll"
[ "$(sha1 "$work/ntdll.dll")" = "$NTDLL_NEW" ] || die "ntdll.dll checksum mismatch"
[ "$(sha1 "$work/d3d11.dll")" = "$D3D11_NEW" ] || die "d3d11.dll checksum mismatch"

# --- extract & patch --------------------------------------------------------
msg "Extracting"
tar -xJf "$work/$TARBALL" -C "$work"
src="$work/proton-cachyos-11.0-20261005-slr-x86_64"
[ -d "$src" ] || die "unexpected tarball layout"

[ "$(sha1 "$src/$NTDLL_REL")" = "$NTDLL_ORIG" ] || die "release ntdll.dll is not the expected build"
[ "$(sha1 "$src/$D3D11_REL")" = "$D3D11_ORIG" ] || die "release d3d11.dll is not the expected build"
[ "$(sha1 "$src/$NTSO32_REL")" = "$NTSO32_ORIG" ] || die "release i386 ntdll.so is not the expected build"
[ "$(sha1 "$src/$NTSO64_REL")" = "$NTSO64_ORIG" ] || die "release x86_64 ntdll.so is not the expected build"

install -m 755 "$work/ntdll.dll" "$src/$NTDLL_REL"
install -m 755 "$work/d3d11.dll" "$src/$D3D11_REL"
chmod u+w "$src/$NTSO32_REL" "$src/$NTSO64_REL"
bytepatch "$src/$NTSO32_REL" "$NTSO32_OFF" "$NTSO32_FROM" "$NTSO32_TO"
bytepatch "$src/$NTSO64_REL" "$NTSO64_OFF" "$NTSO64_FROM" "$NTSO64_TO"
chmod a-w "$src/$NTSO32_REL" "$src/$NTSO64_REL"

# give it its own name in Steam/Heroic lists
if [ -f "$src/compatibilitytool.vdf" ]; then
    sed -i -e "s/\"proton-cachyos-11.0-20261005-slr-x86_64\" \/\/ Internal name/\"$NAME\" \/\/ Internal name/" \
           -e "s/\"display_name\" \"[^\"]*\"/\"display_name\" \"$NAME (Point Blank fix)\"/" "$src/compatibilitytool.vdf"
fi

rm -rf "$dest"
mv "$src" "$dest"

[ "$(sha1 "$dest/$NTDLL_REL")" = "$NTDLL_NEW" ] && [ "$(sha1 "$dest/$D3D11_REL")" = "$D3D11_NEW" ] \
    && [ "$(sha1 "$dest/$NTSO32_REL")" = "$NTSO32_NEW" ] && [ "$(sha1 "$dest/$NTSO64_REL")" = "$NTSO64_NEW" ] \
    || die "post-install verification failed"

msg "Installed: $dest"
cat <<EOF

Next steps:
  Heroic: restart Heroic -> Point Blank -> Settings -> Wine version -> "$NAME"
  Steam : restart Steam  -> game Properties -> Compatibility -> "$NAME (Point Blank fix)"

Uninstall: curl -fsSL $REPO_RAW/install.sh | bash -s -- --uninstall
EOF
