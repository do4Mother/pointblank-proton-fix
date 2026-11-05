#!/usr/bin/env python3
"""
Cap the highest user address Wine hands to 32-bit large-address-aware processes
at 0xFFFC0000 (instead of the top of the 4 GB space).

Why: PointBlank.exe's memory pool (fn 0x456290) does
    mem = VirtualAlloc(NULL, 0x10000, MEM_COMMIT|MEM_RESERVE|MEM_TOP_DOWN, PAGE_READWRITE)
and then walks the block in 0x40000 steps. When Wine places the block at
0xFFFE0000, `mem + 0x40000` wraps to 0x00020000 and the loop writes chunk headers
across low memory until it hits a read-only mapping:
    Unhandled page fault on write access to 001A0008 at address 00456311
It is intermittent because it only happens when the topmost 64K slot is still free.

Two one-instruction patches in virtual_set_large_address_space():
  i386-unix/ntdll.so   (classic 32-bit Wine process; Heroic default, WoW64 off)
      mov 0x1068(%ebx),%eax  ->  mov $0xfffc0000,%eax ; nop   (user_space_limit)
  x86_64-unix/ntdll.so (new WoW64 mode)
      mov $0xffffffff,%eax   ->  mov $0xfffbffff,%eax         (user_space_wow_limit)

Target: proton-cachyos 11.0-20261005-slr. Any other build is refused (SHA1 check).

Usage: python3 patch_ntdll_so_addr_cap.py /path/to/proton/files/lib/wine
Backups are written next to each file as ntdll.so.orig.
"""
import hashlib, os, shutil, sys

PATCHES = [
    # (relative path, file offset, original bytes, new bytes, sha1 before, sha1 after)
    ("i386-unix/ntdll.so", 0x99b1e, "8b8368100000", "b80000fcff90",
     "23f0745fa5ef9f3b39ced2c6211eb236a68f70e1", "576c2f2b460b9fa83aa21f5e8a12d0028b74f4a9"),
    ("x86_64-unix/ntdll.so", 0x9aeeb, "b8ffffffff", "b8fffffbff",
     "8d1c0f3d8cec3dae5472f94d8337b6728aebe703", "27cc7094a4da326fe7f0c35bea969d8c4f601ea8"),
]

def patch(path, off, old, new, sha_old, sha_new):
    data = bytearray(open(path, "rb").read())
    sha = hashlib.sha1(data).hexdigest()
    if sha == sha_new:
        print(f"{path}: already patched"); return
    if sha != sha_old:
        sys.exit(f"{path}: unexpected build (sha1 {sha}); refusing to patch")
    old, new = bytes.fromhex(old), bytes.fromhex(new)
    assert data[off:off + len(old)] == old, "bytes at patch offset don't match"
    data[off:off + len(new)] = new
    assert hashlib.sha1(data).hexdigest() == sha_new
    shutil.copy2(path, path + ".orig")
    tmp = path + ".new"  # write a new inode so running processes keep the old mapping
    open(tmp, "wb").write(data)
    os.chmod(tmp, 0o555)
    os.replace(tmp, path)
    print(f"{path}: patched")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for rel, *args in PATCHES:
        patch(os.path.join(sys.argv[1], rel), *args)
