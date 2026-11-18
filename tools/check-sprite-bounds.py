#!/usr/bin/env python3
"""Checks that every fv-e-* sprite of a data.raw dump stays inside its PNG (headless never loads images, so an
out-of-range x/y/width/height only crashes in a GUI load).
usage: tools/check-sprite-bounds.py <data-raw-dump.json> [factorio data dir]
Make the dump with:  factorio --dump-data --config <ini with read-data/write-data> --mod-directory <dir with fleet-view>
(the dump lands in <write-data>/script-output/data-raw-dump.json). Reads PNG sizes from the IHDR header; only
__base__ / __space-age__ / __elevated-rails__ / __quality__ paths are checked (others are listed as skipped)."""
import json, os, struct, sys

dump = sys.argv[1]
root = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/Steam/steamapps/common/Factorio/data")
sprites = json.load(open(dump)).get("sprite", {})
sizes = {}

def png_size(path):
    if path not in sizes:
        with open(path, "rb") as f:
            h = f.read(24)
        sizes[path] = struct.unpack(">II", h[16:24])
    return sizes[path]

checked = bad = skipped = 0
for name, sp in sorted(sprites.items()):
    if not name.startswith("fv-e-"):
        continue
    for l in sp.get("layers", [sp]):
        fn = l.get("filename", "")
        if not fn.startswith("__"):
            continue
        mod, rel = fn[2:].split("__/", 1)
        path = os.path.join(root, mod, rel)
        if not os.path.exists(path):
            skipped += 1
            continue
        w, h = l.get("width"), l.get("height")
        size = l.get("size")
        if isinstance(size, list):
            w, h = size[0], size[1]
        elif isinstance(size, (int, float)):
            w = h = size
        x, y = l.get("x", 0), l.get("y", 0)
        pw, ph = png_size(path)
        checked += 1
        if w is None or h is None or x < 0 or y < 0 or x + w > pw or y + h > ph:
            bad += 1
            print("OUT OF BOUNDS", name, fn, "x,y,w,h", x, y, w, h, "png", pw, ph)
print("checked %d layers, %d out of bounds, %d skipped (file not found)" % (checked, bad, skipped))
sys.exit(1 if bad else 0)
