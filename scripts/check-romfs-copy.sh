#!/usr/bin/env bash
# Check the local romfs copy against the dump it came from: file count, total
# bytes and a hash sample of files spread across the tree.
#
# Usage: scripts/check-romfs-copy.sh [N]   (N = files to hash, default 40)
set -euo pipefail
cd "$(dirname "$0")/.."
. config/mkw-tune.env

dst=${MKW_ROMFS:-$MKW_GAME_DIR/romfs-local}
src=$MKW_DUMP/romfs
n=${1:-40}

echo "=== counts ==="
printf "source  : %s files, %s\n" "$(find "$src" -type f | wc -l)" "$(du -sh "$src" | cut -f1)"
printf "local   : %s files, %s\n" "$(find "$dst" -type f | wc -l)" "$(du -sh "$dst" | cut -f1)"

echo "=== byte totals ==="
printf "source  : %s\n" "$(find "$src" -type f -printf '%s\n' | awk '{s+=$1} END {print s}')"
printf "local   : %s\n" "$(find "$dst" -type f -printf '%s\n' | awk '{s+=$1} END {print s}')"

echo "=== hash sample ($n files) ==="
bad=0
while read -r f; do
  rel=${f#"$src"/}
  a=$(sha256sum "$f" | cut -d' ' -f1)
  b=$(sha256sum "$dst/$rel" 2>/dev/null | cut -d' ' -f1)
  if [ "$a" != "$b" ]; then
    echo "MISMATCH $rel"
    bad=$((bad + 1))
  fi
done < <(find "$src" -type f | shuf -n "$n")
echo "mismatches: $bad"
