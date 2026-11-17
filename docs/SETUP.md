# Setup, in detail

The steps, what each one costs, and the traps. `scripts/setup.sh` does all of them; this is what it does and why.

## 0. What you need

- A copy of the game: a folder with `exefs/` and `romfs/`, dumped from your own Switch 2 and decrypted (1.8.0 with
  the update merged into the base game's RomFS). A `.nup`/`.nx` works too — the port reads it.
- `git`, `uv` (https://github.com/astral-sh/uv), a C compiler, ninja, and Vulkan 1.3.
- x86-64 with AVX2 (or Linux AArch64 with ARMv8.2: LSE, FP16, RCpc, DotProd, CRC32).
- ~35 GB free: the game copy, the build (about 3 GB) and the shaders.

## 1. The upstream

```bash
git submodule update --init --recursive
```

It is pinned to the commit in `.upstream-sha`. `scripts/upstream-check.sh` shows how far behind it is and merges a
new one.

## 2. The game copy

```bash
MKW_DUMP=/mnt/Data/mkw-dump scripts/setup.sh --game
```

This links `exefs/` and `romfs/` into `upstream/game/` and points `upstream/game/spirv` at the prepared SPIR-V.

**The game dir is the port's installation dir, and it matters.** The prepared SPIR-V, the pipeline cache and the
settings all live there — *not* next to the binary. If they are missing, the boot's pipeline prewarm finds no shader:

```
gfx_shader: prewarm: 1299 shaders named by pipeline keys, 1299 not found, on 17 threads
vk_pipeline: prewarm: 1038 records ...: 0 pipelines built, 0 failed, 0 already built,
             1038 dropped (shader not loaded)
```

and **every pipeline is built in play — the mid-race stops**. With them in place:

```
vk_pipeline: prewarm: 1038 records ...: 1038 pipelines built, 0 failed, 0 dropped
```

in about 1.4 s, before the guest starts. The key file grows with use (1,038 → 1,541 → 1,861 records over three
runs here), so a course stops stalling on its pipelines after it has been seen.

## 3. The romfs on the fast disk

```bash
scripts/setup.sh --romfs-local
```

The romfs is **206,202 small files**. On a slow mount the world map's first frame spent **39.5 s** recording while it
streamed ~5.5 GB of them, and the map ran at 3-8 fps; the same map on the NVMe runs at the full 60 fps. The copy is
23,483,877,087 bytes; `scripts/check-romfs-copy.sh` verifies the file count, the byte total and a hash sample against
the dump.

## 4. The build

```bash
scripts/setup.sh --build
```

Four steps, in order (each is idempotent):

| Step | What | Cost here |
|---|---|---|
| `sm86/spec/spec.py` | fetches NVIDIA's `nvdisasm` and `ptxas` (CUDA 12.8, 84 MB, pinned by sha256) and builds the SM86 specification the decoder reads | ~1 min |
| `recomp/gen.py` | the game's AArch64 code → C: 245,653 functions, 391 chunks, 977 MB of C, **0 unsupported instructions** | ~1 min at 16 jobs |
| `tools/shaders/extract.py` + `translate.py` | the SM86 shaders → SPIR-V: **11,604 programs, 11,604 valid (100%)** | ~15 min |
| `tools/build/build.py` | the runtime: 662 steps, the 245 MB `build/mkw` | ~6 min at 8 jobs |

The 1.8.0 patch set is `recomp/patches-mkw-180.txt`; a 1.0.0 dump wants `recomp/patches-mkw.txt`.

Check the dump is the version you think before the long steps:

```bash
cd upstream && uv run recomp/versions.py "$MKW_DUMP/exefs"
# Mario Kart World 1.8.0 (version 180), modules main, subsdk0, subsdk1, sdk, patches patches-mkw-180.txt
```

It reads the build id of `exefs/main` and checks the RomFS's file count against that version's (206,202 for 1.8.0).

## 5. Run it

```bash
./run-mkw-180.sh            # until the window is closed
./run-mkw-180.sh 90 shot.png
```

The settings come from `config/mkw-tune.env`; extra `MKW_*` in the environment win over the file.

## Traps

- **The mouse.** `MOUSE_SENS` defaults to **1**, so the game grabs and hides the pointer (SDL's relative mouse mode).
  `MKW_MOUSE_SENS=0` turns the mouse camera off and with it the grab.
- **`--seconds` never expires without `MKW_SEQ_WATCH=1`.** The world clock it counts is the sequence watcher's,
  which is -1 unless the watcher runs, so the run only ends when the window is closed and the `--shot` is never
  written. With it set, the run ends on game time.
- **`--shot` turns the pipeline prewarm off** in the port ("a --shot image must not depend on build timing"), so a
  timed run must not use it.
- **`MKW_TEX_MAX`/`MKW_TEX_QUALITY` black the road out** on a 12 GB card. See `docs/PERFORMANCE.md`.
- **The VRAM budget moves.** The heap limit is the driver's budget less `MKW_VRAM_MARGIN`, and the budget shrinks
  with whatever else holds VRAM: 10,738 MiB with the desktop quiet, 8,793 MiB with ZBrush open. If the race slows
  down suddenly, check `vk: heap 0 limited to ...` in the log before blaming the renderer.
- **The other emulators on the desktop matter.** The game wants about four cores; the box was at load 6-12 of 16
  during these measurements (amiberry, PBZ.exe, a python at ~4.7 cores), and two runs of the same build differed by
  up to 7 ms a frame because of it.
