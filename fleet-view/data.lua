-- Anchor entity (validated in the Task 1 spike, docs/spike-findings.md): invisible, non-colliding,
-- unselectable. One per (viewer, other ship); every picture of that ship targets it, so one
-- teleport moves the whole ship.
data:extend{
  {
    type = "simple-entity-with-owner", name = "fv-anchor",
    picture = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    collision_mask = {layers = {}}, selectable_in_game = false,
    flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "placeable-off-grid",
             "no-automated-item-removal", "no-automated-item-insertion"},
    hidden = true,
  },
  -- White square, tinted at draw time (fallback rects). 8x8 px.
  {type = "sprite", name = "fv-px", filename = "__fleet-view__/graphics/px.png", width = 8, height = 8},
  -- Soft round white dot (running lights), tinted at draw time. 64x64 px = LIGHT_SIZE model tiles at runtime scale S
  -- (the size sits in the prototype scale so the sort-key shift stays small: scripts/sortkey.lua MAX_SHIFT).
  {type = "sprite", name = "fv-dot", filename = "__fleet-view__/graphics/dot.png", width = 64, height = 64,
   scale = require("scripts.sortkey").LIGHT_SIZE / 2},
  -- same dot, additive blending (lamp glows: draw_light shows nothing on a platform, the sprite blend_mode is honoured)
  {type = "sprite", name = "fv-glow", filename = "__fleet-view__/graphics/dot.png", width = 64, height = 64, blend_mode = "additive",
   scale = require("scripts.sortkey").GLOW_TILES / 2},
}
-- Floor at true scale: variant i of the platform 1x1 (64 px = 1 tile at scale 0.5) and 2x2 (128 px) sheets. Drawn at
-- runtime scale S (0.4.10; was S / 2 at prototype scale 1: the sort-key shift would have been over the limit).
for i = 0, 15 do
  data:extend{
    {type = "sprite", name = "fv-t1-" .. i, filename = "__space-age__/graphics/terrain/space-platform/space-platform-1x1.png",
     x = 64 * i, y = 0, width = 64, height = 64, scale = 0.5},
    {type = "sprite", name = "fv-t2-" .. i, filename = "__space-age__/graphics/terrain/space-platform/space-platform-2x2.png",
     x = 128 * i, y = 0, width = 128, height = 128, scale = 0.5},
  }
end
-- Floor blocks (0.5.0): fv-t<4|8>-<v> = ONE sprite whose layers are the 2x2 pictures of a 4x4 / 8x8-tile block, at the
-- places and with the variants the lone fv-t2 pieces have (geom.floor_sub_variant), each drawn FLOOR_OVERLAP larger
-- like a lone piece (geom.floor_scale(2)), so the floor looks the same and costs 4x / 16x fewer render objects
-- (measured 2026-11-16, tests/bench/micro.sh: moving an attached object costs per OBJECT, hardly per layer).
-- Drawn at runtime scale S; the layer shifts are in prototype tiles and scale with it.
do
  local geom = require("scripts.geom")
  for _, n in ipairs(geom.FLOOR_BLOCKS) do
    for v = 0, 15 do
      local layers = {}
      for j = 0, n / 2 - 1 do
        for i = 0, n / 2 - 1 do
          layers[#layers + 1] = {filename = "__space-age__/graphics/terrain/space-platform/space-platform-2x2.png",
            x = 128 * geom.floor_sub_variant(v, i, j), y = 0, width = 128, height = 128,
            scale = 0.5 * geom.floor_scale(2), shift = {2 * i + 1 - n / 2, 2 * j + 1 - n / 2}}
        end
      end
      data:extend{{type = "sprite", name = "fv-t" .. n .. "-" .. v, layers = layers}}
    end
  end
end
-- fv-px for a rect of height n tiles (0.4.10): the sort-key shift scales with y_scale = h * S * 4, so each height gets
-- its own copy (data-final-fixes gives it the shift, scripts/sortkey.lua px_name picks it).
for n = 1, require("scripts.sortkey").PX_MAX do
  data:extend{{type = "sprite", name = "fv-px-" .. n, filename = "__fleet-view__/graphics/px.png", width = 8, height = 8}}
end
