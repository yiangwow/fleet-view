-- Cargo bay / hub connection pieces (docs/bay-connections.md): lattice masks, bridges, piece choice.
package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path
local snapshot = require("scripts.snapshot")
local bays = require("scripts.bays")

local function bay(x, y) return {name = "cargo-bay", type = "cargo-bay", x = x, y = y, w = 4, h = 4} end
local function hub(x, y) return {name = "space-platform-hub", type = "space-platform-hub", x = x, y = y, w = 8, h = 8} end

-- {"x,y" -> mask} of the conn list; centre (0, 0) so x, y are plain lattice coordinates
local function masks(ents)
  local conn, br = snapshot.conn_tiles(ents, 0, 0)
  local m, n = {}, 0
  for i = 1, #conn, 3 do m[conn[i] .. "," .. conn[i + 1]] = conn[i + 2]; n = n + 1 end
  return m, n, br
end
local function bridge_list(br)
  local out = {}
  for i = 1, #br, 3 do out[#out + 1] = br[i] .. "," .. br[i + 1] .. ":" .. br[i + 2] end
  table.sort(out)
  return table.concat(out, " ")
end

return {
  single_bay_is_a_3x3_ring = function()
    local m, n, br = masks({bay(0, 0)})
    assert_eq(n, 8, "ring of 8, the middle point (255) is left out")
    assert_eq(m["-1,-1"], 8 + 16 + 32, "top-left corner: R, BR, B")
    assert_eq(m["0,-1"], 8 + 16 + 32 + 64 + 128, "top edge")
    assert_eq(m["1,1"], 1 + 2 + 128, "bottom-right corner: TL, T, L")
    assert_eq(m["-1,0"], 2 + 4 + 8 + 16 + 32, "left edge")
    assert_eq(#br, 0)
  end,
  no_bays_no_pieces = function()
    local conn, br = snapshot.conn_tiles({{name = "pipe", type = "pipe", x = 0.5, y = 0.5, w = 1, h = 1}}, 0, 0)
    assert_eq(#conn, 0); assert_eq(#br, 0)
  end,
  bay_next_to_hub = function()
    -- hub (0,-2) = tiles -4..4 x -6..2, bay (6,-2) = tiles 4..8 x -4..0: they share 4 tiles of edge
    local m, n, br = masks({hub(0, -2), bay(6, -2)})
    assert_eq(bridge_list(br), "4,-2:2", "one wide horizontal bridge in the middle of the shared edge")
    assert_eq(m["3,-2"], nil, "interior points (mask 255) are not listed")
  end,
  row_of_two_bays = function()
    local m, n, br = masks({bay(0, 0), bay(4, 0)})
    assert_eq(bridge_list(br), "2,0:2")
    -- 7 x 3 lattice, only the middle row's inner points are interior (255)
    assert_eq(n, 7 * 3 - 5)
    assert_eq(m["2,0"], nil, "seam point (2,0) has all 8 neighbours")
    assert_eq(m["2,-1"], 8 + 16 + 32 + 64 + 128, "top wall across the seam")
  end,
  stacked_bays_vertical_bridge = function()
    local _, _, br = masks({bay(0, 0), bay(0, 4)})
    assert_eq(bridge_list(br), "0,2:4")
  end,
  offset_seams_are_narrow = function()
    -- side by side, shifted by 2: shared edge 2 tiles; by 1: 3 tiles; both < 4 = narrow
    local _, _, b2 = masks({bay(0, 0), bay(4, 2)})
    assert_eq(bridge_list(b2), "2,1:1")
    local _, _, b1 = masks({bay(0, 0), bay(4, 1)})
    assert_eq(bridge_list(b1), "2,0.5:1")
  end,
  cross_of_four_bays = function()
    local _, _, br = masks({bay(0, 0), bay(4, 0), bay(0, 4), bay(4, 4)})
    assert_eq(bridge_list(br), "0,2:4 2,0:2 2,2:5 2,4:2 4,2:4")
  end,
  diagonal_only_does_not_connect = function()
    local m, n, br = masks({bay(0, 0), bay(4, 4)})
    assert_eq(#br, 0)
    assert_eq(n, 16, "two separate rings")
  end,
  gap_does_not_connect = function()
    local _, n, br = masks({bay(0, 0), bay(5, 0)})
    assert_eq(#br, 0); assert_eq(n, 16)
  end,
  model_centre_is_subtracted = function()
    local conn = snapshot.conn_tiles({bay(10, 20)}, 10, 20)
    local seen = {}
    for i = 1, #conn, 3 do seen[conn[i] .. "," .. conn[i + 1]] = true end
    assert(seen["-1,-1"] and seen["1,1"])
  end,
  build_model_has_conn_and_old_models_ok = function()
    local tiles = {}
    for x = -8, 8 do for y = -8, 8 do tiles[#tiles + 1] = {x = x, y = y} end end
    local m = snapshot.build_model(tiles, {bay(0, 0)}, 1)
    assert_eq(#m.conn, 24); assert_eq(#m.bridges, 0)
    -- a model stored by 0.4.4 has neither field: nothing in the code indexes them without a check
    m.conn, m.bridges = nil, nil
    assert_eq(m.conn, nil)
  end,

  -- piece choice with entries of the vanilla tileset_mapping
  piece_choice = function()
    local map = {["56"] = {5}, ["248"] = {1}, ["10"] = {7, 10}, ["254"] = {9}}
    local tiles = {[1] = {{"a", "b"}, {"c", "d"}}, [5] = {{"e", "f"}}, [7] = {{"g"}}, [9] = {{"h"}}, [10] = {{"i"}}}
    local out = bays.pieces({0, 0, 56, 1, 0, 248, 2, 0, 10, 3, 0, 255, 4, 0, 254, 5, 0, 7}, map, tiles)
    assert_eq(#out / 3, 5, "56, 248, 10 (two pieces), 254; 255 and unmapped 7 draw nothing")
    assert(out[3] == "e" or out[3] == "f")
  end,
  group_alternates_along_a_wall = function()
    local map = {["248"] = {1}}
    local tiles = {[1] = {{"a"}, {"b"}}}
    local out = bays.pieces({0, 0, 248, 1, 0, 248, 2, 0, 248, 3, 0, 248}, map, tiles)
    assert_eq(out[3], "a"); assert_eq(out[6], "b"); assert_eq(out[9], "a"); assert_eq(out[12], "b")
  end,
  bridge_pieces_pick_by_kind = function()
    local br = {[1] = {"n"}, [2] = {"w1", "w2"}, [5] = {"x1", "x2"}}
    local out = bays.bridge_pieces({0, 0, 1, 2, 0, 2, 4, 4, 5, 6, 6, 3}, br)
    assert_eq(#out / 3, 3, "kind 3 has no sprite: skipped")
    assert_eq(out[3], "n")
    assert(out[6] == "w1" or out[6] == "w2")
  end,
}
