#!/usr/bin/env bash
# A/B a set of MKW_* settings over the race, one run each, and print the race's
# frame times for each.
#
# Two runs of the same build differ by up to 7 ms here (the desktop carries
# other emulators), so a single run per setting is not enough: this prints the
# median over the race's frames, and the race's last segment (the attract demo
# races different courses, so a segment is not the whole race).
#
# Usage: scripts/ab-race.sh "NAME1:MKW_A=1 MKW_B=2" "NAME2:..." ...
#   each argument is NAME followed by the env for that run
set -uo pipefail
cd "$(dirname "$0")/.."
. config/mkw-tune.env

for spec in "$@"; do
  name=${spec%%:*}
  envs=${spec#*:}
  echo "=================== $name : $envs"
  # shellcheck disable=SC2086
  env $envs scripts/measure-race.sh "ab-$name" 30 >/dev/null 2>&1
  log=upstream/build/run/ab-$name.log
  [ -s "$log" ] || { echo "  NO LOG"; continue; }
  python3 - "$log" <<'PY'
import re, statistics, sys
pat = re.compile(r"present: frame (\d+) interval ([0-9.]+) ms")
race = re.compile(r"race: in a race")
lines = open(sys.argv[1], errors="ignore").readlines()
starts = [i for i, l in enumerate(lines) if race.search(l)]
if not starts:
    print("  no race"); raise SystemExit
ints = []
for l in lines[starts[-1]:]:
    m = pat.search(l)
    if m: ints.append(float(m.group(2)))
if len(ints) < 60:
    print("  race segment only %d frames" % len(ints)); raise SystemExit
med = statistics.median(ints)
at60 = sum(1 for x in ints if x <= 17.0) * 100.0 / len(ints)
print("  n=%-6d median %5.1f ms (%4.1f fps)  mean %5.1f  at a locked 60 fps: %4.1f%% of frames" % (
    len(ints), med, 1000 / med, statistics.mean(ints), at60))
PY
done
