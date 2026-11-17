#!/usr/bin/env bash
# Measure a 24-kart Mario Kart World race with the port's own machinery: the
# attract demo races by itself, IsSequenceFlag is the node a race starts at, so
# the run is measured from there and ends RACE_SECS later.
#
# The turbo stays OFF: with it the game runs at 4x and the phase watcher never
# reaches the race's own node, so the window measured is not a race.
#
# Usage: scripts/measure-race.sh NAME [RACE_SECS]      (extra MKW_* env passes through)
#   e.g. MKW_RESOLUTION=720 scripts/measure-race.sh hd
set -uo pipefail
cd "$(dirname "$0")/.."
. config/mkw-tune.env

name=${1:?usage: scripts/measure-race.sh NAME [RACE_SECS]}
race_secs=${2:-30}
up=$PWD/upstream
log=$up/build/run/$name.log
mkdir -p "$up/build/run"

export MKW_GAME_DIR=${MKW_GAME_DIR:-$up/game}
export MKW_GPU_MEM_LIMIT=${MKW_GPU_MEM_LIMIT:-10240}
export MKW_SPARSE_MIB=${MKW_SPARSE_MIB:-768}
export MKW_SEQ_WATCH=1 MKW_SEQ_UNTIL=${MKW_SEQ_UNTIL:-IsSequenceFlag} MKW_SEQ_EXIT=$race_secs
export MKW_TURBO=${MKW_TURBO:-off} MKW_SKIP_MOVIES=${MKW_SKIP_MOVIES:-0}
export MKW_HOST_TIME=1 MKW_PASS_TIMING=${MKW_PASS_TIMING:-1}
export MKW_BACKGROUND_WINDOW=${MKW_BACKGROUND_WINDOW:-1} MKW_ASSUME_FOCUS=1
export MKW_TRACE=${MKW_TRACE:-gfx,present}

rm -f "$up/build/run/$name.ctl"; mkfifo "$up/build/run/$name.ctl"
export MKW_CTL="$up/build/run/$name.ctl"

romfs=${MKW_ROMFS:-$MKW_GAME_DIR/romfs-local}
[ -d "$romfs" ] || romfs="$MKW_DUMP/romfs"

# The game's own --seconds is the safety limit; the world clock starts at the
# save's first frame, so it has to cover the boot, the world map's load (which
# varies with the page cache) and the race. MKW_SEQ_EXIT ends the run 30 s
# after the race node, so this is only the backstop.
world=${WORLD_SECS:-900}
echo "measure-race: $name, race window ${race_secs}s (safety limit ${world}s)"
timeout -s KILL ${RUN_LIMIT:-420} "$up/build/mkw" \
  --exefs "$MKW_DUMP/exefs" --romfs "$romfs" --profile "$up/build/profile" \
  --seconds "$world" > "$log" 2>&1
echo "exit $?"

echo "=== the race window ==="
grep -E "frametime: (60 s|[0-9]+ s):" "$log" | tail -2
grep -oE "game: speed [0-9.]+x over [0-9.]+ s \([0-9]+ frames, [0-9]+ interval changes" "$log" | tail -3
echo "=== frames ==="
grep -oE "present: frame [0-9]+ interval [0-9.]+ ms" "$log" | tail -3
echo "=== log: $log ==="
