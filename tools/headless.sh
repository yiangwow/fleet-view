#!/usr/bin/env bash
# usage: tools/headless.sh <zip> [save=fixtures/saves/nn1.zip]
# Generic headless runner: mod dir = fixtures/mods/* + <zip> + tests/headless/fleet-view-test (if present);
# loads a COPY of the save for 4520 ticks (TICKS= overrides) in the factorio docker image, prints the log.
# Fails on "Error" in the log, or (when the helper mod exists) if "fleet-view checks: all passed" is missing.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
zip=$(readlink -f "$1"); save=$(readlink -f -m "${2:-$root/fixtures/saves/nn1.zip}")
[ -f "$zip" ] || { echo "headless: FAIL (mod zip not found: $zip)" >&2; exit 1; }
[ -f "$save" ] || { echo "headless: FAIL (save not found: $save)" >&2; exit 1; }
command -v docker >/dev/null || { echo "headless: FAIL (docker not found)" >&2; exit 1; }
IMAGE=${FACTORIO_IMAGE:-factoriotools/factorio:2.1.23}
d=$(mktemp -d); trap 'chmod -R a+rwX "$d" 2>/dev/null; rm -rf "$d"' EXIT
mkdir -p "$d/mods"
cp "$root"/fixtures/mods/* "$d/mods/"
cp "$zip" "$d/mods/"
helper="$root/tests/headless/fleet-view-test"
[ -d "$helper" ] && cp -r "$helper" "$d/mods/fleet-view-test"
cp "$save" "$d/save.zip"
chmod -R a+rwX "$d"
docker run --rm --entrypoint /opt/factorio/bin/x64/factorio -v "$d":/t "$IMAGE" \
  --mod-directory /t/mods --benchmark /t/save.zip --benchmark-ticks "${TICKS:-4520}" >"$d/log.txt" 2>&1
rc=$?
cat "$d/log.txt"
if [ "$rc" -ne 0 ]; then echo "headless: FAIL (docker/factorio exit $rc)" >&2; exit 1; fi
if grep -q "Error" "$d/log.txt"; then echo "headless: FAIL (Error in log)" >&2; exit 1; fi
if [ -d "$helper" ] && ! grep -q "fleet-view checks: all passed" "$d/log.txt"; then
  echo "headless: FAIL (checks did not pass)" >&2; exit 1
fi
echo "headless: ok"
