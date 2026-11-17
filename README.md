# Mario Kart World on Linux, native

**Mario Kart World** (Nintendo Switch 2, versions 1.0.0 and 1.8.0) recompiled to run natively on Linux x86-64
(and Linux AArch64).

This is **our setup of [adriadam10/mkw-recomp](https://github.com/adriadam10/mkw-recomp)**, which is the upstream we
depend on: a static recompilation of the game (the Switch 2's AArch64 code becomes C, the NVN2 graphics API is
reimplemented over Vulkan, the SM86 shaders become SPIR-V ahead of time). It is a recompilation, not an emulator:
there is no CPU interpreter or JIT, and no emulation below the graphics API.

What is ours here is the **setup, the tuning and the measurements** — the game copy, the build on this machine, the
settings that make a 24-kart race run at 47 fps instead of 30, and the traps that cost hours to find. The upstream
code is not forked or copied; it is the `upstream/` submodule, pinned to the commit in `.upstream-sha`.

```
upstream/        adriadam10/mkw-recomp, as a submodule (the game, the runtime, the build)
config/          our tuned settings, in one place
scripts/         the setup, the upstream tracker, the race rigs
docs/            how to set it up, and what it measures
run-mkw-180.sh   the runner
```

## Quick start

```bash
git clone --recurse-submodules https://github.com/CrownParkComputing/mkw-recomp.git
cd mkw-recomp
MKW_DUMP=/path/to/your/dump scripts/setup.sh --build --romfs-local
./run-mkw-180.sh
```

`MKW_DUMP` is your own copy of the game: a folder with `exefs/` and `romfs/` (or a `.nup`/`.nx` the port can read).
**Nothing of the game is in this repository** — no dumps, no assets, no generated code.

The build takes a while the first time (the game code, then the shaders, then the runtime: about half an hour with
a warm CUDA cache), and seconds after that. `scripts/setup.sh` is idempotent: re-run it after the upstream moves.

## The game copy

The port wants the game's own files, and it wants them in the **game dir** (`upstream/game/`): the prepared SPIR-V, the
pipeline cache and the settings live there, **not** next to the binary. That is the single most expensive mistake
this setup makes possible — with the game dir pointing somewhere else, the boot's pipeline prewarm finds no shader and
builds nothing ("`1038 dropped (shader not loaded)`"), and **every pipeline is built in play, mid-race**.

`scripts/setup.sh` wires it:

| In the game dir | What it is |
|---|---|
| `exefs/`, `romfs/` | links to your dump |
| `romfs-local/` | an optional copy of the romfs on the fast disk (see below) |
| `spirv/` | a link to the prepared SPIR-V (11,604 programs, translated once) |
| `pipeline-cache.bin`, `pipeline-keys.bin` | the Vulkan pipeline cache and the pipeline states, pre-built at boot |
| `cache/`, `logs/` | the resolution overlay and the log |

**Put the romfs on the fast disk.** The dump's own mount is slow for the romfs's 206,202 small files: with it the
world map's first frame spent **39.5 s** recording while it streamed ~5.5 GB of textures, and the map ran at 3-8 fps.
Copied to the NVMe (23,483,877,087 bytes, verified identical by `scripts/check-romfs-copy.sh`) the same map runs at
the full 60 fps.

## Settings, and why

`config/mkw-tune.env` holds them; the comments say what each one is worth. The measured race (24 karts, median over
thousands of race frames on an RTX 3060):

| Setting | ms | fps | frames at a locked 60 |
|---|---|---|---|
| the upstream's defaults (720 lines) | 33.3 | 30.0 | 0.6% |
| `MKW_REPLAY_PAR_HEAD=0` | 21.1 | 47.3 | 7.0% |
| `MKW_MIRROR_GAP=8` | 19.1 | 52.3 | 13.1% |
| `MKW_RESOLUTION=540` | 19.4 | 51.5 | 7.7% |
| **all three (our default)** | 21.0 | **47.5** | **22.9%** |

And the ones that look helpful and are not:

- **`MKW_TEX_MAX=1024` and `MKW_TEX_QUALITY=half` black the road out.** In a race the track renders with no surface
  at all — the scenery, the HUD and the karts are fine, the road is solid black. They exist to fit a smaller card; on
  a 12 GB one the race uses 8.3 GB of the 10.4 GB heap limit with them off.
- **`MKW_ONE_PER_CORE=1` hurts when combined with the resolution** (37 fps): pinning the process to one thread per
  physical core takes the recording's chunk threads their parallelism. On its own it is worth +18%.
- **`--shot` turns the pipeline prewarm off** in the port ("a --shot image must not depend on build timing"), so never
  measure a timed run with it.

`docs/PERFORMANCE.md` has the measurements and what the frame time is made of.

## 60 fps in a race

**The race is CPU-bound, not GPU-bound.** The GPU sits at 41% while the frame is 27 ms, and the port's own scheduler
census says the guest threads are not starved (core-wait 0-2%, wake-to-run 9-13 us): the main thread spends 30% of its
frame inside host calls — the recording — and the rest waiting on the game's own workers. The frame is a serial chain
(game → recording → GPU → completion), and the recording is the long link in it.

That is the upstream's own open roadmap item #1 (*"60 fps in races: the serial frame"*), and their faster test
machine does not manage it either. **60 fps in a race is not a setting**; our settings take a 24-kart race from 30 to
47-52 fps, and to a locked 60 fps in its lighter stretches. Closing the rest needs the recording to cost less CPU,
which is work in the upstream.

The menus, the world map and the title run at a full 60 fps.

## The upstream

`scripts/upstream-check.sh` shows how far we are behind and merges:

```bash
scripts/upstream-check.sh              # pinned vs the upstream's main
scripts/upstream-check.sh --merge --rebuild
scripts/upstream-check.sh --mark       # record a commit you picked yourself
```

The upstream ships releases daily, so a merge is usually: the game code regenerated, the shaders retranslated, the
runtime rebuilt (`--rebuild` does all three). Our settings are ours and do not change with it.

## Licence

Our code (this repository) is MIT. The upstream is MIT too, and stays under its own licence in `upstream/`. The game
itself is Nintendo's, and is not here.

## What is where

- `upstream/` — the submodule: `recomp/` (the lifter), `runtime/` (the console's replacement), `sm86/` (the shader
  translator), `tools/` (the build and the game-running rigs), `docs/` (the upstream's own documentation, including
  its [roadmap](upstream/docs/roadmap.md) and [performance notes](upstream/docs/performance.md)).
- `scripts/setup.sh` — the upstream, the game copy and the build.
- `scripts/upstream-check.sh` — the upstream tracker.
- `scripts/measure-race.sh`, `scripts/ab-race.sh` — the race measurement rigs.
- `scripts/check-romfs-copy.sh` — the romfs copy's check.
- `config/mkw-tune.env` — our settings.
- `docs/SETUP.md` — the setup in detail, with the traps.
- `docs/PERFORMANCE.md` — the measurements.
