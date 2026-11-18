-- Data stage: sprites for the platform edge pieces (scripts/edges.lua): fv-b-<kind>-<row>-<v>, one 64x512 frame of the
-- foundation's background transition sheets.
local edges = require("scripts.edges")
local M = {}
function M.make()
  for kind, k in ipairs(edges.KINDS) do
    for row = 0, k.rows - 1 do
      for v = 0, k.nv - 1 do
        data:extend({ {
          type = "sprite", name = edges.sprite_name(edges.code(kind, row, v)),
          filename = "__space-age__/graphics/terrain/space-platform/space-platform-" .. k.sheet .. "-background.png",
          x = edges.FRAME_W * edges.column(kind, v), y = edges.FRAME_H * row,
          width = edges.FRAME_W, height = edges.FRAME_H, scale = 0.5,   -- drawn at runtime S (sort-key shift limit)
        } })
      end
    end
  end
end
return M
