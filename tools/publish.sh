#!/usr/bin/env bash
# Upload dist/fleet-view_<info.json version>.zip to the mod portal (API v2) and check the portal sha1.
# Key: ~/.config/fleet-view/portal-key (chmod 600, owner-made), else a hidden prompt. Never printed or logged.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$root/fleet-view/info.json")
ZIP=$root/dist/fleet-view_$ver.zip
[ -f "$ZIP" ] || { echo "ABORT: $ZIP missing (make zip)"; exit 1; }
SHA=$(sha1sum "$ZIP" | cut -d' ' -f1)
live=$(curl -fsS https://mods.factorio.com/api/mods/fleet-view | python3 -c 'import json,sys;print(json.load(sys.stdin)["releases"][-1]["version"])')
[ "$live" != "$ver" ] || { echo "ABORT: portal already has $ver"; exit 1; }
KF=$HOME/.config/fleet-view/portal-key
if [ -f "$KF" ]; then KEY=$(tr -d '[:space:]' < "$KF"); else read -rsp "mod portal API key: " KEY; echo; fi
URL=$(curl -fsS -H "Authorization: Bearer $KEY" -F mod=fleet-view https://mods.factorio.com/api/v2/mods/releases/init_upload | python3 -c 'import json,sys;print(json.load(sys.stdin)["upload_url"])')
curl -fsS -F "file=@$ZIP" "$URL" >/dev/null
sleep 3
curl -fsS https://mods.factorio.com/api/mods/fleet-view | python3 -c 'import json,sys;r=json.load(sys.stdin)["releases"][-1];print("portal:",r["version"],r["sha1"])'
echo "local:  $ver $SHA"
