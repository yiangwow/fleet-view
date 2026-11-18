local geom = require("scripts.geom")

local function area(rs) local a = 0 for _, r in ipairs(rs) do a = a + r.w * r.h end return a end

local function check_exact(tiles, rs)
  local want = {}
  for _, t in ipairs(tiles) do want[t.x .. "," .. t.y] = true end
  local seen = {}
  for _, r in ipairs(rs) do
    for x = r.x, r.x + r.w - 1 do
      for y = r.y, r.y + r.h - 1 do
        local k = x .. "," .. y
        assert(not seen[k], "overlap at " .. k)
        assert(want[k], "rect covers non-tile " .. k)
        seen[k] = true
      end
    end
  end
  for k in pairs(want) do assert(seen[k], "uncovered " .. k) end
end

-- Fake decks for geom.spot's `blocked` predicate: has(x, y) = is there deck on tile (x, y); the deck's bounding box
-- is given by the extent (x0..x1, y0..y1 inclusive). Returns deck, blocked, has.
local function fake_deck(x0, y0, x1, y1, has)
  local deck = {cx = (x0 + x1 + 1) / 2, cy = (y0 + y1 + 1) / 2, hw = (x1 - x0 + 1) / 2, hh = (y1 - y0 + 1) / 2}
  local function blocked(tx1, ty1, tx2, ty2)
    for x = tx1, tx2 do for y = ty1, ty2 do if has(x, y) then return true end end end
    return false
  end
  return deck, blocked, has
end
local function lcg(seed)
  local s = seed
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end
-- does the box {x, y, hw, hh} grown by g tiles overlap a deck tile?
local function overlaps(has, b, g)
  for x = math.floor(b.x - b.hw - g + 1e-9), math.ceil(b.x + b.hw + g - 1e-9) - 1 do
    for y = math.floor(b.y - b.hh - g + 1e-9), math.ceil(b.y + b.hh + g - 1e-9) - 1 do
      if has(x, y) then return true end
    end
  end
  return false
end

return {
  merge_l_shape = function()
    local tiles = { {x=0,y=0}, {x=0,y=1}, {x=0,y=2}, {x=1,y=2}, {x=2,y=2} }
    local rs = geom.merge_tiles(tiles)
    assert_eq(area(rs), 5)
    check_exact(tiles, rs)
  end,

  merge_empty = function() assert_eq(#geom.merge_tiles({}), 0) end,

  merge_random_walk_1134 = function()
    local s = 12345
    local function rnd(n) s = (s * 1103515245 + 12345) % 2147483648; return s % n end
    local set, tiles = {}, {}
    local x, y = 0, 0
    local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
    while #tiles < 1134 do
      local k = x .. "," .. y
      if not set[k] then set[k] = true; tiles[#tiles + 1] = {x = x, y = y} end
      local d = dirs[rnd(4) + 1]
      x, y = x + d[1], y + d[2]
    end
    local rs = geom.merge_tiles(tiles)
    assert_eq(area(rs), 1134)
    assert(#rs < 300, "rect count " .. #rs)
    check_exact(tiles, rs)
  end,

  spot_scale_in_range_and_deterministic = function()
    local deck = {cx = 0, cy = 0, hw = 12, hh = 8}
    for seed = 1, 200 do
      local function gen()
        local s = seed * 7919
        return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
      end
      local a = geom.spot(deck, {}, 6, 4, gen())
      local b = geom.spot(deck, {}, 6, 4, gen())
      assert_eq(a.x, b.x); assert_eq(a.y, b.y); assert_eq(a.k, b.k)
      assert(a.k >= 0.85 and a.k <= 1.15, "scale " .. a.k)
      assert_near(a.hw, 6 * a.k, 1e-9); assert_near(a.hh, 4 * a.k, 1e-9)
    end
  end,

  spot_outside_deck_with_gap_and_all_sides = function()
    local deck = {cx = 5, cy = -3, hw = 20, hh = 6}
    local sides = {up = 0, down = 0, left = 0, right = 0}
    local s = 99
    local function rnd() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
    for _ = 1, 2000 do
      local b = geom.spot(deck, {}, 5, 3, rnd)
      -- axis separation from the deck's bounding box, in tiles
      local sx = math.abs(b.x - deck.cx) - (deck.hw + b.hw)
      local sy = math.abs(b.y - deck.cy) - (deck.hh + b.hh)
      local gap = math.max(sx, sy)
      assert(gap >= 3 - 1e-6 and gap <= 12 + 1e-6, "gap " .. gap)
      if sy >= sx then sides[b.y < deck.cy and "up" or "down"] = sides[b.y < deck.cy and "up" or "down"] + 1
      else sides[b.x < deck.cx and "left" or "right"] = sides[b.x < deck.cx and "left" or "right"] + 1 end
    end
    for k, n in pairs(sides) do assert(n > 100, "side " .. k .. " only " .. n) end
  end,

  spot_never_overlaps_other_ships = function()
    local deck = {cx = 0, cy = 0, hw = 10, hh = 6}
    for seed = 1, 150 do
      local s = seed * 31337
      local function rnd() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
      local held = {}
      for i = 1, 9 do
        local b = geom.spot(deck, held, 4 + (i * 3) % 7, 3 + (i * 5) % 6, rnd)
        assert(geom.clear_of(b, held), "seed " .. seed .. " ship " .. i .. " too close")
        assert(math.max(math.abs(b.x) - (deck.hw + b.hw), math.abs(b.y) - (deck.hh + b.hh)) >= 3 - 1e-6, "inside deck gap")
        held[#held + 1] = b
      end
    end
  end,

  -- 0.4.9: ships walk in from the bounding box while their box (grown by the gap) touches no deck tile
  -- 0.4.9 float smoothness: setting value -> teleport step; a view from an older build (no value) = balanced
  same_grain_is_the_1_256_tile_grid = function()
    assert(geom.same_grain({x = 43, y = -1.5}, {x = 43.0019, y = -1.5019}))        -- under half a grain: same
    assert(not geom.same_grain({x = 43, y = -1.5}, {x = 43 + 1 / 256, y = -1.5}))  -- one grain in x
    assert(not geom.same_grain({x = 43, y = -1.5}, {x = 43, y = -1.5 - 1 / 256}))  -- one grain in y
  end,
  planet_km_by_route = function()
    assert_eq(geom.planet_km(2280, 15000), 2280)
    assert_eq(geom.planet_km(2280, 30000), 2280)   -- longer routes keep today's pace
    assert_eq(geom.planet_km(2280, nil), 2280)     -- no connection known
    assert_near(geom.planet_km(2280, 1000), 152, 1e-9)
    assert_near(geom.planet_km(2280, 800), 121.6, 1e-9)
  end,
  float_step_mapping = function()
    assert_eq(geom.float_step("smooth"), 0)
    assert_eq(geom.float_step("balanced"), 1 / 32)
    assert_eq(geom.float_step("light"), 1 / 8)
    assert_eq(geom.float_step(nil), 1 / 32)
    assert_eq(geom.float_step("bogus"), 1 / 32)
    -- the on_tick test `abs(d) >= step` moves on every tick for step 0
    assert(0 >= geom.float_step("smooth"))
  end,

  spot_walk_in_rectangle_identical_to_bounding_box = function()
    local deck, blocked = fake_deck(-30, -10, 29, 9, function() return true end)
    for seed = 1, 200 do
      local ra, rb = lcg(seed), lcg(seed)
      local held = {}
      for i = 1, 5 do
        local a = geom.spot(deck, held, 5 + i, 3 + i, ra)
        local b = geom.spot(deck, held, 5 + i, 3 + i, rb, blocked)
        assert_eq(b.x, a.x); assert_eq(b.y, a.y); assert_eq(b.k, a.k)
        held[#held + 1] = a
      end
    end
  end,

  spot_walk_in_cross_lands_in_the_corners = function()
    local deck, blocked, has = fake_deck(-150, -150, 149, 149, function(x, y) return x >= -150 and x < 150 and y >= -150 and y < 150 and (x >= -20 and x < 20 or y >= -20 and y < 20) end)
    local near, total = 0, 0
    for seed = 1, 100 do
      local rnd, held = lcg(seed), {}
      for i = 1, 6 do
        local b = geom.spot(deck, held, 6, 4, rnd, blocked)
        assert(not overlaps(has, b, 0), "ship over deck at " .. b.x .. "," .. b.y)
        held[#held + 1] = b
        total = total + 1
        -- far nearer than the bounding box edge (150): corner ships sit by the arms, ~20 + gap + half size from the centre
        if math.max(math.abs(b.x), math.abs(b.y)) < 100 then near = near + 1 end
      end
    end
    assert(near > total * 0.3, "only " .. near .. " of " .. total .. " ships came in")
    -- the diagonal corner a ship rolled at 45 degrees: close to the arms
    local rnd = function() return 0.125 end -- k mid, angle 45 degrees, gap 7.5
    local b = geom.spot(deck, {}, 6, 4, rnd, blocked)
    assert(b.x > 0 and b.y > 0 and b.x < 60 and b.y < 60, "diagonal ship at " .. b.x .. "," .. b.y)
  end,

  spot_walk_in_ring_never_in_the_hole = function()
    -- a square ring: hole |x|,|y| < 30, ring out to 40
    local function has(x, y) local m = math.max(math.abs(x + 0.5), math.abs(y + 0.5)); return m <= 40 and m > 30 end
    local deck, blocked = fake_deck(-40, -40, 39, 39, has)
    for seed = 1, 100 do
      local rnd, held = lcg(seed), {}
      for i = 1, 5 do
        local b = geom.spot(deck, held, 5, 5, rnd, blocked)
        assert(not overlaps(has, b, 0))
        assert(math.max(math.abs(b.x), math.abs(b.y)) > 40, "ship in the hole or ring at " .. b.x .. "," .. b.y)
        held[#held + 1] = b
      end
    end
  end,

  spot_walk_in_l_shape = function()
    -- L: a vertical arm x 0..19, y 0..99 and a foot x 0..99, y 80..99; the empty corner is x >= 20, y < 80
    local deck, blocked, has = fake_deck(0, 0, 99, 99, function(x, y) return x < 20 and y < 100 and y >= 0 and x >= 0 or y >= 80 and y < 100 and x >= 0 and x < 100 end)
    local inside = 0
    for seed = 1, 100 do
      local rnd, held = lcg(seed), {}
      for i = 1, 4 do
        local b = geom.spot(deck, held, 6, 4, rnd, blocked)
        assert(not overlaps(has, b, 0), "ship over deck")
        assert(geom.clear_of(b, held))
        held[#held + 1] = b
        if b.x > 20 and b.x < 100 and b.y < 80 then inside = inside + 1 end
      end
    end
    assert(inside > 30, "no ships in the L's corner (" .. inside .. ")")
  end,

  spot_crowded_falls_back_to_pushing_outward = function()
    local deck = {cx = 0, cy = 0, hw = 4, hh = 4}
    local held = {}
    local s = 5
    local function rnd() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
    for i = 1, 40 do
      local b = geom.spot(deck, held, 30, 30, rnd)
      assert(geom.clear_of(b, held), "ship " .. i)
      held[#held + 1] = b
    end
  end,

  -- travel_dy(f, side, drift): screen-y offset of a travelling ship from its spot; side -1 ahead (up), 1 behind (down)
  travel_dy_parked_is_zero_on_both_sides = function()
    assert_eq(geom.travel_dy(0, -1, 40), 0)
    assert_eq(geom.travel_dy(0, 1, 40), 0)
  end,

  travel_dy_gone_is_one_drift_ahead_up_the_screen = function()
    assert_eq(geom.travel_dy(1, -1, 40), -40)
  end,

  travel_dy_arriving_start_is_one_drift_behind_down_the_screen = function()
    assert_eq(geom.travel_dy(1, 1, 40), 40)
  end,

  travel_dy_is_a_quarter_of_the_drift_at_half = function()
    assert_near(geom.travel_dy(0.5, -1, 40), -10, 1e-12)
    assert_near(geom.travel_dy(0.5, 1, 40), 10, 1e-12)
    assert_near(geom.travel_dy(0.5, -1, 8), -2, 1e-12) -- scales with the drift it is given
  end,

  travel_dy_strictly_monotonic_in_f = function()
    for _, side in ipairs{-1, 1} do
      local prev = geom.travel_dy(0, side, 40)
      for n = 1, 180 do
        local v = geom.travel_dy(n / 180, side, 40)
        assert(side * (v - prev) > 0, "side " .. side .. " not strictly moving away at n=" .. n)
        prev = v
      end
    end
  end,

  travel_dy_eased_the_speed_grows_with_f = function()
    -- departures speed up, arrivals brake into the spot: the per-tick step is larger the further along (f) it is
    local prev_step = 0
    for n = 1, 180 do
      local step = math.abs(geom.travel_dy(n / 180, -1, 40) - geom.travel_dy((n - 1) / 180, -1, 40))
      assert(step > prev_step, "step did not grow at n=" .. n)
      prev_step = step
    end
    assert(prev_step < 0.5, "fastest step " .. prev_step) -- about 2*40/180 = 0.44 tiles per tick
  end,

  shade_lit_side_brighter_and_bounded = function()
    local light = {x = -0.5, y = -0.5, z = 0.7071}
    assert(geom.shade(light, -1, -1) > geom.shade(light, 1, 1))
    for nx = -1, 1, 0.25 do
      for ny = -1, 1, 0.25 do
        local b = geom.shade(light, nx, ny)
        assert(b >= 0.35 and b <= 1.0, "out of range " .. b)
      end
    end
  end,

  floor_pieces_overlap = function()
    -- neighbouring floor pieces must reach past their shared edge (no gap whatever the pixel rounding)
    local fs2, fs1 = geom.floor_scale(2), geom.floor_scale(1)
    assert(fs2 > 1 and fs1 > fs2)
    assert_near(2 * fs2 - 2, geom.FLOOR_OVERLAP, 1e-9)
    assert_near(1 * fs1 - 1, geom.FLOOR_OVERLAP, 1e-9)
  end,

  cam_offset_is_cam_minus_ref_times_f = function()
    local dx, dy = geom.cam_offset({x = 10, y = -6}, {x = 2, y = 2}, 0.25, 100)
    assert_near(dx, 2, 1e-9); assert_near(dy, -2, 1e-9)
    dx, dy = geom.cam_offset({x = 2, y = 2}, {x = 2, y = 2}, 0.25, 100)
    assert_eq(dx, 0); assert_eq(dy, 0)
  end,

  cam_offset_is_capped_in_length_not_direction = function()
    local dx, dy = geom.cam_offset({x = 300, y = 400}, {x = 0, y = 0}, 0.25, 20)
    assert_near(math.sqrt(dx * dx + dy * dy), 20, 1e-9)
    assert_near(dx / dy, 0.75, 1e-9)
  end,

  ease_converges_and_lands = function()
    local v = 0
    for _ = 1, 200 do v = geom.ease(v, 5, 0.2, 1e-5) end
    assert_eq(v, 5)
    assert_near(geom.ease(0, 10, 0.2, 1e-5), 2, 1e-9)
  end,
}
