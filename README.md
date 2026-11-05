# Point Blank (Indonesia) on Linux: Proton fix

Since the **Oct 13 2026 update** (the new DX11 lighting), Point Blank ID crashes on Linux/Proton
during loading, at fade-in, or right after joining a room. Some launches also freeze at startup.
This repo installs a patched **proton-cachyos 11.0-20261005-slr** that fixes all three crashes.

## Install (one command)

```sh
curl -fsSL https://raw.githubusercontent.com/do4Mother/pointblank-proton-fix/main/install.sh | bash
```

Then **restart Heroic** (or Steam) and set the game's Wine/Proton version to **`proton-cachyos-pbfix`**.

The installer:
1. downloads the official proton-cachyos release from CachyOS's GitHub and checks its SHA-512,
2. replaces exactly two 32-bit DLLs with the patched ones from `bin/`, checking the SHA-1 of both the original and the patched file,
3. changes one instruction in each `ntdll.so` (32- and 64-bit), checking the original bytes and the SHA-1 before and after,
4. installs the result as `proton-cachyos-pbfix` in Heroic's tools folder. If Heroic isn't installed, it uses Steam's `compatibilitytools.d`.

It doesn't touch your system Proton, game files or prefix.

Options:

```sh
... | bash -s -- --heroic          # force Heroic (~/.config/heroic/tools/proton, Flatpak supported)
... | bash -s -- --steam           # force Steam (compatibilitytools.d)
... | bash -s -- --dir <path>      # custom directory
... | bash -s -- --uninstall
```

> **Use `proton-cachyos-pbfix` every time.** Proton copies its own `d3d11.dll` into the prefix
> on every launch, so launching once with another Proton is fine. The fix comes back as soon as
> you switch back.

## What was wrong

### Crash 1: `PointBlank.exe+0x28C23E` (`0x68C23E`), random, during loading

The updated exe has a `thread_local` object with `alignas(16)`, initialized with SSE `movaps`.
Its TLS directory requests 16-byte alignment (`Characteristics = IMAGE_SCN_ALIGN_16BYTES`).
Windows honors that, but Wine's loader allocates TLS blocks with plain `RtlAllocateHeap`
(8-byte aligned on 32-bit). When a block lands misaligned, `movaps` faults. Windows reports
that as an access violation at `0xFFFFFFFF`.

**Fix:** `ntdll.dll` (32-bit). `alloc_tls_memory()` now honors the TLS directory's
alignment. Source: [`patches/ntdll-tls-alignment.patch`](patches/ntdll-tls-alignment.patch), against
[CachyOS/wine-cachyos@2ce6b44](https://github.com/CachyOS/wine-cachyos/commit/2ce6b44caa66a56ec99c7826ae564c088abc1b9f)
(the wine commit of proton-cachyos `cachyos-11.0-20261005-slr`). Only the PE `ntdll.dll` was rebuilt.

### Crash 2: `d3d11.dll+0x1000BE`, at fade-in or after joining a room

The game's `i3GfxDX11DeferredContext` sometimes calls `ExecuteCommandList(NULL)` on the
immediate context, before its deferred recording job has produced a command list.
DXVK dereferences the pointer without a NULL check.

**Fix:** DXVK `d3d11.dll` (32-bit). A NULL command list now makes the call return.
It's a 13-byte binary patch: a `cmp [esp+8],0 / je ret` guard in existing padding, with the
vtable entry pointed at it. Reproducible with
[`patches/patch_d3d11_null_cmdlist.py`](patches/patch_d3d11_null_cmdlist.py).

### Crash 3: startup freeze, `write access to 001A0008 at address 00456311` (intermittent)

The game hangs right after launch (the crashed process is held by `winedbg`). The game's
memory pool does `VirtualAlloc(NULL, 0x10000, MEM_COMMIT|MEM_RESERVE|MEM_TOP_DOWN)`. It then splits
the block into `0x40000` steps without an overflow check. The exe is large-address-aware, so Wine
may place that block at `0xFFFE0000`, the top of the 4 GB space. `0xFFFE0000 + 0x40000` then wraps to
`0x00020000`, and the loop writes chunk headers across low memory until it hits Wine's read-only
`c_437.nls` mapping at `0x1A0000`. It only happens when the topmost 64 KB slot is still free at
that moment, so some launches work and others freeze.

**Fix:** `ntdll.so` (Unix side). The highest user address for 32-bit large-address-aware processes
is capped at `0xFFFC0000`, so a top-down allocation can't land close enough to 4 GB to overflow.
It's one instruction in `virtual_set_large_address_space()` in both `i386-unix/ntdll.so` (classic
32-bit mode, Heroic's default) and `x86_64-unix/ntdll.so` (WoW64 mode). The game exe isn't touched.
Reproducible with [`patches/patch_ntdll_so_addr_cap.py`](patches/patch_ntdll_so_addr_cap.py).
`WINE_LARGE_ADDRESS_AWARE=0` doesn't help, because the exe itself is flagged large-address-aware.

## Checksums

| file | original (release) SHA-1 | patched SHA-1 |
|---|---|---|
| `files/lib/wine/i386-windows/ntdll.dll` | `21e0a301011e7c12e7012f257d6b7c339cb76e98` | `f711607fda0c6be1363de328efa3a18875e9ee53` |
| `files/lib/wine/dxvk/i386-windows/d3d11.dll` | `62220b85e6d32bceea4da5a5d74cec9af994340e` | `0acf5a46885246884a8f3b8d539d17b8ba4bde13` |
| `files/lib/wine/i386-unix/ntdll.so` | `23f0745fa5ef9f3b39ced2c6211eb236a68f70e1` | `576c2f2b460b9fa83aa21f5e8a12d0028b74f4a9` |
| `files/lib/wine/x86_64-unix/ntdll.so` | `8d1c0f3d8cec3dae5472f94d8337b6728aebe703` | `27cc7094a4da326fe7f0c35bea969d8c4f601ea8` |

The patched files only work with **proton-cachyos 11.0-20261005-slr**. Don't copy them into other Proton versions.

## Licenses

- `bin/ntdll.dll` is a **modified** build of Wine (LGPL-2.1-or-later). The full change is in
  `patches/ntdll-tls-alignment.patch`. The complete source is the wine-cachyos commit above, plus that patch.
- `ntdll.so` (patched by `install.sh`, not shipped here) is a **modified** Wine binary
  (LGPL-2.1-or-later). The change is the one-instruction edit described above, applied to the official release.
- `bin/d3d11.dll` is a **modified** binary of [DXVK](https://github.com/doitsujin/dxvk)
  (zlib license, © Philip Rebohle and contributors). It's an altered version, not the original release.
- `install.sh` and the files in `patches/`: MIT, see [LICENSE](LICENSE).

This project isn't affiliated with Zepetto, CachyOS, Valve, Wine or DXVK. It comes with no warranty.
