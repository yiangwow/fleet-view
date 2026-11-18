-- Platform edge art: which piece goes on which empty tile (scripts/edges.lua).
package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path
local snapshot = require("scripts.snapshot")
local edges = require("scripts.edges")

local function build(rows)   -- rows of "#" (deck) and "." ; top-left = tile (0, 0)
  local tiles = {}
  for y, line in ipairs(rows) do
    for x = 1, #line do if line:sub(x, x) == "#" then tiles[#tiles + 1] = {x = x - 1, y = y - 1} end end
  end
  return snapshot.build_model(tiles, {}, 0), #tiles
end
-- {"kind-row" -> count} of a model's edge list, plus the total
local function count(m)
  local c, n = {}, 0
  for i = 1, #m.edge, 3 do
    local kind, row = edges.parts(m.edge[i + 2])
    local k = kind .. "-" .. row
    c[k] = (c[k] or 0) + 1; n = n + 1
  end
  return c, n
end

return {
  lone_tile = function()
    local m = build({ "#" })
    local c, n = count(m)
    -- 4 sides + 4 outer corners
    assert_eq(n, 8)
    for r = 0, 3 do assert_eq(c["1-" .. r], 1, "side row " .. r) end
    for r = 0, 3 do assert_eq(c["4-" .. r], 1, "outer corner row " .. r) end
  end,
  block_has_sides_and_four_corners = function()
    local m = build({ "###", "###", "###" })
    local c, n = count(m)
    assert_eq(n, 12 + 4)
    assert_eq(c["1-0"], 3, "deck to the north of 3 tiles")
    for r = 0, 3 do assert_eq(c["4-" .. r], 1) end
    -- every piece sits on an empty tile (centre 1.5, 1.5 -> offsets of +-2 from the middle)
    for i = 1, #m.edge, 3 do
      local x, y = m.edge[i] + 1.5, m.edge[i + 1] + 1.5   -- back to tile coords + 0.5
      assert(x < 0.6 or x > 3 or y < 0.6 or y > 3, "piece on a deck tile")
    end
  end,
  notch_is_an_inner_corner = function()
    local m = build({ "###", "##.", "###" })   -- the empty tile (2, 1) has deck N, S, W: a u
    local c = count(m)
    assert_eq(c["5-3"] or c["5-0"] or c["5-1"] or c["5-2"], 1, "one u piece")
    local m2 = build({ "##", "#." })   -- empty (1, 1): deck N and W = inner corner
    local c2 = count(m2)
    assert_eq(c2["3-" .. edges.INNER_ROW[1 + 8]], 1)
  end,
  one_wide_strip_is_double_side = function()
    local m = build({ ".#.", ".#.", ".#." })
    local c = count(m)
    assert_eq(c["1-" .. edges.SIDE_ROW[2]], 3, "empty tiles left of the strip have deck to the east")
    assert_eq(c["1-" .. edges.SIDE_ROW[8]], 3, "empty tiles right of the strip have deck to the west")
  end,
  gap_between_decks_is_double = function()
    local m = build({ "#.#" })
    local c = count(m)
    assert_eq(c["2-1"], 1, "deck W and E")
    local m2 = build({ "#", ".", "#" })
    assert_eq(count(m2)["2-0"], 1)
  end,
  enclosed_hole_has_no_piece = function()
    local m = build({ "###", "#.#", "###" })
    local _, n = count(m)
    -- outside ring only: 12 sides + 4 corners; the hole (deck on all four sides) has no background piece
    assert_eq(n, 16)
  end,
  sprite_names_and_codes_round_trip = function()
    for kind, k in ipairs(edges.KINDS) do
      for row = 0, k.rows - 1 do
        for v = 0, k.nv - 1 do
          local code = edges.code(kind, row, v)
          local a, b, c = edges.parts(code)
          assert_eq(a, kind); assert_eq(b, row); assert_eq(c, v)
          assert(edges.sprite_name(code):match("^fv%-b%-%d%-%d%-%d$"))
          assert(edges.column(kind, v) < k.count)
        end
      end
    end
  end,
  every_classified_code_has_a_sprite = function()
    for mask = 0, 255 do
      for _, code in ipairs(edges.classify(mask, 5)) do
        local kind, row, v = edges.parts(code)
        local k = edges.KINDS[kind]
        assert(k and row < k.rows and v < k.nv, "bad code " .. code .. " for mask " .. mask)
      end
    end
  end,
  piece_count_is_about_the_perimeter = function()
    local rows = {}
    for y = 1, 20 do rows[y] = string.rep("#", 30) end
    local m = build(rows)
    local _, n = count(m)
    assert_eq(n, 2 * 30 + 2 * 20 + 4)
  end,
}
