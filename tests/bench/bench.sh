#!/usr/bin/env bash
# usage: tests/bench/bench.sh <A|B> [ticks=1800]   (zip must exist: make zip)
# A = server mod set only; B = + fleet-view + fleet-view-bench (viewer on platform-2, moving every tick).
# Runs docker factoriotools/factorio:2.1.23 --benchmark on a COPY of fixtures/saves/nn1.zip. Never touches the live server.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
mode=$1; ticks=${2:-1800}
# ZIP= picks a build (e.g. a baseline); default = the version in fleet-view/info.json (NOT the first zip in dist/:
# that silently benchmarked 0.1.0 until 2026-10-31)
ver=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$root/fleet-view/info.json")
zip=${ZIP:-$root/dist/fleet-view_$ver.zip}
[ -f "$zip" ] || { echo "no zip $zip (make zip)"; exit 1; }
echo "bench zip: $zip ($(sha1sum "$zip" | cut -c1-8))"
d=$(mktemp -d); trap 'chmod -R a+rwX "$d" 2>/dev/null; rm -rf "$d"' EXIT
mkdir -p "$d/mods"; cp "$root"/fixtures/mods/* "$d/mods/"; cp "$root/fixtures/saves/nn1.zip" "$d/save.zip"
# FLOAT=smooth|balanced|light sets the float smoothness setting, FLOAT=off turns the float off; HOLD=n ticks after SHOW the
# viewer leaves (default 1300; the fill + arrival of 10 big ships takes ~1000 ticks, so use HOLD=2300 and read the PARKED line)
# C = the bench driver WITHOUT fleet-view (STRESS: what the stress platforms cost the other mods)
if [ "$mode" = B ] || [ "$mode" = C ]; then [ "$mode" = B ] && cp "$zip" "$d/mods/"; cp -r "$here/fleet-view-bench" "$d/mods/"
  sed -i "s/^local SHOW = [0-9]*/local SHOW = ${SHOW_TICK:-5}/" "$d/mods/fleet-view-bench/control.lua"
  sed -i "s/^local STATS = [0-9]*/local STATS = ${STATS_EVERY:-600}/" "$d/mods/fleet-view-bench/control.lua"
  sed -i "s/^local STRESS = [0-9]*/local STRESS = ${STRESS:-0}/" "$d/mods/fleet-view-bench/control.lua"
  [ -n "${HIST:-}" ] && sed -i "s/^local HIST = false/local HIST = true/" "$d/mods/fleet-view-bench/control.lua"
  sed -i "s/^local HOLD = [0-9]*/local HOLD = ${HOLD:-1300}/" "$d/mods/fleet-view-bench/control.lua"
  sed -i "s/^local FLOAT = \"[a-z]*\"/local FLOAT = \"${FLOAT:-}\"/" "$d/mods/fleet-view-bench/control.lua"; fi
chmod -R a+rwX "$d"
docker run --rm --entrypoint /opt/factorio/bin/x64/factorio -v "$d":/t "${FACTORIO_IMAGE:-factoriotools/factorio:2.1.23}" \
  --mod-directory /t/mods --benchmark /t/save.zip --benchmark-ticks "$ticks" --benchmark-verbose all >"$d/out.txt" 2>&1
grep -E -A6 "FV-BENCH|FV-PROF|rror|Performed" "$d/out.txt" | grep -v FV-STRESS | cut -c1-300
grep -E "FV-STRESS|FV-HIST" "$d/out.txt" | cut -c1-200
[ -n "${KEEP_OUT:-}" ] && cp "$d/out.txt" "$KEEP_OUT"
SHOW_TICK=${SHOW_TICK:-5} STRESS=${STRESS:-0} HOLD=${HOLD:-1300} python3 -I "$here/analyze.py" "$d/out.txt"
