#!/usr/bin/env python3
"""
Patch DXVK 32-bit d3d11.dll so ID3D11DeviceContext::ExecuteCommandList(NULL, ...)
on the immediate context returns instead of crashing.

Target: DXVK v3.1.1-47-g685301564ea3486 (i386-windows/d3d11.dll) as shipped in
proton-cachyos 11.0-20261005-slr. Any other build is refused (SHA1 check).

Usage: python3 patch_d3d11_null_cmdlist.py /path/to/i386-windows/d3d11.dll
A backup is written next to it as d3d11.dll.orig.
"""
import hashlib, shutil, struct, sys

ORIG_SHA1    = "62220b85e6d32bceea4da5a5d74cec9af994340e"
PATCHED_SHA1 = "0acf5a46885246884a8f3b8d539d17b8ba4bde13"

IMAGE_BASE   = 0x6a540000
FN_EXECUTE   = 0x6a737820  # D3D11ImmediateContext::ExecuteCommandList
CAVE         = 0x6a737818  # 8 bytes of NOP padding right before it
RET_0C       = 0x6a737806  # existing `ret 0xc` in the previous function
VTABLE_SLOT  = 0x6ea0e0    # file offset of the vtable entry pointing at FN_EXECUTE

def main(path):
    data = bytearray(open(path, "rb").read())
    sha = hashlib.sha1(data).hexdigest()
    if sha == PATCHED_SHA1:
        print("already patched"); return
    if sha != ORIG_SHA1:
        sys.exit(f"unexpected d3d11.dll (sha1 {sha}); refusing to patch")

    pe, = struct.unpack_from("<I", data, 0x3c)
    opt_size, = struct.unpack_from("<H", data, pe + 20)
    sec = pe + 24 + opt_size
    assert data[sec:sec + 5] == b".text"
    _, text_va, _, text_raw = struct.unpack_from("<IIII", data, sec + 8)
    v2f = lambda va: text_raw + va - IMAGE_BASE - text_va

    cave = v2f(CAVE)
    assert data[cave:cave + 8] == b"\x90" * 8
    assert data[v2f(RET_0C):v2f(RET_0C) + 3] == b"\xc2\x0c\x00"
    assert struct.unpack_from("<I", data, VTABLE_SLOT)[0] == FN_EXECUTE

    # cmp dword [esp+8], 0   ; pCommandList == NULL ?
    # je  RET_0C             ; stdcall return, pop 3 args
    # nop                    ; fall through into the original function
    data[cave:cave + 8] = bytes([0x83, 0x7c, 0x24, 0x08, 0x00,
                                 0x74, (RET_0C - (CAVE + 7)) & 0xff, 0x90])
    struct.pack_into("<I", data, VTABLE_SLOT, CAVE)

    assert hashlib.sha1(data).hexdigest() == PATCHED_SHA1
    shutil.copy2(path, path + ".orig")
    open(path, "wb").write(data)
    print("patched OK, backup:", path + ".orig")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
