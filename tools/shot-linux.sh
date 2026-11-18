#!/usr/bin/env bash
# usage: tools/shot-linux.sh <save.zip> <out-dir> [mode=vp] [timeout_s=300]
# Native Linux Factorio (Steam install) with its OWN config/write-data in a temp dir (never ~/.factorio).
# Env: FV_VP=1 adds Visible Planets in Space from $VP_SRC (a source checkout, default fixtures/visible-planets-src).
#      FV_LAYERS="a,b,c" builds a TEST copy of fleet-view with those three render layers (draw.lua LAYER_*);
#      FV_PAR=true|false (pan mode) sets the parallax setting; FV_PAR_CAM=0.4 overrides PARALLAX_CAM in the test copy.
#      the shot driver gets the same names for its markers. Default = the shipped layers.
set -euo pipefail
save=$(readlink -f "$1"); out=$(mkdir -p "$2" && readlink -f "$2"); mode=${3:-vp}; to=${4:-300}
root=$(cd "$(dirname "$0")/.." && pwd)
GAME=$HOME/.local/share/Steam/steamapps/common/Factorio
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fv-shot-XXXX"); mkdir -p "$TMP/mods" "$TMP/data"
cp "$root"/fixtures/mods/* "$TMP/mods/"
ver=$(python3 -c 'import json;print(json.load(open("'"$root"'/fleet-view/info.json"))["version"])')
cp -r "$root/fleet-view" "$TMP/mods/fleet-view_$ver"
if [ -n "${FV_LAYERS:-}" ]; then
  IFS=, read -r l1 l2 l3 <<<"$FV_LAYERS"
  sed -i "s|^local LAYER_TILE, LAYER_FLAT, LAYER_TOP = .*|local LAYER_TILE, LAYER_FLAT, LAYER_TOP = \"$l1\", \"$l2\", \"$l3\"|" "$TMP/mods/fleet-view_$ver/scripts/draw.lua"
else   # the build's own layers, for the shot driver's markers
  IFS=, read -r l1 l2 l3 < <(grep "^local LAYER_TILE" "$TMP/mods/fleet-view_$ver/scripts/draw.lua" | grep -o '"[^"]*"' | tr -d '"' | paste -sd,)
fi
grep -n "^local LAYER_TILE" "$TMP/mods/fleet-view_$ver/scripts/draw.lua"
cp -r "$root/tests/shot/fleet-view-shot" "$TMP/mods/fleet-view-shot"
echo "return \"$mode\"" > "$TMP/mods/fleet-view-shot/mode.lua"
echo "return ${FV_SEED:-1}" > "$TMP/mods/fleet-view-shot/seed.lua"
echo "return {${FV_IDLE_FRAMES:-900}, ${FV_IDLE_ZOOM:-0.5}, ${FV_IDLE_SHIP:-0}}" > "$TMP/mods/fleet-view-shot/idle.lua"
echo "return ${FV_PAR:-true}" > "$TMP/mods/fleet-view-shot/par.lua"   # pan mode: fleet-view-parallax setting (true/false)
if [ -n "${FV_PAR_CAM:-}" ]; then sed -i "s|^local PARALLAX_CAM = [0-9.]*|local PARALLAX_CAM = $FV_PAR_CAM|" "$TMP/mods/fleet-view_$ver/scripts/draw.lua"; grep -n "^local PARALLAX_CAM" "$TMP/mods/fleet-view_$ver/scripts/draw.lua"; fi
echo "return {\"$l1\", \"$l2\", \"$l3\"}" > "$TMP/mods/fleet-view-shot/layers.lua"
MODS="fleet-view fleet-view-shot"
if [ -n "${FV_VP:-}" ]; then cp -r "${VP_SRC:-$root/fixtures/visible-planets-src}" "$TMP/mods/visible-planets_1.8.2"; python3 - "$TMP/mods/visible-planets_1.8.2/settings.lua" "${FV_VP_SCALE:-14}" <<'P'
import re,sys
p=sys.argv[1]; s=open(p).read()
i=s.index("visible-planets-planet-scale\"")
j=s.index("default_value",i)
k=s.index(",",j)
s=s[:j]+"default_value = "+sys.argv[2]+".0"+s[k:]
open(p,"w").write(s)
P
  grep -n -A3 "planet-scale\"" "$TMP/mods/visible-planets_1.8.2/settings.lua" | grep default; MODS="$MODS visible-planets"; fi
python3 - "$TMP/mods/mod-list.json" $MODS <<'P'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
for m in sys.argv[2:]: d["mods"].append({"name":m,"enabled":True})
json.dump(d,open(p,"w"))
P
cp "$save" "$TMP/save.zip"
printf '[path]\nread-data=%s\nwrite-data=%s\n[general]\nlocale=auto\n[graphics]\nfullscreen=false\n' "$GAME/data" "$TMP/data" > "$TMP/config.ini"
SteamAppId=427520 SteamGameId=427520 "$GAME/bin/x64/factorio" --config "$TMP/config.ini" --mod-directory "$TMP/mods" \
  --load-game "$TMP/save.zip" --disable-audio >"$TMP/stdout.log" 2>&1 &
PID=$!
# the temp dir (mods copy + write-data, 0.5-1.2 GB) is removed on exit: 20 runs filled /tmp on 2026-11-16. KEEP_TMP=1 keeps it.
trap 'kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true; [ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT
SO="$TMP/data/script-output"; LOG="$TMP/data/factorio-current.log"; EXPECT=${EXPECT:-4}; ok=0
for i in $(seq 1 "$to"); do
  if [ -d "$SO" ] && [ "$(ls "$SO"/fv-shot-*.png 2>/dev/null | wc -l)" -ge "$EXPECT" ] && ! grep -q "FVSHOT ship" "$LOG" 2>/dev/null; then :; fi
  if grep -q "FVSHOT ship\|FVSHOT idle done\|FVSHOT fv-shot-deck\|FVSHOT dirs done\|FVSHOT art done\|FVSHOT cross done\|FVSHOT order done\|FVSHOT planet done\|FVSHOT moon done\|FVSHOT subpx done" "$LOG" 2>/dev/null && [ "$(ls "$SO"/fv-shot-*.png 2>/dev/null | wc -l)" -ge "$EXPECT" ]; then sleep 4; ok=1; break; fi
  if grep -qiE "non-recoverable|The mod .* caused a" "$LOG" 2>/dev/null; then grep -iE -A3 "non-recoverable|caused a" "$LOG" | head -12 >&2; break; fi
  kill -0 $PID 2>/dev/null || { echo "factorio exited early"; tail -20 "$TMP/stdout.log"; break; }
  sleep 1
done
cp "$SO"/*.png "$out"/ 2>/dev/null || true
cp "$LOG" "$out/factorio-current.log" 2>/dev/null || true
grep FVSHOT "$LOG" | head -20 || true
[ $ok = 1 ] && echo "OK: $(ls "$out"/*.png | tr '\n' ' ')" || { echo "FAILED"; exit 1; }
