#!/usr/bin/env bash
# Track adriadam10/mkw-recomp, the upstream this repo depends on.
#
# The upstream is the git submodule at upstream/, pinned to the commit in
# .upstream-sha. The upstream ships releases daily, so this is how a new one
# comes in: --merge moves the submodule to the upstream's main and rebuilds
# (the game code is regenerated and the shaders retranslated; our settings are
# ours and do not change).
#
# Usage: scripts/upstream-check.sh [--merge] [--mark] [--rebuild] [SHA]
#   (no argument)  show the pinned commit, the upstream's latest, and how far
#                  behind we are
#   --merge        move the submodule to the upstream's latest main and record
#                  the new commit in .upstream-sha
#   --mark         record the submodule's current commit in .upstream-sha
#                  (after a manual checkout)
#   --rebuild      rebuild after a merge (the game code and the shaders)
#   SHA            merge to that commit instead of the upstream's main
set -euo pipefail
cd "$(dirname "$0")/.."

up=upstream
sha_file=.upstream-sha
pinned=$(cat "$sha_file" 2>/dev/null || echo "")
current=$(git -C "$up" rev-parse HEAD)

merge=0; mark=0; rebuild=0; target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=1 ;;
    --mark) mark=1 ;;
    --rebuild) rebuild=1 ;;
    -*) echo "usage: scripts/upstream-check.sh [--merge] [--mark] [--rebuild] [SHA]"; exit 2 ;;
    *) target=$1 ;;
  esac
  shift
done

if [ "$merge" = 1 ]; then
  git -C "$up" fetch origin main
  if [ -n "$target" ]; then
    git -C "$up" checkout --detach "$target"
  else
    git -C "$up" checkout --detach origin/main
  fi
  git -C "$up" submodule update --recursive
  new=$(git -C "$up" rev-parse HEAD)
  echo "$new" > "$sha_file"
  echo "upstream: now $new ($(git -C "$up" describe --tags --always))"
  echo "          recorded in $sha_file"
  if [ "$rebuild" = 1 ]; then
    echo "== rebuilding (the game code and the shaders change with the upstream) =="
    (cd "$up" && uv run python recomp/gen.py --exefs "$(readlink -f game/exefs)" --out build/generated \
       --jobs "$(nproc)" --patches recomp/patches-mkw-180.txt)
    (cd "$up" && uv run tools/shaders/extract.py && uv run tools/shaders/translate.py --progress)
    (cd "$up" && uv run tools/build/build.py --gen "$PWD/build/generated" --exefs "$(readlink -f game/exefs)" --jobs 8)
  fi
  exit 0
fi

if [ "$mark" = 1 ]; then
  echo "$(git -C "$up" rev-parse HEAD)" > "$sha_file"
  echo "upstream: recorded $(cat "$sha_file")"
  exit 0
fi

git -C "$up" fetch origin main --quiet
remote=$(git -C "$up" rev-parse origin/main)
echo "=== upstream: adriadam10/mkw-recomp ==="
echo "pinned in $sha_file : $pinned"
echo "submodule now       : $current ($(git -C "$up" describe --tags --always))"
echo "upstream main       : $remote ($(git -C "$up" describe --tags --always origin/main 2>/dev/null || echo '-'))"
if [ "$current" = "$remote" ]; then
  echo "state                : up to date"
else
  behind=$(git -C "$up" rev-list --count "$current..$remote")
  echo "state                : $behind commit(s) behind"
fi
echo
echo "merge it with: scripts/upstream-check.sh --merge [--rebuild]"
