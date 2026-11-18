-- Sort-key shifts (scripts/sortkey.lua, docs/layer-order.md).
package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path
local sortkey = require("scripts.sortkey")
local edges = require("scripts.edges")
local S = 0.16

-- key offset above the picture in model tiles = folded y / S (the target moves up by the fold)
local function up(name, xs, ys, o) local x, y = sortkey.fold(name, xs, ys, o); return x / S, y / S end

return {
  rotate_matches_the_measured_turn = function()
    local x, y = sortkey.rotate(0, 7, 0.25)   -- GUI test: shift (0, 7) at orientation 0.25 drew at (-7, 0)
    assert_near(x, -7, 1e-9); assert_near(y, 0, 1e-9)
  end,
  buildings_sort_TOP_above_their_picture = function()
    local x, y = up("fv-e-assembling-machine-2", S, S)
    assert_near(x, 0, 1e-9); assert_near(y, sortkey.TOP, 1e-9)
    assert_near(select(2, up("fv-c-1-2-0", S, S)), sortkey.TOP, 1e-9)
    assert_near(select(2, up("fv-arm-inserter", S, S)), sortkey.TOP, 1e-9)
  end,
  floor_sorts_FLOOR_above_and_edges_at_their_tile_row = function()
    local _, y = up("fv-t2-3", S, S)
    assert_near(y, sortkey.FLOOR, 1e-9)
    local _, e = up("fv-b-1-0-0", S, S)
    assert_near(e - edges.HANG, sortkey.FLOOR, 1e-9)   -- picture HANG below the tile, key FLOOR above the tile
    -- floor must sort before any building it overlaps: a building sprite reaches at most ~10 model tiles below its centre
    assert(sortkey.FLOOR >= sortkey.TOP + 12, "floor must sort clearly before buildings")
  end,
  dots_and_rects_sort_TOP_above = function()
    assert_near(select(2, up("fv-dot", S, S)), sortkey.TOP, 1e-9)
    assert_near(select(2, up("fv-glow", S, S)), sortkey.TOP, 1e-9)
    for h = 1, 10 do
      local n = sortkey.px_name(h)
      assert_near(select(2, up(n, S * 4, h * S * 4)), sortkey.TOP, 1e-9, n)
    end
    assert_eq(sortkey.px_name(0.5), "fv-px-1"); assert_eq(sortkey.px_name(2.5), "fv-px-3"); assert_eq(sortkey.px_name(40), "fv-px-10")
    -- a non-integer height lands between TOP/2 and TOP, never above the floor's key
    local y = select(2, up("fv-px-3", S * 4, 2.5 * S * 4))
    assert(y > sortkey.TOP / 2 and y <= sortkey.TOP, tostring(y))
  end,
  turned_copies_point_straight_up_after_rotation = function()
    for q = 1, 3 do
      local o = q / 4
      local name = sortkey.turned("fv-e-transport-belt", o)
      assert_eq(name, "fv-e-transport-belt-fvq" .. q)
      local x, y = up(name, S, S, o)
      assert_near(x, 0, 1e-9, name); assert_near(y, sortkey.TOP, 1e-9, name)
    end
    assert_eq(sortkey.turned("fv-e-pipe", nil), nil)
    assert_eq(sortkey.turned("fv-e-pipe", 0), nil)
    assert_eq(sortkey.turned("fv-e-pipe", 0.1), nil)
  end,
  base_sprite_turned_keeps_its_picture = function()
    -- no turned copy (e.g. a modded type): the fold still turns with the sprite, so the picture is exact
    local x, y = sortkey.fold("fv-e-pipe", S, S, 0.5)
    assert_near(x, 0, 1e-9); assert_near(y, -sortkey.TOP * S, 1e-9)
  end,
  every_shift_stays_under_the_engine_limit = function()
    -- GUI test order5: a prototype shift of 280 tiles is not drawn at all, 200 is
    local names = { "fv-t1-0", "fv-t2-15", "fv-b-9-3-1", "fv-dot", "fv-glow", "fv-e-x", "fv-c-1-1-3", "fv-arm-inserter",
      "fv-e-transport-belt-fvq1", "fv-e-pipe-sh-fvq3" }
    for n = 1, sortkey.PX_MAX do names[#names + 1] = "fv-px-" .. n end
    for _, name in ipairs(names) do
      local x, y = sortkey.shift(name)
      assert(math.sqrt(x * x + y * y) <= sortkey.MAX_SHIFT, name .. " shift " .. y)
      assert(math.sqrt(x * x + y * y) > 0, name .. " has no shift")
    end
    assert(sortkey.MAX_SHIFT < 256)
    -- the pad's culling margin (half its pixels) covers the biggest shift with the 1.5x trim slack
    assert(sortkey.PAD.px / 2 >= 1.5 * sortkey.MAX_SHIFT)
  end,
  icons_are_not_shifted = function()
    local x, y = sortkey.fold("entity/stone-furnace", 0.3, 0.3, 0.25)
    assert_eq(x, 0); assert_eq(y, 0)
  end,
}
