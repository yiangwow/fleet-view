local geom = require("scripts.geom")
local snapshot = require("scripts.snapshot")

local function tiles_rect(x0, y0, w, h)
  local t = {}
  for y = y0, y0 + h - 1 do for x = x0, x0 + w - 1 do t[#t + 1] = {x = x, y = y} end end
  return t
end

local function area(rects) local a = 0; for _, r in ipairs(rects) do a = a + r.w * r.h end; return a end

return {
  centre_is_tile_centroid = function()
    local m = snapshot.build_model(tiles_rect(10, 20, 4, 2), {}, 7)
    assert_near(m.centre.x, 12, 1e-9)   -- tile centres 10.5..13.5
    assert_near(m.centre.y, 21, 1e-9)   -- 20.5, 21.5
    assert_eq(m.tick, 7)
  end,
  rects_cover_tiles_relative_to_centre = function()
    local m = snapshot.build_model(tiles_rect(10, 20, 4, 2), {}, 0)
    assert_eq(area(m.rects), 8)
    assert_near(m.rects[1].x, -2, 1e-9)
    assert_near(m.rects[1].y, -1, 1e-9)
  end,
  empty_tiles_gives_nil = function()
    assert_eq(snapshot.build_model({}, {}, 0), nil)
  end,
  belts_walls_pipes_become_sprite_ents = function()
    local ents = {
      {name = "transport-belt", type = "transport-belt", x = 10.5, y = 20.5, w = 1, h = 1, dir = 4},
      {name = "stone-wall", type = "wall", x = 11.5, y = 20.5, w = 1, h = 1},
      {name = "pipe", type = "pipe", x = 12.5, y = 20.5, w = 1, h = 1},
      {name = "assembling-machine-2", type = "assembling-machine", x = 12, y = 21, w = 3, h = 3},
      {name = "loader", type = "loader", x = 13.5, y = 20.5, w = 1, h = 1},
    }
    local m = snapshot.build_model(tiles_rect(10, 20, 4, 2), ents, 0)
    assert_eq(#m.ents, 4)
    assert_eq(#m.crects, 1)   -- only the loader has no graphic and stays a rect
    local c = m.crects[1].color
    assert(c[1] - c[3] < 0.15, "fallback colour must be desaturated")
    assert_eq(m.ents[#m.ents].name, "assembling-machine-2")   -- buildings after belts/pipes/walls
    assert_near(m.ents[#m.ents].x, 0, 1e-9)
  end,
  belt_rotation_from_direction = function()
    local function rot(dir)
      local m = snapshot.build_model(tiles_rect(0, 0, 3, 3), {{name = "b", type = "transport-belt", x = 1.5, y = 1.5, w = 1, h = 1, dir = dir}}, 0)
      return m.ents[1].rot
    end
    assert_near(rot(4), 0, 1e-9)      -- sprite frame 0 faces east
    assert_near(rot(0), 0.75, 1e-9)   -- north
    assert_near(rot(8), 0.25, 1e-9)   -- south
    assert_near(rot(12), 0.5, 1e-9)   -- west
  end,
  direction_kept_for_non_rot_entities = function()
    local function dir(ty, d)
      local m = snapshot.build_model(tiles_rect(0, 0, 4, 4), {{name = "x", type = ty, x = 2, y = 2, w = 3, h = 3, dir = d}}, 0)
      return m.ents[1].dir
    end
    assert_eq(dir("fusion-generator", 4), 4)
    assert_eq(dir("fusion-generator", 8), 8)
    assert_eq(dir("fusion-generator", 12), 12)
    assert_eq(dir("fusion-generator", 0), nil)     -- north = no dir
    assert_eq(dir("fusion-generator", nil), nil)   -- old stored models / no direction
    assert_eq(dir("fusion-generator", 2), nil)     -- not a cardinal direction
    assert_eq(dir("transport-belt", 4), nil)       -- turned by rot, never twice
    assert_eq(dir("splitter", 8), nil)
    assert_eq(dir("pipe", 4), nil)
  end,
  splitter_rotates_pipe_to_ground_keeps_its_direction = function()
    -- 0.4.8: pipe-to-ground has its own picture per direction (fv-e-<name>-<dir>), so it is never turned
    local m = snapshot.build_model(tiles_rect(0, 0, 4, 4), {
      {name = "s", type = "splitter", x = 1, y = 1.5, w = 2, h = 1, dir = 8},
      {name = "p", type = "pipe-to-ground", x = 3.5, y = 3.5, w = 1, h = 1, dir = 4},
      {name = "q", type = "pipe-to-ground", x = 2.5, y = 3.5, w = 1, h = 1, dir = 0},
    }, 0)
    for _, e in ipairs(m.ents) do
      if e.name == "s" then assert_near(e.rot, 0.5, 1e-9); assert_eq(e.dir, nil)
      elseif e.name == "p" then assert_near(e.rot, 0, 1e-9); assert_eq(e.dir, 4)
      else assert_near(e.rot, 0, 1e-9); assert_eq(e.dir, nil) end
    end
  end,
  pipes_and_walls_lie_along_their_neighbours = function()
    local function rots(ty, pts)
      local ents = {}
      for i, pt in ipairs(pts) do ents[i] = {name = "x" .. i, type = ty, x = pt[1], y = pt[2], w = 1, h = 1} end
      local m = snapshot.build_model(tiles_rect(0, 0, 6, 6), ents, 0)
      local out = {}
      for _, e in ipairs(m.ents) do out[e.name] = e.rot end
      return out
    end
    local r = rots("pipe", {{1.5, 1.5}, {2.5, 1.5}, {3.5, 1.5}})   -- horizontal run
    assert_near(r.x2, 0.25, 1e-9)
    r = rots("wall", {{1.5, 1.5}, {1.5, 2.5}, {1.5, 3.5}})         -- vertical run
    assert_near(r.x2, 0, 1e-9)
    r = rots("pipe", {{1.5, 1.5}})                                   -- lone piece
    assert_near(r.x1, 0, 1e-9)
  end,
  hub_and_cargo_bay_draw_before_everything_else = function()
    local ents = {
      {name = "assembling-machine-3", type = "assembling-machine", x = 1.5, y = 0.5, w = 3, h = 3},
      {name = "cargo-bay", type = "cargo-bay", x = 3.5, y = 3.5, w = 4, h = 4},
      {name = "pipe", type = "pipe", x = 0.5, y = 0.5, w = 1, h = 1},
      {name = "space-platform-hub", type = "space-platform-hub", x = 5.5, y = 5.5, w = 6, h = 6},
    }
    local m = snapshot.build_model(tiles_rect(0, 0, 8, 8), ents, 0)
    local order = {}
    for i, e in ipairs(m.ents) do order[i] = e.name end
    assert_eq(order[1] .. "," .. order[2], "cargo-bay,space-platform-hub")
    assert_eq(order[3], "pipe")
    assert_eq(order[4], "assembling-machine-3")
  end,
  lights_max_8_deterministic = function()
    local t = tiles_rect(0, 0, 30, 20)
    local a = snapshot.build_model(t, {}, 0)
    local b = snapshot.build_model(t, {}, 0)
    assert(#a.lights <= 8 and #a.lights > 0)
    assert_eq(#a.lights, #b.lights)
    for i, l in ipairs(a.lights) do assert_eq(l.x, b.lights[i].x); assert_eq(l.y, b.lights[i].y) end
  end,
  few_tiles_few_lights = function()
    local m = snapshot.build_model(tiles_rect(0, 0, 2, 2), {}, 0)
    assert(#m.lights <= 4)
  end,
  floor_pieces_are_2x2_with_1x1_leftovers = function()
    local ps = snapshot.floor_pieces({{x = -2, y = -1, w = 5, h = 3}})
    local n2, n1, tiles = 0, 0, 0
    for _, p in ipairs(ps) do
      if p.size == 2 then n2 = n2 + 1 else n1 = n1 + 1 end
      tiles = tiles + p.size * p.size
      assert(p.v >= 0 and p.v <= 15)
    end
    assert_eq(tiles, 15); assert_eq(n2, 2); assert_eq(n1, 7)   -- 4x2 in blocks, 1 col of 3 + 1 row of 4... = 15 tiles
    assert_eq(#snapshot.floor_pieces({{x = 0, y = 0, w = 8, h = 8}}), 16)
    local a, b = snapshot.floor_pieces({{x = 3, y = 4, w = 6, h = 6}}), snapshot.floor_pieces({{x = 3, y = 4, w = 6, h = 6}})
    for i, p in ipairs(a) do assert_eq(p.v, b[i].v) end
  end,
  floor_blocks_draw_the_same_2x2_pictures = function()
    -- 0.5.0: big blocks (8x8, 4x4) are ONE sprite whose layers are the 2x2 pictures the small pieces would have been.
    -- Expanding every block into its 2x2 sub-pieces (geom.floor_sub_variant) must give exactly the max = 2 result.
    local function expand(ps)
      local set, n = {}, 0
      for _, p in ipairs(ps) do
        if p.size <= 2 then
          set[p.x .. "," .. p.y .. "," .. p.size .. "," .. p.v] = true; n = n + 1
        else
          for j = 0, p.size / 2 - 1 do for i = 0, p.size / 2 - 1 do
            set[(p.x + 2 * i) .. "," .. (p.y + 2 * j) .. ",2," .. geom.floor_sub_variant(p.v, i, j)] = true; n = n + 1
          end end
        end
      end
      return set, n
    end
    for _, r in ipairs({{x = 0, y = 0, w = 8, h = 8}, {x = -2, y = -1, w = 5, h = 3}, {x = 3.5, y = -7.25, w = 21, h = 13},
        {x = -40.5, y = 2, w = 16, h = 30}, {x = 1, y = 1, w = 7, h = 9}, {x = -3, y = 5, w = 1, h = 12}}) do
      local want, wn = expand(snapshot.floor_pieces({r}, 2))
      for _, max in ipairs({4, 8}) do
        local got, gn = expand(snapshot.floor_pieces({r}, max))
        assert_eq(gn, wn)
        for k in pairs(want) do assert(got[k], "missing " .. k .. " (max " .. max .. ", rect " .. r.w .. "x" .. r.h .. ")") end
      end
    end
  end,
  floor_blocks_cut_the_count = function()
    assert_eq(#snapshot.floor_pieces({{x = 0, y = 0, w = 8, h = 8}}, 8), 1)
    assert_eq(#snapshot.floor_pieces({{x = 0, y = 0, w = 8, h = 8}}, 4), 4)
    assert_eq(#snapshot.floor_pieces({{x = 0, y = 0, w = 8, h = 8}}), 16)        -- default = 2x2, as before
    -- 21 x 13: 2 blocks of 8, then 4x4 / 2x2 / 1x1 in the strips; every tile covered once
    local ps, tiles = snapshot.floor_pieces({{x = 0, y = 0, w = 21, h = 13}}, 8), 0
    local n8 = 0
    for _, p in ipairs(ps) do tiles = tiles + p.size * p.size; if p.size == 8 then n8 = n8 + 1 end end
    assert_eq(tiles, 21 * 13); assert_eq(n8, 2)
    assert(#ps < #snapshot.floor_pieces({{x = 0, y = 0, w = 21, h = 13}}) / 2)
  end,
  split_rects_caps_size_and_keeps_area = function()
    local out = snapshot.split_rects({{x = -5, y = 0, w = 20, h = 3}}, 8)
    assert_eq(area(out), 60)
    for _, r in ipairs(out) do assert(r.w <= 8 and r.h <= 8) end
  end,
  radius_covers_extent = function()
    local m = snapshot.build_model(tiles_rect(0, 0, 40, 10), {}, 0)
    assert_near(m.radius, 20, 1e-9)
  end,

  bounds_extents_and_centroid = function()
    local b = snapshot.bounds({{x = 2, y = 5}, {x = 3, y = 5}, {x = 4, y = 7}})
    assert_eq(b.minx, 2); assert_eq(b.maxx, 4); assert_eq(b.miny, 5); assert_eq(b.maxy, 7)
    assert_eq(b.w, 3); assert_eq(b.h, 3)
    assert_near(b.cx, 3.5, 1e-9); assert_near(b.cy, (5.5 + 5.5 + 7.5) / 3, 1e-9)
    assert_eq(snapshot.bounds({}), nil)
  end,
}
