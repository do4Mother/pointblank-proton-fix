#!/usr/bin/env bash
# Installs "proton-cachyos-pbfix": the official proton-cachyos 11.0-20261005-slr
# release with two patched DLLs that fix the Point Blank (ID) crashes on Linux.
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

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
sha1() { sha1sum "$1" | cut -d' ' -f1; }

for c in curl tar sha1sum sha512sum xz; do
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

install -m 755 "$work/ntdll.dll" "$src/$NTDLL_REL"
install -m 755 "$work/d3d11.dll" "$src/$D3D11_REL"

# give it its own name in Steam/Heroic lists
if [ -f "$src/compatibilitytool.vdf" ]; then
    sed -i -e "s/\"proton-cachyos-11.0-20261005-slr-x86_64\" \/\/ Internal name/\"$NAME\" \/\/ Internal name/" \
           -e "s/\"display_name\" \"[^\"]*\"/\"display_name\" \"$NAME (Point Blank fix)\"/" "$src/compatibilitytool.vdf"
fi

rm -rf "$dest"
mv "$src" "$dest"

[ "$(sha1 "$dest/$NTDLL_REL")" = "$NTDLL_NEW" ] && [ "$(sha1 "$dest/$D3D11_REL")" = "$D3D11_NEW" ] \
    || die "post-install verification failed"

msg "Installed: $dest"
cat <<EOF

Next steps:
  Heroic: restart Heroic -> Point Blank -> Settings -> Wine version -> "$NAME"
  Steam : restart Steam  -> game Properties -> Compatibility -> "$NAME (Point Blank fix)"

Uninstall: curl -fsSL $REPO_RAW/install.sh | bash -s -- --uninstall
EOF
