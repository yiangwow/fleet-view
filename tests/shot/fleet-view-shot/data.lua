-- order3 shot mode (2026-11-15): the red signal icon with a prototype `shift`, to test whether a shifted picture
-- sorts by its target or by where it is drawn. 64 px at scale 0.5 = one tile; the shift is in tiles.
local function red(name, dy)
  return {type = "sprite", name = name, filename = "__base__/graphics/icons/signal/signal_red.png",
    width = 64, height = 64, x = 0, y = 0, scale = 0.5, shift = {0, dy}}
end
data:extend{red("fvt-red-s7", 7), red("fvt-red-s10", 10), red("fvt-red-s40", 40)}
-- order5 (2026-11-15): 0.4.10's floor (simple sprite, shift 280, runtime scale 0.08) vanished while buildings (layered,
-- shift 100, runtime 0.16) drew. Same picture as fv-t2-0 (128 px floor piece) as: simple scale 1 ("s"), simple scale 0.5
-- ("h"), layered scale 1 ("l"); shift 20..280 tiles.
local function sq(name, dy, scale, layered)
  local p = {filename = "__space-age__/graphics/terrain/space-platform/space-platform-2x2.png", x = 0, y = 0,
    width = 128, height = 128, scale = scale, shift = {0, dy}}
  if layered then return {type = "sprite", name = name, layers = {p}} end
  p.type = "sprite"; p.name = name
  return p
end
local list = {}
for _, dy in ipairs{20, 100, 150, 200, 280} do
  list[#list + 1] = sq("fvt-sq-s" .. dy, dy, 1)
  list[#list + 1] = sq("fvt-sq-h" .. dy, dy, 0.5)
  list[#list + 1] = sq("fvt-sq-l" .. dy, dy, 1, true)
end
data:extend(list)
-- order8 (2026-11-15): culling rule = target within the view grown by max(width, height) px / 2 x runtime scale (tiles),
-- shift ignored (orders 6-7). Does an extra transparent layer (graphics/pad.png 256 px, drawn tiny) widen that margin?
local piece = {filename = "__space-age__/graphics/terrain/space-platform/space-platform-1x1.png", x = 0, y = 0,
  width = 64, height = 64, scale = 0.5, shift = {0, 66}}
local pad = {filename = "__fleet-view-shot__/graphics/pad.png", width = 256, height = 256, scale = 1 / 64, shift = {0, 66}}
data:extend{
  {type = "sprite", name = "fvt-f64-s66", filename = piece.filename, x = 0, y = 0, width = 64, height = 64, scale = 0.5, shift = {0, 66}},
  {type = "sprite", name = "fvt-f64-p66", layers = {piece, pad}},
  {type = "sprite", name = "fvt-f64-l66", layers = {table.deepcopy(piece)}},
}
-- order8b: the fully transparent pad changed nothing (trimmed away at load?). pad-corners.png = the same 256 px with
-- alpha 1/255 in the 4 corner pixels (not trimmable). Pad as the 2nd layer ("c2") and as the 1st ("c1").
local padc = {filename = "__fleet-view-shot__/graphics/pad-corners.png", width = 256, height = 256, scale = 1 / 64, shift = {0, 66}}
data:extend{
  {type = "sprite", name = "fvt-f64-c2", layers = {table.deepcopy(piece), padc}},
  {type = "sprite", name = "fvt-f64-c1", layers = {table.deepcopy(padc), table.deepcopy(piece)}},
  {type = "sprite", name = "fvt-f64-c2big", layers = {table.deepcopy(piece),
    {filename = "__fleet-view-shot__/graphics/pad-corners.png", width = 256, height = 256, scale = 0.5, shift = {0, 66}}}},
}
-- planet mode (2026-11-16, portal versuffer "Make departure/arrival render sync to planets": moons ~1000 km from their
-- planet, the planet disappears much faster than Fleet View's ships). A short test route from nauvis, so the planet
-- backdrop's slide can be filmed against km flown on a 1000 km route and on the 15000 km nauvis-vulcanus.
data:extend{
  {type = "space-location", name = "fvt-moon", icon = "__space-age__/graphics/icons/solar-system-edge.png",
    starmap_icon = "__space-age__/graphics/icons/starmap-solar-system-edge.png", starmap_icon_size = 512,
    order = "z[fvt-moon]", subgroup = "planets", gravity_pull = 10, distance = 15.5, orientation = 0.27, magnitude = 0.3},
  {type = "space-connection", name = "nauvis-fvt-moon", subgroup = "planet-connections", from = "nauvis", to = "fvt-moon",
    order = "z", length = 1000},
}
-- subpx mode (2026-11-16, 0.5.0 float research, portal Maxorio: "there's a point in doing sub-pixel movement"): a plain
-- floor piece, no shift, to see whether the renderer draws positions between whole screen pixels.
data:extend{{type = "sprite", name = "fvt-sub", filename = "__space-age__/graphics/terrain/space-platform/space-platform-2x2.png",
  x = 0, y = 0, width = 128, height = 128, scale = 0.5}}
