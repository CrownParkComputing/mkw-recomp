#!/usr/bin/env bash
# Run Mario Kart World through our build of adriadam10/mkw-recomp.
#
# The upstream is the submodule at upstream/; the game is installed in
# upstream/game/ (the port looks for the prepared SPIR-V, the pipeline cache and
# the settings there - scripts/setup.sh puts them there).
#
# Usage: ./run-mkw-180.sh [SECONDS] [SHOT]
#   SECONDS  how long to run (default 0 = until the window is closed)
#   SHOT     screenshot to write (default none)
#
#   MKW_CTL_NAME=NAME gives the run a control FIFO:
#     tools/../upstream/tools/run/ctl.sh NAME shot PATH   a frame on demand
#
# Extra MKW_* settings pass through; config/mkw-tune.env holds ours.
set -euo pipefail
cd "$(dirname "$0")"

secs=${1:-0}
shot=${2:-}
. config/mkw-tune.env

up=$PWD/upstream
[ -x "$up/build/mkw" ] || { echo "no $up/build/mkw: build it first (scripts/setup.sh)"; exit 1; }

# The installation dir: the prepared SPIR-V, the pipeline cache, the settings.
export MKW_GAME_DIR=${MKW_GAME_DIR:-$up/game}
mkdir -p "$MKW_GAME_DIR/cache" "$MKW_GAME_DIR/logs"

# The romfs: the local copy on the fast disk when there is one. The dump's own
# mount is slow for the romfs's 206,202 small files and the world map's first
# frame took 39.5 s streaming them.
romfs=${MKW_ROMFS:-$MKW_GAME_DIR/romfs-local}
[ -d "$romfs" ] || romfs="$MKW_DUMP/romfs"

# The control FIFO, for tools/run/ctl.sh shots.
if [ -n "${MKW_CTL_NAME:-}" ]; then
  mkdir -p "$up/build/run"
  rm -f "$up/build/run/${MKW_CTL_NAME}.ctl"
  mkfifo "$up/build/run/${MKW_CTL_NAME}.ctl"
  export MKW_CTL="$up/build/run/${MKW_CTL_NAME}.ctl"
fi

echo "mkw: run ${secs}s (romfs: ${romfs}, game dir: ${MKW_GAME_DIR})"
args=(--exefs "$MKW_DUMP/exefs" --romfs "$romfs" --profile "$up/build/profile")
[ "$secs" != "0" ] && args+=(--seconds "$secs")
[ -n "$shot" ] && args+=(--shot "$shot")
cd "$up" && exec ./build/mkw "${args[@]}"
