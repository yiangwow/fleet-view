#!/usr/bin/env bash
# usage: [ONLY=<n>] tests/bench/micro.sh   — (ONLY = start at phase n) cost of moving many attached render objects (tests/bench/fv-micro, not shipped).
# docker factoriotools/factorio --benchmark on a COPY of fixtures/saves/nn1.zip with the server mod set + fv-micro
# (no fleet-view). Prints script / whole update ms per phase, idle and moving. KEEP_OUT=<file> keeps the raw log.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
d=$(mktemp -d); trap 'chmod -R a+rwX "$d" 2>/dev/null; rm -rf "$d"' EXIT
mkdir -p "$d/mods"; cp "$root"/fixtures/mods/* "$d/mods/"; cp "$root/fixtures/saves/nn1.zip" "$d/save.zip"
cp -r "$here/fv-micro" "$d/mods/"
chmod -R a+rwX "$d"
phases=$(grep -c '^  {name = ' "$here/fv-micro/control.lua")
if [ -n "${ONLY:-}" ]; then sed -i "s/^local ONLY = nil/local ONLY = $ONLY/" "$d/mods/fv-micro/control.lua"; phases=$((phases - ONLY + 1)); fi
docker run --rm --entrypoint /opt/factorio/bin/x64/factorio -v "$d":/t "${FACTORIO_IMAGE:-factoriotools/factorio:2.1.23}" \
  --mod-directory /t/mods --benchmark /t/save.zip --benchmark-ticks $((10 + phases * 600 + 20)) --benchmark-verbose all >"$d/out.txt" 2>&1
grep -E "FVM|rror" "$d/out.txt" | cut -c1-200
[ -n "${KEEP_OUT:-}" ] && cp "$d/out.txt" "$KEEP_OUT"
python3 -I - "$d/out.txt" <<'P'
import sys, csv, re, statistics as st
lines = open(sys.argv[1]).read().splitlines()
i = [k for k, l in enumerate(lines) if l.startswith("tick,timestamp")][0]
rows = [r for r in csv.DictReader(lines[i:]) if r["tick"][:1] == "t"]
names = {int(m[1]): (int(m[2]), m[3]) for l in lines for m in [re.search(r"FVM phase (\d+) t (\d+) create: (.*)", l)] if m}
def ms(col, a, b):
    v = [int(r[col]) / 1e6 for r in rows[a:b]]
    return st.mean(v) if v else float("nan")
print(f"{'phase':32} {'idle script':>11} {'move script':>11} {'idle whole':>10} {'move whole':>10}   (ms/tick)")
for k, (t, name) in sorted(names.items()):
    print(f"{name:32} {ms('scriptUpdate', t+60, t+200):11.3f} {ms('scriptUpdate', t+210, t+500):11.3f} {ms('wholeUpdate', t+60, t+200):10.3f} {ms('wholeUpdate', t+210, t+500):10.3f}")
P
