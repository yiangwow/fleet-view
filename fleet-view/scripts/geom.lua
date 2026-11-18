-- Pure geometry helpers for Fleet View. No game globals; deterministic.
local geom = {}

geom.SCALE = 0.16
geom.SHIP_GAP = 4 -- minimum tiles between neighbouring ships
geom.GAP_MIN, geom.GAP_MAX = 3, 12 -- random gap between the deck's bounding box and a ship's box
geom.SCALE_MIN, geom.SCALE_MAX = 0.85, 1.15 -- random per-ship factor on SCALE
geom.TRIES = 24 -- rolls for a spot clear of the other ships before pushing outward

-- Greedy: per row, find horizontal runs; extend a run downward while the next
-- row has an identical run (same x, same width) still unclaimed.
function geom.merge_tiles(tiles)
  local rows, ys = {}, {}
  for _, t in ipairs(tiles) do
    local r = rows[t.y]
    if not r then r = {}; rows[t.y] = r; ys[#ys + 1] = t.y end
    r[t.x] = true
  end
  table.sort(ys)
  -- runs[y] = { {x=,w=,used=} ... } sorted by x
  local runs = {}
  for _, y in ipairs(ys) do
    local xs = {}
    for x in pairs(rows[y]) do xs[#xs + 1] = x end
    table.sort(xs)
    local list = {}
    local i = 1
    while i <= #xs do
      local j = i
      while j < #xs and xs[j + 1] == xs[j] + 1 do j = j + 1 end
      list[#list + 1] = {x = xs[i], w = j - i + 1, used = false}
      i = j + 1
    end
    runs[y] = list
  end
  local out = {}
  for _, y in ipairs(ys) do
    for _, run in ipairs(runs[y]) do
      if not run.used then
        local h = 1
        while true do
          local nxt = runs[y + h]
          local found
          if nxt then
            for _, r2 in ipairs(nxt) do
              if not r2.used and r2.x == run.x and r2.w == run.w then found = r2; break end
            end
          end
          if not found then break end
          found.used = true
          h = h + 1
        end
        out[#out + 1] = {x = run.x, y = y, w = run.w, h = h}
      end
    end
  end
  return out
end

-- Is box {x, y, hw, hh} at least SHIP_GAP tiles from every box in `held` (same shape)?
function geom.clear_of(box, held)
  for _, h in ipairs(held) do
    if math.abs(box.x - h.x) < box.hw + h.hw + geom.SHIP_GAP - 1e-9
      and math.abs(box.y - h.y) < box.hh + h.hh + geom.SHIP_GAP - 1e-9 then return false end
  end
  return true
end

-- Box centre at angle `ang` (radians) from the deck centre, as near as possible while its edge is `gap` tiles
-- outside the deck's bounding box (separated by at least `gap` on the axis that is reached first).
-- deck = {cx, cy, hw, hh} (tile bounding box centre and half extents); hw/hh = the ship's scaled half extents.
local function at_angle(deck, ang, gap, hw, hh)
  local dx, dy = math.cos(ang), math.sin(ang)
  local t = math.huge
  if math.abs(dx) > 1e-9 then t = math.min(t, (deck.hw + hw + gap) / math.abs(dx)) end
  if math.abs(dy) > 1e-9 then t = math.min(t, (deck.hh + hh + gap) / math.abs(dy)) end
  return deck.cx + dx * t, deck.cy + dy * t, dx, dy
end

-- Float smoothness (setting `fleet-view-smoothness`): a parked ship's anchor is teleported once it has drifted
-- this many tiles per axis from where it was last put. smooth = every tick (0.4.7), balanced = 1/32 (1 px at zoom 1,
-- 0.4.8), light = 1/8. Anything else (a view from an older build has none) = balanced.
geom.FLOAT_STEP = {smooth = 0, balanced = 1 / 32, light = 1 / 8}
function geom.float_step(name) return geom.FLOAT_STEP[name] or geom.FLOAT_STEP.balanced end

-- The planet backdrop slides by the FRACTION of the route flown, not by km (filmed 2026-11-16 on a 1000 km test route
-- and on nauvis-vulcanus, departures and arrivals: same edge at the same fraction, within ~5%; portal versuffer, moons
-- Muluna 1000 km / Cerys 800 km). Fleet View's PLANET_KM was filmed on a 15000 km route. km over which the planet
-- leaves/arrives on a route of `length` km: shorter routes scale it down; 15000 km and longer keep `pk` (unchanged).
-- The engine stores entity positions in 1/256 tile (shot mode subpx 2026-11-16: 43.003906 = 43 + 1/256). Two
-- positions on the same grain put an anchor on the same spot.
function geom.same_grain(a, b)
  return math.floor(a.x * 256 + 0.5) == math.floor(b.x * 256 + 0.5) and math.floor(a.y * 256 + 0.5) == math.floor(b.y * 256 + 0.5)
end

geom.PLANET_ROUTE = 15000
function geom.planet_km(pk, length)
  if length and length > 0 and length < geom.PLANET_ROUTE then return pk * length / geom.PLANET_ROUTE end
  return pk
end

-- Walk a ship inward from the bounding-box spot (t0 = distance along the ray from the deck centre) while its box
-- grown by `gap` still overlaps no deck tile; returns the innermost clear distance. Walks IN from the outside and
-- stops at the first blocked position, so a ring's hole is never reached. Coarse steps (up to 8 tiles, never more
-- than half the grown box so a thin arm cannot be stepped over), then 1-tile steps back from the blocked one.
-- blocked(tx1, ty1, tx2, ty2) = does the inclusive tile range hold deck? (the tile at (x, y) covers x..x+1, y..y+1)
local EPS = 1e-9
local function walk_in(deck, dx, dy, t0, hw, hh, gap, blocked)
  local gw, gh = hw + gap, hh + gap
  local function hit(t)
    local x, y = deck.cx + dx * t, deck.cy + dy * t
    return blocked(math.floor(x - gw + EPS), math.floor(y - gh + EPS), math.ceil(x + gw - EPS) - 1, math.ceil(y + gh - EPS) - 1)
  end
  local step = math.max(1, math.min(8, math.floor(math.min(gw, gh))))
  local tc = t0
  while tc > 0 do
    local tn = math.max(0, tc - step)
    if hit(tn) then break end
    tc = tn
  end
  if step > 1 then
    while tc > 0 do
      local tn = math.max(0, tc - 1)
      if hit(tn) then break end
      tc = tn
    end
  end
  return tc
end

-- A random spot for a ship, any side of the deck. rnd() returns a float in [0, 1) (a LuaRandomGenerator in the mod).
-- hw0/hh0 = half extents at the base scale; the ship gets a random scale factor SCALE_MIN..SCALE_MAX.
-- Angle uniform around the deck centre, gap GAP_MIN..GAP_MAX from the deck's bounding box; the ship then walks
-- inward along its ray while its box grown by the gap overlaps no deck tile (`blocked`, see walk_in; nil = stay
-- on the bounding box, so a rectangle gives the same spot either way: the deck sprite hides a ship over deck
-- tiles, a cross or L leaves room in its corners). Up to TRIES rolls of (angle, gap) are made for a spot
-- SHIP_GAP clear of every box in `held`; failing that the last roll is pushed outward along its direction until
-- clear. Returns the box {x, y, hw, hh, k}.
function geom.spot(deck, held, hw0, hh0, rnd, blocked)
  local k = geom.SCALE_MIN + (geom.SCALE_MAX - geom.SCALE_MIN) * rnd()
  local hw, hh = hw0 * k, hh0 * k
  local box, dx, dy
  for _ = 1, geom.TRIES do
    local ang = 2 * math.pi * rnd()
    local gap = geom.GAP_MIN + (geom.GAP_MAX - geom.GAP_MIN) * rnd()
    local x, y
    x, y, dx, dy = at_angle(deck, ang, gap, hw, hh)
    if blocked then
      local t0 = math.sqrt((x - deck.cx) ^ 2 + (y - deck.cy) ^ 2)
      local t = walk_in(deck, dx, dy, t0, hw, hh, gap, blocked)
      if t < t0 then x, y = deck.cx + dx * t, deck.cy + dy * t end
    end
    box = {x = x, y = y, hw = hw, hh = hh, k = k}
    if geom.clear_of(box, held) then return box end
  end
  while not geom.clear_of(box, held) do
    box.x, box.y = box.x + dx * 2, box.y + dy * 2
  end
  return box
end

-- Screen-y offset (tiles) of a travelling ship from its spot at animation frame f (0 = parked .. 1 = gone).
-- Ships fly forward like a platform, up the screen: side -1 = ahead of the spot (leaving), 1 = behind it (arriving).
-- Eased (f^2): a leaving ship speeds up, an arriving one brakes into its spot.
-- Floor pieces are drawn a hair larger than their tile area so neighbours overlap: the renderer rounds each
-- sprite's edges to pixels and a 1 px gap (background shows through) opens at some sub-pixel positions (0.4.8).
geom.FLOOR_OVERLAP = 0.1 -- tiles, total per piece (half on each side)
function geom.floor_scale(size) return 1 + geom.FLOOR_OVERLAP / size end
-- Floor blocks (0.5.0, snapshot.floor_pieces): the texture variant of the 2x2 sub-piece (i, j) (0-based, in 2-tile
-- steps from the block's top-left) of a block whose top-left variant is v. Same rule as a lone piece's variant:
-- v = (7 x + 13 y) mod 16 in tiles, so 2 tiles right = +14, 2 tiles down = +26.
function geom.floor_sub_variant(v, i, j) return (v + 14 * i + 26 * j) % 16 end
geom.FLOOR_BLOCKS = {4, 8}   -- block sizes that have sprites (data.lua)

function geom.travel_dy(f, side, drift) return side * drift * f * f end

-- Camera parallax: the offset (tiles) a view's ships get for a camera at `cam` {x, y} when the deck centre `ref` is the
-- neutral spot: (cam - ref) * f, its length capped at `max` (a camera far away must not fling the ships).
-- Far things follow the camera MORE (a star at infinity stays on screen), so a ship's own share is this / p
-- (p = the ship's parallax factor, bigger = nearer = follows less).
function geom.cam_offset(cam, ref, f, max)
  local dx, dy = (cam.x - ref.x) * f, (cam.y - ref.y) * f
  local l = math.sqrt(dx * dx + dy * dy)
  if l > max and l > 0 then dx, dy = dx * max / l, dy * max / l end
  return dx, dy
end

-- One easing step of `cur` towards `target` (rate 0..1 per tick); lands exactly once within `snap`.
function geom.ease(cur, target, rate, snap)
  local d = target - cur
  if math.abs(d) <= snap then return target end
  return cur + d * rate
end

-- Lambert on a sphere-ish normal; result in [0.35, 1.0].
function geom.shade(light_dir, nx, ny)
  local r2 = nx * nx + ny * ny
  if r2 > 1 then
    local r = math.sqrt(r2)
    nx, ny, r2 = nx / r, ny / r, 1
  end
  local nz = math.sqrt(1 - r2)
  local l = math.sqrt(light_dir.x ^ 2 + light_dir.y ^ 2 + light_dir.z ^ 2)
  if l == 0 then return 1.0 end
  local d = (nx * light_dir.x + ny * light_dir.y + nz * light_dir.z) / l
  if d < 0 then d = 0 elseif d > 1 then d = 1 end
  return 0.35 + 0.65 * d
end

return geom
