#!/usr/bin/env bash
# usage: tools/shot.sh <save.zip> <out-dir> [mode=shot|layers|rect|follow|fleet|default|fixed|random|anim] (random/anim: FV_SEED=<n> picks the spot seed) [timeout_s=240, anim: 480]
# Launches Windows Factorio with its OWN config/write-data under %TEMP%\fv-shot (never the owner's profile),
# loads <save>, the fv-spike mod takes screenshots into script-output, we copy them to <out-dir>, then kill ONLY the PID we started.
set -euo pipefail
save=$(readlink -f "$1"); out=$(mkdir -p "$2" && readlink -f "$2"); mode=${3:-shot}; to=${4:-240}
if [ "$mode" = anim ] && [ -z "${4:-}" ]; then to=480; fi   # anim writes 142 screenshots: more time unless one was given
if [ "$mode" = idle ] && [ -z "${4:-}" ]; then to=900; fi   # idle writes 900 screenshots (one per tick)
root=$(cd "$(dirname "$0")/.." && pwd)
EXE_W='E:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'
READ_W='E:\SteamLibrary\steamapps\common\Factorio\data'
TMP_L=/mnt/c/Users/computer/AppData/Local/Temp/fv-shot
TMP_W='C:\Users\computer\AppData\Local\Temp\fv-shot'
rm -rf "$TMP_L"; mkdir -p "$TMP_L/mods" "$TMP_L/data"
cp "$root"/fixtures/mods/* "$TMP_L/mods/"
if [ "$mode" = fleet ] || [ "$mode" = default ] || [ "$mode" = fixed ] || [ "$mode" = random ] || [ "$mode" = anim ] || [ "$mode" = idle ]; then
  # fleet-view zip (make zip) + the screenshot driver mod (tests/shot, not shipped); EXPECT = the PNGs the mode writes
  (cd "$root" && make -s zip >/dev/null)
  cp "$root"/dist/fleet-view_*.zip "$TMP_L/mods/"
  cp -r "$root/tests/shot/fleet-view-shot" "$TMP_L/mods/fleet-view-shot"
  echo "return \"$mode\"" > "$TMP_L/mods/fleet-view-shot/mode.lua"
  echo "return ${FV_SEED:-1}" > "$TMP_L/mods/fleet-view-shot/seed.lua"
  MODS="fleet-view fleet-view-shot"; EXPECT=${EXPECT:-3}; case "$mode" in default|fixed) EXPECT=3;; random) EXPECT=1;; anim) EXPECT=142;; idle) EXPECT=900;; esac   # anim: 71 frames x (wide + close), see tests/shot
else
  cp -r "$root/spike/fv-spike" "$TMP_L/mods/fv-spike"; echo "return \"$mode\"" > "$TMP_L/mods/fv-spike/mode.lua"
  MODS="fv-spike"
fi
python3 - "$TMP_L/mods/mod-list.json" $MODS <<'P'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
for m in sys.argv[2:]: d["mods"].append({"name":m,"enabled":True})
json.dump(d,open(p,"w"))
P
cp "$save" "$TMP_L/save.zip"
printf '[path]\nread-data=%s\nwrite-data=%s\\data\n[general]\nlocale=auto\n[graphics]\nfullscreen=false\n' "$READ_W" "$TMP_W" > "$TMP_L/config.ini"
fexe() { tasklist.exe /FI "IMAGENAME eq factorio.exe" /FO CSV /NH 2>/dev/null | tr -d '\r' | grep -i '"factorio.exe"' | cut -d, -f2 | tr -d '"' | sort || true; }
BEFORE=$(fexe)
ENVSET="\$env:SteamAppId='427520'; \$env:SteamGameId='427520';"
[ -n "${FV_NO_STEAMAPPID:-}" ] && ENVSET=""   # test hook for the abort path only
PID=$(powershell.exe -NoProfile -Command "$ENVSET (Start-Process -PassThru -FilePath '$EXE_W' -ArgumentList '--config','$TMP_W\\config.ini','--mod-directory','$TMP_W\\mods','--load-game','$TMP_W\\save.zip','--disable-audio').Id" | tr -d '\r')
echo "started PID $PID (factorio.exe PIDs before launch: $(echo $BEFORE | tr '\n' ' '))"
alive() { tasklist.exe /FI "PID eq $PID" /FI "IMAGENAME eq factorio.exe" /NH 2>/dev/null | grep -q "factorio.exe"; }
trap 'if [ -n "${PID:-}" ] && alive; then taskkill.exe /PID "$PID" /F >/dev/null 2>&1 || true; for _ in $(seq 1 20); do alive || break; sleep 0.5; done; sleep 2; fi' EXIT
# Abort path: Steam relaunch hands the game to Steam (default profile, untracked PID). Never wait on that.
steam_abort() {
  local why=$1 stray; sleep 8
  stray=$(comm -13 <(echo "$BEFORE") <(fexe) | grep -v "^$PID$" || true)
  echo "ERROR: $why" >&2
  echo "ERROR: the launch did not stay under this script's control (likely 'Steam requires game restart': needs SteamAppId/SteamGameId set)." >&2
  [ -n "$stray" ] && echo "ERROR: NEW factorio.exe process(es) not started by this script: $stray  -- NOT killing them; check and close them by hand (they may be on the default profile)." >&2
  exit 2
}
SO="$TMP_L/data/script-output"; ok=0
for i in $(seq 1 "$to"); do
  if ls "$SO"/fv-shot-*.png >/dev/null 2>&1 && [ "$(ls "$SO"/fv-shot-*.png | wc -l)" -ge "${EXPECT:-1}" ]; then sleep 3; ok=1; break; fi
  # A Lua error in the helper raises a modal dialog on the owner's screen: detect it in our private log and kill our own PID at once.
  if grep -qiE "non-recoverable|The mod .* caused a" "$TMP_L/data/factorio-current.log" 2>/dev/null; then
    grep -iE -A3 "non-recoverable|caused a" "$TMP_L/data/factorio-current.log" | head -12 >&2
    taskkill.exe /PID "$PID" /F >/dev/null 2>&1 || true
    echo "ERROR: Factorio reported a non-recoverable mod error; killed PID $PID (only the process this script started)." >&2
    exit 3
  fi
  if ! alive; then
    LOG="$TMP_L/data/factorio-current.log"
    if [ ! -f "$LOG" ] || grep -q "Steam requires game restart" "$LOG"; then steam_abort "process $PID exited with no private log (or Steam restart requested)"; fi
    echo "process $PID exited early; log tail:"; tail -5 "$LOG"; break
  fi
  sleep 1
done
cp "$SO"/*.png "$out"/ 2>/dev/null || true
cp "$TMP_L/data/factorio-current.log" "$out/factorio-current.log" 2>/dev/null || true
[ $ok = 1 ] && echo "OK: $(ls "$out"/*.png)" || { echo "FAILED: no screenshot"; exit 1; }
