#!/usr/bin/env bash
# usage: tools/gif.sh <shot-out-dir> [fps=10]
# Animations from the frames `tools/shot.sh <save.zip> <out-dir> anim` copied into <out-dir>: fv-shot-anim-{wide,close}-NNN.png,
# one frame per 6 game ticks within each phase (leave, arrive), so fps 10 plays each phase in real time; the 30-tick wait
# between the phases is not filmed and plays as one frame step. Per camera it writes, into <out-dir> (nothing outside it):
#   fleet-view-anim-<cam>.gif        960 px wide, looping (ffmpeg palettegen/paletteuse)
#   fleet-view-anim-<cam>-sheet.png  contact sheet: every Nth frame (N = ceil(frames / 12), at most 12), tiled 4x3
# Needs ffmpeg. A camera with no frames is skipped; with neither it is an error.
set -euo pipefail
dir=${1:?usage: tools/gif.sh <shot-out-dir> [fps=10]}; fps=${2:-10}
[ -d "$dir" ] || { echo "gif: not a directory: $dir" >&2; exit 1; }
[[ $fps =~ ^[0-9]+([.][0-9]+)?$ && ! $fps =~ ^0+([.]0*)?$ ]] || { echo "gif: fps must be a positive number (got '$fps')" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "gif: ffmpeg not found" >&2; exit 1; }
cd "$dir"   # relative names from here on: a glob pattern with an odd directory name cannot go wrong
shopt -s nullglob
made=0
for cam in wide close; do
  frames=(fv-shot-anim-"$cam"-*.png)
  n=${#frames[@]}
  if [ "$n" -eq 0 ]; then echo "gif: no $cam frames (fv-shot-anim-$cam-*.png) in $dir, skipped" >&2; continue; fi
  gif=fleet-view-anim-$cam.gif; sheet=fleet-view-anim-$cam-sheet.png
  ffmpeg -nostdin -v error -y -framerate "$fps" -pattern_type glob -i "fv-shot-anim-$cam-*.png" \
    -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 "$gif"
  step=$(( (n + 11) / 12 ))
  ffmpeg -nostdin -v error -y -pattern_type glob -i "fv-shot-anim-$cam-*.png" \
    -vf "select='not(mod(n,$step))',scale=480:-1:flags=lanczos,tile=4x3:padding=4:margin=4" -frames:v 1 "$sheet"
  echo "$cam: $n frames at $fps fps -> $gif ($(du -h "$gif" | cut -f1)), $sheet (frame step $step)"
  made=$((made + 1))
done
[ "$made" -gt 0 ] || { echo "gif: no frames found in $dir" >&2; exit 1; }
