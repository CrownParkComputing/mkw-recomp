# Performance

What the race frame is made of, what the settings are worth, and where the wall is.

Measured here on an **RTX 3060 (12 GB)** and a **Ryzen 7 3700X** (8 cores, 16 threads), Linux, at 540 or 720 lines
internal, with the game copy on the NVMe and the pipeline cache warm. The port's own tooling does the measuring
(`scripts/measure-race.sh`, `scripts/ab-race.sh`); the upstream's own notes are in `upstream/docs/performance.md`
and its open work in `upstream/docs/roadmap.md`.

## The measure

The attract demo races by itself (24 karts), so a race needs no menu driving. The run is measured from the
`IsSequenceFlag` node (where a race starts) and ends 30 s later. The numbers below are the **median over the race's
frames** — a race's own stretches vary by a third (the grid, the open track, a wall), and two runs of the same build
differ by up to 7 ms here because the desktop carries other emulators, so a single run or a single frame says
nothing.

## Where the frame time goes

The race is **CPU-bound, not GPU-bound**. With the GPU at 41% and the frame at 27 ms, the port's own scheduler
census (`MKW_TRACE=sched`) says:

- the guest threads are **not** starved: core-wait 0-2%, wake-to-run 9-13 us, core grant 4.6-6.5 us;
- the main thread spends **30% of its frame inside host calls** — the recording — and 41% waiting on the game's own
  workers, which are themselves 74% idle waiting for work;
- the host-time census counts **6.5 M memcpy calls and 1.35 M `nvnCommandBufferCallCommands` calls** per 16.7 s.

The frame is a serial chain — the game runs its frame, the Vulkan back end records that submit into command
buffers, the GPU runs what was submitted, and only then does the next frame start. The recording is the long link in
it, and **it is the upstream's open roadmap item #1** ("60 fps in races: the serial frame"). Their own faster test
machine (a Radeon 660M) measures 31-33 ms a race frame; this one measures 27.

So: the GPU is not the limit, the pixels are not the limit, and the game is not waiting for a core.

## The settings

| Setting | ms | fps | frames at a locked 60 |
|---|---|---|---|
| the upstream's defaults (720 lines) | 33.3 | 30.0 | 0.6% |
| `MKW_REPLAY_PAR_HEAD=0` | 21.1 | 47.3 | 7.0% |
| `MKW_MIRROR_GAP=8` | 19.1 | 52.3 | 13.1% |
| `MKW_RESOLUTION=540` | 19.4 | 51.5 | 7.7% |
| `MKW_RESOLUTION=540 MKW_REPLAY_PAR_HEAD=0` | 21.3 | 46.9 | — |
| **all three (our default)** | 21.0 | **47.5** | **22.9%** |

What each one does:

- **`MKW_RESOLUTION=540`** (960x540 instead of 1280x720) — the GPU's share is on the serial chain, so less of it
  shortens the frame. At **480 lines the race holds a locked 16.667 ms in its lighter stretches**.
- **`MKW_MIRROR_GAP=8`** — the guest's memory is mirrored into VRAM, and the frame was making ~106 GPU round trips
  for it (245 syncs, 136 write-back ranges, 13.7 MiB written back a frame). Pools this many 2 MiB regions apart
  share one query, so there are fewer.
- **`MKW_REPLAY_PAR_HEAD=0`** — the recording's first 256 draws were recorded serially on the replay thread before
  the chunks start; the chunks are handed out as the walk goes, so the GPU can start earlier.

They do not simply add: each shortens the same wait.

## What does not help

| Setting | Result |
|---|---|
| `MKW_TEX_MAX=1024`, `MKW_TEX_QUALITY=half` | **the road renders solid black** in a race. They cut the big terrain and course textures to fit a smaller card; on a 12 GB card the race uses 8.3 GB of the 10.4 GB heap limit without them. |
| `MKW_ONE_PER_CORE=1` | +18% on its own (44.0 fps), but **-10% combined with the resolution** (37.2 fps): pinning the process to one thread per physical core takes the recording's chunk threads their parallelism. |
| `MKW_REPLAY_PAR_THREADS=6` | the upstream already picks 3 chunk threads on a machine this size; more did not move the frame. |
| `MKW_GPU_CRUMBS=0` | no measurable change (the breadcrumbs are on the GPU's timeline, not the CPU's frame). |
| `MKW_FPS=60` | pins the game to 60 Hz (the console's "Fixed 60"), but it then holds 60 and runs in **slow motion** (0.55x) when the machine cannot keep up — worse than the console's "Automatic", which drops to 30 and keeps real time. |

## 60 fps

The menus, the world map and the title run at a full 60 fps (`game: speed 1.00x`, 300 frames in 5 s). A 24-kart race
does not, and **that is not a setting**: it is the recording's CPU cost, which the upstream has not solved. What our
settings buy is 30 → 47-52 fps in the race, and a locked 60 fps in its lighter stretches.

The upstream's own next steps, in their words, are the ones that would close the gap: recording with less CPU (less
work per draw, descriptor sets kept across frames by their contents), the kernel's global lock, and profile-guided
optimisation of the generated C (which is still built at `-O1`).

## Reproducing

```bash
scripts/measure-race.sh base                 # one run, the race's frame times
scripts/ab-race.sh "a:" "b:MKW_RESOLUTION=720"   # one run per setting
```

A quieter machine makes the numbers better and the comparison between runs tighter.
