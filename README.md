# Point Blank (Indonesia) on Linux: Proton fix

Since the **Oct 13 2026 update** (the new DX11 lighting), Point Blank ID crashes on Linux/Proton
during loading, at fade-in, or right after joining a room. This repo installs a patched
**proton-cachyos 11.0-20261005-slr** that fixes both crashes.

## Install (one command)

```sh
curl -fsSL https://raw.githubusercontent.com/do4Mother/pointblank-proton-fix/main/install.sh | bash
```

Then **restart Heroic** (or Steam) and set the game's Wine/Proton version to **`proton-cachyos-pbfix`**.

The installer:
1. downloads the official proton-cachyos release from CachyOS's GitHub and checks its SHA-512,
2. replaces exactly two 32-bit DLLs with the patched ones from `bin/`, checking the SHA-1 of both the original and the patched file,
3. installs the result as `proton-cachyos-pbfix` in Heroic's tools folder. If Heroic isn't installed, it uses Steam's `compatibilitytools.d`.

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

## Checksums

| file | original (release) SHA-1 | patched SHA-1 |
|---|---|---|
| `files/lib/wine/i386-windows/ntdll.dll` | `21e0a301011e7c12e7012f257d6b7c339cb76e98` | `f711607fda0c6be1363de328efa3a18875e9ee53` |
| `files/lib/wine/dxvk/i386-windows/d3d11.dll` | `62220b85e6d32bceea4da5a5d74cec9af994340e` | `0acf5a46885246884a8f3b8d539d17b8ba4bde13` |

The DLLs only work with **proton-cachyos 11.0-20261005-slr**. Don't copy them into other Proton versions.

## Licenses

- `bin/ntdll.dll` is a **modified** build of Wine (LGPL-2.1-or-later). The full change is in
  `patches/ntdll-tls-alignment.patch`. The complete source is the wine-cachyos commit above, plus that patch.
- `bin/d3d11.dll` is a **modified** binary of [DXVK](https://github.com/doitsujin/dxvk)
  (zlib license, © Philip Rebohle and contributors). It's an altered version, not the original release.
- `install.sh` and the files in `patches/`: MIT, see [LICENSE](LICENSE).

This project isn't affiliated with Zepetto, CachyOS, Valve, Wine or DXVK. It comes with no warranty.
