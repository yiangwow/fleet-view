-- Sort keys (0.4.10, docs/layer-order.md; portal report Qazerowl "Rendering on top of edges").
-- Render layers 0-2 draw script sprites sorted by the y of their TARGET (lower = on top), and the deck's hanging
-- underside joins layer 1's sort at the first empty row under the deck. A ship drawn below that row therefore drew
-- over it. A sprite prototype `shift` moves the picture but not the sort key (GUI test 2026-11-15), so every ship
-- sprite carries a downward shift and is targeted that much higher: same picture, key far above it. Then the whole
-- ship sorts under the viewer's hanging edges, and the floor (bigger shift) sorts under the ship's own buildings.
-- Used by the data stage (data-final-fixes.lua writes the shifts) and by draw.lua (moves the targets).
-- The runtime scales a shift by the sprite's x_scale / y_scale and turns it with `orientation` (GUI test).
local edges = require("scripts.edges")

local M = {}

-- How far above its picture a sprite sorts, in model tiles (times the ship's drawn scale on screen: geom.SCALE 0.16 x
-- k 0.85..1.15 x travel shrink 0.53..1 = 0.072..0.184). TOP: 50 = 6.8..9.2 screen tiles for a parked ship (3.6 at the
-- smallest while travelling), more than the underside art hangs below a deck edge (about 3-4.5). FLOOR - TOP: more
-- than any building sprite reaches below its centre plus a floor piece.
M.TOP = 50
M.FLOOR = 66
-- Two engine limits (GUI tests 2026-11-15, docs/layer-order.md):
-- 1. A prototype shift above about 256 tiles is not drawn at all (order5: 200 drawn, 280 missing).
-- 2. Culling ignores the shift: a sprite is drawn only while its TARGET is within the view grown by about half the
--    FIRST layer's pixel size x the runtime scale (orders 6-8). A shifted sprite whose picture is near the top of the
--    screen has its target above the view; small sprites (belts, 1x1 floor, lights) vanished there when zoomed in.
--    The size that counts is after the loader trims transparent borders: the platform edge frames are 64x512 but
--    mostly empty, and the top-edge pieces vanished (art shot 2026-11-15). So data-final-fixes puts PAD (a 256 px
--    picture, transparent but for alpha 1/255 corner pixels so it cannot be trimmed, drawn at 1/64 scale) in front of
--    EVERY shifted sprite as its first layer: margin 128 x scale, which covers any shift up to MAX_SHIFT (order8b).
--    The loader stores the pad once (atlas sizes unchanged with 320 padded sprites).
-- Floor, edge and dot sprites carry their size in the prototype `scale` and are drawn at runtime scale S like the
-- entities: the shift is multiplied by the runtime scale, so a sprite drawn at S / 4 would need 4x the shift.
M.MAX_SHIFT = 85
M.PAD = { filename = "__fleet-view__/graphics/pad.png", px = 256, scale = 1 / 64 }

-- Sizes of the dot sprites (data.lua sets them as the prototype scale, draw.lua draws them at S).
M.LIGHT_SIZE = 0.5   -- running light diameter, model tiles
M.GLOW_TILES = 1.4   -- lamp glow diameter, model tiles (3 smeared a lamp row into one white cloud, merge shot 2026-11-12)
-- fv-px rects (loaders, gates): y_scale = h * S * 4, so the shift is per height: fv-px-<n> for n = 1..PX_MAX.
M.PX_MAX = 10
-- Entity types drawn with `orientation` (snapshot.lua ROT_BY_DIR + LINE): their fv-e-<name> and fv-e-<name>-sh get
-- turned copies `-fvq<1..3>` whose shift is pre-turned, so it points down again once the sprite is rotated.
-- Inserter arms (fv-arm-*) are always turned (by direction) and get them too.
M.ROTATED_TYPES = { "transport-belt", "underground-belt", "splitter", "pipe", "wall" }

local function starts(s, p) return s:sub(1, #p) == p end

-- Turns vector (x, y) by orientation `o` (0..1, clockwise on screen, y down): measured, shift (0, 7) at 0.25 drew at (-7, 0).
function M.rotate(x, y, o)
  if not o or o == 0 then return x, y end
  local a = 2 * math.pi * o
  local c, s = math.cos(a), math.sin(a)
  return x * c - y * s, x * s + y * c
end

-- Downward shift (prototype tiles) of an UNTURNED fleet-view sprite, by name; 0 for anything else (entity icons).
local function base_shift(name)
  if starts(name, "fv-t") then return M.FLOOR end                    -- floor: y_scale = S * floor_scale (prototype scale 0.5)
  if starts(name, "fv-b-") then return M.FLOOR + edges.HANG end      -- edge art (S, prototype scale 0.5): drawn HANG below
  local n = name:match("^fv%-px%-(%d+)$")                            --   its tile, sorts at the tile row like the game
  if n then return M.TOP / (4 * tonumber(n)) end
  if name == "fv-dot" or name == "fv-glow" then return M.TOP end     -- y_scale = S (size in the prototype scale)
  if starts(name, "fv-e-") or starts(name, "fv-c-") or starts(name, "fv-arm-") then return M.TOP end
  return 0
end

-- The shift vector {x, y} (prototype tiles) the data stage gives sprite `name`. A turned copy "<base>-fvq<q>" is drawn
-- with orientation q/4: its vector is the base one turned back by q/4.
function M.shift(name)
  local base, q = name:match("^(.*)%-fvq(%d)$")
  if base then
    local x, y = M.rotate(0, base_shift(base), -tonumber(q) / 4)
    return x, y
  end
  return 0, base_shift(name)
end

-- Name of the turned copy for orientation `o` (a quarter turn 0.25 / 0.5 / 0.75), or nil.
function M.turned(name, o)
  if not o then return nil end
  local q = math.floor(o * 4 + 0.5) % 4
  if q == 0 or math.abs(o * 4 - math.floor(o * 4 + 0.5)) > 1e-6 then return nil end
  return name .. "-fvq" .. q
end

-- fv-px variant for a rect of height h (model tiles).
function M.px_name(h)
  local n = math.max(1, math.min(M.PX_MAX, math.ceil(h - 1e-9)))
  return "fv-px-" .. n
end

-- Where to move the target so the picture stays put: the shift as drawn (scaled by xs / ys, turned by `o`), in the
-- same units as xs / ys. Subtract it from the picture offset.
function M.fold(name, xs, ys, o)
  local x, y = M.shift(name)
  return M.rotate(x * xs, y * ys, o)
end

return M
