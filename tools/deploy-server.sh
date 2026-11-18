#!/usr/bin/env bash
# Deploy dist/fleet-view_<info.json version>.zip to nn1 (tt-server). Aborts if anyone is online. Backs up the installed
# fleet-view zip + mod-list.json + mod-settings.dat to /home/tt/factorio-backup-fleet-view-<old>-<date>, swaps the zip,
# restarts, prints the log. Runs detached on the server (an interrupted ssh must not leave it half done).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$root/fleet-view/info.json")
ZIP=$root/dist/fleet-view_$ver.zip; SHA=$(sha1sum "$ZIP" | cut -d' ' -f1); D=$(date +%Y%m%d-%H%M)
scp -q "$ZIP" tt@192.168.1.9:/home/tt/fleet-view_$ver-$D.zip
ssh tt@192.168.1.9 "cat > /home/tt/fv-deploy-$ver-$D.sh" <<R
#!/usr/bin/env bash
set -euo pipefail
echo "== \$(date -Is) start $ver $SHA"
[ "\$(sha1sum /home/tt/fleet-view_$ver-$D.zip | cut -d' ' -f1)" = $SHA ] || { echo "ABORT: zip sha1 mismatch"; exit 1; }
online=\$(docker exec factorio rcon /players online | head -1); echo "players: \$online"
case "\$online" in *"(0)"*) ;; *) echo "ABORT: players online"; exit 1;; esac
old=\$(docker exec factorio sh -c 'ls /factorio/mods | grep "^fleet-view_.*\.zip$"' | head -1); echo "installed: \$old"
BK=/home/tt/factorio-backup-\${old%.zip}-$D; mkdir -p "\$BK"
docker stop -t 60 factorio
docker run --rm -v /home/tt/factorio:/f -v /home/tt:/h -v "\$BK":/b alpine sh -c "cp /f/mods/\$old /f/mods/mod-list.json /f/mods/mod-settings.dat /b/ && rm /f/mods/\$old && cp /h/fleet-view_$ver-$D.zip /f/mods/fleet-view_$ver.zip && chown 845:845 /f/mods/fleet-view_$ver.zip && sha1sum /f/mods/fleet-view_$ver.zip"
docker start factorio
for _ in \$(seq 1 60); do docker logs --since 5m factorio 2>&1 | grep -qE "Hosting game|Error" && break; sleep 5; done
docker logs --since 5m factorio 2>&1 | grep -iE "fleet-view [0-9]|error|Hosting game|Checksum of fleet" | head -10
echo "== \$(date -Is) done"
echo "rollback: docker stop -t 60 factorio; docker run --rm -v /home/tt/factorio:/f -v \$BK:/b alpine sh -c 'rm -f /f/mods/fleet-view_$ver.zip && cp /b/* /f/mods/ && chown 845:845 /f/mods/*'; docker start factorio"
R
ssh tt@192.168.1.9 "chmod +x /home/tt/fv-deploy-$ver-$D.sh; setsid nohup /home/tt/fv-deploy-$ver-$D.sh > /home/tt/fv-deploy-$ver-$D.log 2>&1 < /dev/null & sleep 50; cat /home/tt/fv-deploy-$ver-$D.log"
