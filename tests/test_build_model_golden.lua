-- build_model must give exactly the same model as the string-keyed version it replaced (0.4.2 perf work):
-- tests/golden/build_model.txt was written by that version from the layout below (holes, ragged edges,
-- horizontal + vertical pipe/wall runs, rotated belts, coloured rects). Regenerate only on a deliberate change:
--   lua5.2 tests/test_build_model_golden.lua --write
package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path
local snapshot = require("scripts.snapshot")

local function layout()
  local tiles, ents = {}, {}
  for y = -20, 25 do
    for x = -30, 31 do
      local hole = (x > -5 and x < 3 and y > 0 and y < 6) or ((x * 7 + y * 13) % 11 == 0 and math.abs(x) > 25)
      if not hole then tiles[#tiles + 1] = {x = x, y = y} end
    end
  end
  for x = -20, -10 do ents[#ents + 1] = {name = "pipe", type = "pipe", x = x + 0.5, y = -10.5, w = 1, h = 1} end
  for y = -15, -5 do ents[#ents + 1] = {name = "pipe", type = "pipe", x = 15.5, y = y + 0.5, w = 1, h = 1} end
  ents[#ents + 1] = {name = "pipe", type = "pipe", x = 0.5, y = 0.5 - 18, w = 1, h = 1}
  for x = 5, 12 do ents[#ents + 1] = {name = "stone-wall", type = "wall", x = x + 0.5, y = 20.5, w = 1, h = 1} end
  for i = 0, 15 do
    ents[#ents + 1] = {name = "transport-belt", type = "transport-belt", x = -25.5 + i, y = 12.5, w = 1, h = 1, dir = (i * 4) % 16}
  end
  ents[#ents + 1] = {name = "splitter", type = "splitter", x = 3, y = -3.5, w = 2, h = 1, dir = 4}
  ents[#ents + 1] = {name = "loader", type = "loader", x = 8, y = -8.5, w = 1, h = 2}
  for i = 0, 9 do
    ents[#ents + 1] = {name = "assembling-machine-2", type = "assembling-machine", x = -10.5 + (i % 5) * 4, y = 15.5 - math.floor(i / 5) * 4, w = 3, h = 3}
  end
  ents[#ents + 1] = {name = "space-platform-hub", type = "space-platform-hub", x = 0, y = 0, w = 8, h = 8}
  return tiles, ents
end

local function ser(v)
  if type(v) == "number" then return string.format("%.10g", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function model_text()
  local tiles, ents = layout()
  local m = snapshot.build_model(tiles, ents, 5)
  m.conn, m.bridges, m.edge, m.glows = nil, nil, nil, nil   -- 0.4.5 fields (test_bays.lua), edge art (test_edges.lua), glows (test_shape_art.lua); the golden covers everything older
  return ser(m)
end

local GOLDEN = "tests/golden/build_model.txt"
if arg and arg[1] == "--write" then
  local f = assert(io.open(GOLDEN, "w")); f:write(model_text()); f:close(); print("wrote " .. GOLDEN)
  return
end

return {
  build_model_matches_golden = function()
    local f = assert(io.open(GOLDEN, "r")); local want = f:read("*a"); f:close()
    assert(model_text() == want, "build_model output differs from " .. GOLDEN)
  end,
}
