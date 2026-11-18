#!/usr/bin/env bash
# usage: run-headless.sh <mode: anchor|none|benchA|benchB> <ticks>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
mode=$1; ticks=${2:-600}
T=$(mktemp -d /tmp/fvspike.XXXX)
mkdir -p "$T/mods"; cp "$root"/fixtures/mods/* "$T/mods/"; cp "$root/fixtures/saves/nn1.zip" "$T/save.zip"
if [ "$mode" != none ]; then
  cp -r "$here/fv-spike" "$T/mods/fv-spike"; echo "return \"$mode\"" > "$T/mods/fv-spike/mode.lua"
  python3 - "$T/mods/mod-list.json" <<'P'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["mods"].append({"name":"fv-spike","enabled":True}); json.dump(d,open(p,"w"))
P
fi
chmod -R a+rwX "$T"
docker run --rm --entrypoint /opt/factorio/bin/x64/factorio -v "$T":/t factoriotools/factorio:2.1.23 \
  --mod-directory /t/mods --benchmark /t/save.zip --benchmark-ticks "$ticks" --benchmark-verbose all > "$T/out.txt" 2>&1 || true
grep -E "FV |Performed|avg:|rror" "$T/out.txt" | cut -c1-300 || true
python3 "$here/analyze.py" "$T/out.txt"
[ -n "${KEEP:-}" ] && echo "$T" || rm -rf "$T"
