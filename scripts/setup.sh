#!/usr/bin/env bash
# Set up our build of adriadam10/mkw-recomp: the upstream (the submodule), our
# game copy, and the build.
#
# Usage: scripts/setup.sh [--build] [--romfs-local] [--only=<step>]
#   --build         also compile the game and the runtime (the slow part)
#   --romfs-local   copy the romfs to the fast disk next to the game dir
#                    (the dump's own mount is slow for its 206,202 small files:
#                    the world map's first frame took 39.5 s streaming them)
#   --only=STEP     one step: upstream | game | spec | gen | shaders | build
#
# Every step is idempotent; re-run it after the upstream moves.
set -euo pipefail
cd "$(dirname "$0")/.."

. config/mkw-tune.env
up=$PWD/upstream
game=$up/game

do_build=0
romfs_local=0
only=""
for a in "$@"; do
  case "$a" in
    --build) do_build=1 ;;
    --romfs-local) romfs_local=1 ;;
    --only=*) only=${a#--only=} ;;
    *) echo "usage: scripts/setup.sh [--build] [--romfs-local] [--only=step]"; exit 2 ;;
  esac
done
step() { [ -z "$only" ] || [ "$only" = "$1" ]; }

# ---- the upstream ----------------------------------------------------------
if step upstream; then
  echo "== upstream =="
  git submodule update --init --recursive
  echo "   $(git -C "$up" describe --tags --always)  (pinned in .upstream-sha)"
fi

# ---- the game copy ---------------------------------------------------------
if step game; then
  echo "== game copy =="
  [ -d "$MKW_DUMP/exefs" ] || { echo "no $MKW_DUMP/exefs: point MKW_DUMP at your dump"; exit 1; }
  mkdir -p "$game"
  ln -sfn "$MKW_DUMP/exefs" "$game/exefs"
  ln -sfn "$MKW_DUMP/romfs" "$game/romfs"
  # The port reads the prepared SPIR-V and the pipeline cache from the GAME DIR
  # (not next to the binary). Without them the prewarm finds no shader and
  # builds nothing: every pipeline is then built in play, mid-race.
  [ -e "$game/spirv" ] || ln -s ../build/spirv "$game/spirv"
  mkdir -p "$game/cache" "$game/logs"
  echo "   exefs -> $MKW_DUMP/exefs"
  echo "   romfs -> $MKW_DUMP/romfs"
fi

if [ "$romfs_local" = 1 ] && step game; then
  echo "== romfs, local copy =="
  if [ -d "$game/romfs-local" ]; then
    echo "   already there"
  else
    mkdir -p "$game/romfs-local"
    echo "   copying (23 GB, a few minutes)"
    tar -C "$MKW_DUMP/romfs" -cf - . | tar -C "$game/romfs-local" -xf -
    echo "   done: $(find "$game/romfs-local" -type f | wc -l) files"
  fi
fi

# ---- the build -------------------------------------------------------------
if [ "$do_build" = 1 ]; then
  cd "$up"
  if step spec; then
    echo "== the SM86 specification (fetches NVIDIA's nvdisasm and ptxas, 84 MB) =="
    uv run sm86/spec/spec.py
  fi
  if step gen; then
    echo "== the game code (AArch64 to C) =="
    # The 1.8.0 patch set; for a 1.0.0 dump it is recomp/patches-mkw.txt.
    uv run python recomp/gen.py --exefs "$MKW_DUMP/exefs" --out build/generated \
      --jobs "$(nproc)" --patches recomp/patches-mkw-180.txt
  fi
  if step shaders; then
    echo "== the shaders (SM86 to SPIR-V) =="
    uv run tools/shaders/extract.py
    uv run tools/shaders/translate.py --progress
  fi
  if step build; then
    echo "== the runtime =="
    uv run tools/build/build.py --gen "$up/build/generated" --exefs "$MKW_DUMP/exefs" --jobs 8
  fi
  # The game dir's pipeline cache is the port's own; keep it with the game.
  [ -s "$game/pipeline-cache.bin" ] || [ ! -s build/pipeline-cache.bin ] || \
    cp build/pipeline-cache.bin build/pipeline-keys.bin "$game/" 2>/dev/null || true
fi

echo "setup: done. Run it with: ./run-mkw-180.sh"
