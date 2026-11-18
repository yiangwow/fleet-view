-- Turns a platform's tiles and entities into a drawable model. build_model/split_rects are pure
-- (no game globals); gather() reads the live platform.
local geom = require("scripts.geom")
local edges = require("scripts.edges")
local snapshot = {}

snapshot.MAX_LIGHTS = 8
snapshot.MAX_GLOWS = 12   -- lit lamps that glow on one ship (draw_light objects, one each)
snapshot.LAMP_COLOUR = {1, 0.9, 0.7}
snapshot.REBUILD_TICKS = 36000

-- Entity types with no usable graphic of their own: one dim, desaturated rect close to the floor colour.
local COLOURED = {
  ["loader"] = {0.40, 0.38, 0.34}, ["loader-1x1"] = {0.40, 0.38, 0.34},
  ["linked-belt"] = {0.40, 0.38, 0.34}, ["gate"] = {0.40, 0.38, 0.34},
}

-- Draw order inside a ship: hub/cargo bay (flat deck-level art) first, then belts/pipes/walls, then the rest.
local PRIO = {
  ["space-platform-hub"] = 0, ["cargo-bay"] = 0,
  ["transport-belt"] = 1, ["underground-belt"] = 1, ["splitter"] = 1, ["pipe"] = 1, ["pipe-to-ground"] = 1,
  ["wall"] = 1,
}
-- Sprite frame 0 of belts faces east; splitter art faces north.
-- pipe-to-ground is NOT turned (0.4.8, portal report Maxorio 2026-11-14: "all pipes to ground use the same graphics just
-- rotated"): each direction has its own picture, drawn as fv-e-<name>-<dir> like any other directional entity.
local ROT_BASE = { ["transport-belt"] = 0.25, ["underground-belt"] = 0.25 }
local ROT_BY_DIR = { ["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true }
-- Curved belts: the default 1-based belt_animation_set index of the curve row by [belt direction][belt_shape].
-- Evidence (2026-11-11): belt_shape probed in game: a belt facing north fed from the west edge reports "left", from the
-- east "right" (same turn rule for the other directions); rows 5..12 of transport-belt.png viewed: "<from>_to_<to>" =
-- enters at the <from> edge, chevrons leave through <to>. left N = west_to_north 7, E = north_to_east 6, S = east_to_south 10,
-- W = south_to_west 11; right N = east_to_north 5, E = south_to_east 9, S = west_to_south 12, W = north_to_west 8.
snapshot.BELT_CURVE = {
  left = { [0] = 7, [4] = 6, [8] = 10, [12] = 11 },
  right = { [0] = 5, [4] = 9, [8] = 12, [12] = 8 },
}
local UG_TYPE = { input = "in", output = "out" }
local LINE = { ["pipe"] = true, ["wall"] = true }   -- straight art is vertical; lie down when the run is horizontal

-- Number keys for coordinate sets (strings like "x,y" cost ~10x more on a big platform: 0.4.2 perf work).
-- Exact for |a|, |b| < 2^20 (platform coordinates are far inside that).
local OFF, SPAN = 2 ^ 20, 2 ^ 22
local function key(a, b) return (a + OFF) * SPAN + (b + OFF) end
local function cell(x, y) return key(math.floor(x * 2 + 0.5), math.floor(y * 2 + 0.5)) end

-- Tile extents without the entity gather: {minx, maxx, miny, maxy (tile coords, inclusive), cx, cy (centroid of the
-- tile centres = model.centre), w, h (tiles)}, or nil for no tiles.
function snapshot.bounds(tiles)
  if #tiles == 0 then return nil end
  local sx, sy = 0, 0
  local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
  for _, t in ipairs(tiles) do
    sx = sx + t.x + 0.5; sy = sy + t.y + 0.5
    if t.x < minx then minx = t.x end
    if t.x > maxx then maxx = t.x end
    if t.y < miny then miny = t.y end
    if t.y > maxy then maxy = t.y end
  end
  return {minx = minx, maxx = maxx, miny = miny, maxy = maxy, cx = sx / #tiles, cy = sy / #tiles,
    w = maxx - minx + 1, h = maxy - miny + 1}
end

-- Cargo bay / hub connection art (docs/bay-connections.md).
-- 1) one piece per boundary TILE of the union of hub and bay tiles, chosen by the mask of its 8 neighbours. Bits from the
-- top-left, clockwise: TL 1, T 2, TR 4, R 8, BR 16, B 32, BL 64, L 128 (y down). `conn` = flat {x, y, mask, ...}, x, y =
-- tile centre minus (cx, cy); interior tiles (mask 255) are left out.
-- 2) one bridge per seam between two touching entities, at the middle of the shared edge: kind 1 horizontal narrow, 2
-- horizontal wide (entities side by side), 3 vertical narrow, 4 vertical wide (stacked), wide = seam of >= BRIDGE_WIDE
-- tiles; kind 5 = crossing, where four different entities meet at one point. `bridges` = flat {x, y, kind, ...}.
local CONN_TYPES = { ["cargo-bay"] = true, ["space-platform-hub"] = true }
snapshot.BRIDGE_WIDE = 4
function snapshot.conn_tiles(entities, cx, cy)
  local owner, ents = {}, {}
  for _, e in ipairs(entities) do
    if CONN_TYPES[e.type] then
      local w, h = math.floor(e.w + 0.5), math.floor(e.h + 0.5)
      local r = {x0 = math.floor(e.x - e.w / 2 + 0.5), y0 = math.floor(e.y - e.h / 2 + 0.5), w = w, h = h}
      ents[#ents + 1] = r
      for ty = r.y0, r.y0 + h - 1 do
        for tx = r.x0, r.x0 + w - 1 do
          local k = key(tx, ty)
          if not owner[k] then owner[k] = #ents end
        end
      end
    end
  end
  -- lattice of corner points whose four surrounding tiles all belong to hub/bays (the footprint shrunk by half a tile:
  -- a lone 4x4 bay gives 3x3 points; seams between touching entities stay occupied).
  local V, vl = {}, {}
  for _, r in ipairs(ents) do
    for vy = r.y0, r.y0 + r.h do
      for vx = r.x0, r.x0 + r.w do
        local k = key(vx, vy)
        if not V[k] and owner[key(vx - 1, vy - 1)] and owner[key(vx, vy - 1)] and owner[key(vx - 1, vy)] and owner[key(vx, vy)] then
          V[k] = true; vl[#vl + 1] = {vx, vy}
        end
      end
    end
  end
  local out, n = {}, 0
  for _, v in ipairs(vl) do
    local x, y = v[1], v[2]
    local m = (V[key(x - 1, y - 1)] and 1 or 0) + (V[key(x, y - 1)] and 2 or 0)
      + (V[key(x + 1, y - 1)] and 4 or 0) + (V[key(x + 1, y)] and 8 or 0)
      + (V[key(x + 1, y + 1)] and 16 or 0) + (V[key(x, y + 1)] and 32 or 0)
      + (V[key(x - 1, y + 1)] and 64 or 0) + (V[key(x - 1, y)] and 128 or 0)
    if m ~= 255 then
      out[n + 1], out[n + 2], out[n + 3] = x - cx, y - cy, m
      n = n + 3
    end
  end
  -- bridges: walk the right and bottom edge of every entity
  local br, bn = {}, 0
  local function emit(x, y, kind)
    br[bn + 1], br[bn + 2], br[bn + 3] = x - cx, y - cy, kind
    bn = bn + 3
  end
  for i, r in ipairs(ents) do
    local seams = {}   -- neighbour index -> {first, last} along the edge
    for ty = r.y0, r.y0 + r.h - 1 do
      local j = owner[key(r.x0 + r.w, ty)]
      if j and j ~= i then
        local s = seams[j]
        if not s then seams[j] = {ty, ty} else s[2] = ty end
      end
    end
    for _, s in pairs(seams) do
      local len = s[2] - s[1] + 1
      emit(r.x0 + r.w, (s[1] + s[2] + 1) / 2, len >= snapshot.BRIDGE_WIDE and 2 or 1)
    end
    seams = {}
    for tx = r.x0, r.x0 + r.w - 1 do
      local j = owner[key(tx, r.y0 + r.h)]
      if j and j ~= i then
        local s = seams[j]
        if not s then seams[j] = {tx, tx} else s[2] = tx end
      end
    end
    for _, s in pairs(seams) do
      local len = s[2] - s[1] + 1
      emit((s[1] + s[2] + 1) / 2, r.y0 + r.h, len >= snapshot.BRIDGE_WIDE and 4 or 3)
    end
    -- crossing: the four tiles around this entity's bottom-right corner belong to four different entities
    local x, y = r.x0 + r.w, r.y0 + r.h
    local a, b, c, d = owner[key(x - 1, y - 1)], owner[key(x, y - 1)], owner[key(x - 1, y)], owner[key(x, y)]
    if a and b and c and d and a ~= b and a ~= c and a ~= d and b ~= c and b ~= d and c ~= d then emit(x, y, 5) end
  end
  return out, br
end

-- tiles: {{x=int,y=int}} (tile top-left coordinates, in list order)
-- entities: {{name,type,x,y,w,h}} (centre position and size, tiles)
-- Everything in the result is relative to model.centre (tile units).
function snapshot.build_model(tiles, entities, tick)
  if #tiles == 0 then return nil end
  local sx, sy = 0, 0
  local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
  local set = {}
  for _, t in ipairs(tiles) do
    sx = sx + t.x + 0.5; sy = sy + t.y + 0.5
    if t.x < minx then minx = t.x end
    if t.x > maxx then maxx = t.x end
    if t.y < miny then miny = t.y end
    if t.y > maxy then maxy = t.y end
    set[key(t.x, t.y)] = true
  end
  local cx, cy = sx / #tiles, sy / #tiles

  local rects = {}
  for _, r in ipairs(geom.merge_tiles(tiles)) do
    rects[#rects + 1] = {x = r.x - cx, y = r.y - cy, w = r.w, h = r.h}
  end

  local lines = {} -- lines[type][cell] = true
  for _, e in ipairs(entities) do
    if LINE[e.type] then
      local l = lines[e.type]
      if not l then l = {}; lines[e.type] = l end
      l[cell(e.x, e.y)] = true
    end
  end
  local crects, ents = {}, {}
  for _, e in ipairs(entities) do
    local col = COLOURED[e.type]
    if col then
      crects[#crects + 1] = {x = e.x - e.w / 2 - cx, y = e.y - e.h / 2 - cy, w = e.w, h = e.h, color = col}
    else
      local rot = 0
      if ROT_BY_DIR[e.type] then
        rot = ((e.dir or 0) / 16 - (ROT_BASE[e.type] or 0)) % 1
      elseif LINE[e.type] then
        local l = lines[e.type]
        local function has(dx, dy) return l[cell(e.x + dx, e.y + dy)] end
        if (has(-1, 0) or has(1, 0)) and not (has(0, -1) or has(0, 1)) then rot = 0.25 end
      end
      -- facing for entities drawn with a per-direction sprite (not the ones turned by `rot`): 4 east, 8 south, 12 west;
      -- nil = north (also in models stored by older builds)
      local dir
      if not (ROT_BY_DIR[e.type] or LINE[e.type]) and (e.dir == 4 or e.dir == 8 or e.dir == 12) then dir = e.dir end
      -- shape art (draw tries these first, rot/dir stay as the fallback): curved belt row, underground in/out, pipe mask
      local row, ug, pmask
      if e.type == "transport-belt" and e.shape and e.shape ~= "straight" then
        local t = snapshot.BELT_CURVE[e.shape]
        row = t and t[e.dir or 0]
      elseif e.type == "underground-belt" and UG_TYPE[e.ug or ""] then
        ug = UG_TYPE[e.ug]
        if e.dir == 4 or e.dir == 8 or e.dir == 12 then dir = e.dir end
      elseif e.type == "pipe" and type(e.pmask) == "number" then
        pmask = e.pmask
      end
      ents[#ents + 1] = {name = e.name, x = e.x - cx, y = e.y - cy, w = e.w, h = e.h, rot = rot, dir = dir, prio = PRIO[e.type] or 2,
        row = row, ug = ug, pmask = pmask, mods = e.mods}
    end
  end
  table.sort(ents, function(a, b)
    if a.prio ~= b.prio then return a.prio < b.prio end
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.name < b.name
  end)

  -- Lights: edge tiles (a neighbour missing), every k-th in list order, at most MAX_LIGHTS.
  local edge = {}
  for _, t in ipairs(tiles) do
    local x, y = t.x, t.y
    if not (set[key(x - 1, y)] and set[key(x + 1, y)] and set[key(x, y - 1)] and set[key(x, y + 1)]) then
      edge[#edge + 1] = t
    end
  end
  local lights = {}
  local step = math.max(1, math.floor(#edge / snapshot.MAX_LIGHTS))
  local i = 1
  while i <= #edge and #lights < snapshot.MAX_LIGHTS do
    lights[#lights + 1] = {x = edge[i].x + 0.5 - cx, y = edge[i].y + 0.5 - cy}
    i = i + step
  end

  -- Glows: lit lamps (rec.lit, rec.color), every k-th in sorted order, at most MAX_GLOWS.
  local lamps = {}
  for _, e in ipairs(entities) do
    if e.lit then lamps[#lamps + 1] = e end
  end
  table.sort(lamps, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.x < b.x end)
  local glows = {}
  local gstep = math.max(1, math.ceil(#lamps / snapshot.MAX_GLOWS))
  for i = 1, #lamps, gstep do
    local l = lamps[i]
    local c = l.color or snapshot.LAMP_COLOUR
    glows[#glows + 1] = {x = l.x - cx, y = l.y - cy, r = c[1] or c.r or 1, g = c[2] or c.g or 1, b = c[3] or c.b or 1}
  end

  local radius = math.max(maxx - minx + 1, maxy - miny + 1) / 2
  local conn, bridges = snapshot.conn_tiles(entities, cx, cy)
  local edge = edges.compute(tiles, function(x, y) return set[key(x, y)] end, cx, cy)
  return {rects = rects, crects = crects, ents = ents, lights = lights, conn = conn, bridges = bridges, edge = edge, glows = glows,
          centre = {x = cx, y = cy}, radius = radius, tick = tick}
end

-- Cut rects into pieces no larger than max tiles per side (so each piece gets its own shade).
function snapshot.split_rects(rects, max)
  local out = {}
  for _, r in ipairs(rects) do
    local y = 0
    while y < r.h do
      local h = math.min(max, r.h - y)
      local x = 0
      while x < r.w do
        local w = math.min(max, r.w - x)
        out[#out + 1] = {x = r.x + x, y = r.y + y, w = w, h = h}
        x = x + w
      end
      y = y + h
    end
  end
  return out
end

-- Floor at true texture scale. Piece = {x, y (top-left, model units), size, v (texture variant 0..15, deterministic)}.
-- The picture is always the platform's 2x2 texture on an even grid from the rect's corner, with 1x1 pieces on odd
-- edges. `max` (2 | 4 | 8, default 2) allows BLOCKS (0.5.0): one piece of size 4 or 8 = one sprite whose layers are the
-- 2x2 pictures that would have been there (fv-t4-<v> / fv-t8-<v>, data.lua; sub-piece variants by
-- geom.floor_sub_variant), so the same floor costs 4x / 16x fewer render objects. v of a block = its top-left 2x2.
-- A rect is filled with the biggest blocks, the strips left over with the next size down.
function snapshot.floor_pieces(rects, max)
  max = max or 2
  local out = {}
  for _, r in ipairs(rects) do
    local bx, by = math.floor(r.x * 2 + 0.5), math.floor(r.y * 2 + 0.5)
    local function add(x, y, size)
      out[#out + 1] = {x = r.x + x, y = r.y + y, size = size, v = ((bx + x) * 7 + (by + y) * 13) % 16}
    end
    local function fill(x0, y0, w, h, n)
      if w <= 0 or h <= 0 then return end
      if n == 1 then
        for y = 0, h - 1 do for x = 0, w - 1 do add(x0 + x, y0 + y, 1) end end
        return
      end
      local wn, hn = w - w % n, h - h % n
      for y = 0, hn - 1, n do for x = 0, wn - 1, n do add(x0 + x, y0 + y, n) end end
      fill(x0 + wn, y0, w - wn, hn, n / 2)   -- strip on the right
      fill(x0, y0 + hn, w, h - hn, n / 2)    -- strip below, full width
    end
    fill(0, 0, r.w, r.h, max)
  end
  return out
end

local SKIP_TYPES = {
  ["character"] = true, ["entity-ghost"] = true, ["tile-ghost"] = true, ["item-request-proxy"] = true,
  ["item-entity"] = true, ["cargo-pod"] = true, ["construction-robot"] = true, ["logistic-robot"] = true,
  ["highlight-box"] = true, ["combat-robot"] = true,
}

local function platform_tiles(surface)
  local names = {}
  for name, proto in pairs(prototypes.tile) do
    if proto.is_foundation then names[#names + 1] = name end
  end
  table.sort(names)
  local tiles = {}
  if #names > 0 then
    for _, t in ipairs(surface.find_tiles_filtered{name = names}) do
      tiles[#tiles + 1] = {x = math.floor(t.position.x), y = math.floor(t.position.y)}
    end
  end
  return tiles
end

-- Tile extents of a live platform (tile scan only, no entities). Runtime only.
function snapshot.gather_bounds(platform)
  local surface = platform.surface
  if not (surface and surface.valid) then return nil end
  return snapshot.bounds(platform_tiles(surface))
end

-- Live read of a LuaSpacePlatform. Runtime only.
function snapshot.gather(platform)
  local surface = platform.surface
  if not (surface and surface.valid) then return nil end
  local tiles = platform_tiles(surface)
  local ents = {}
  for _, e in ipairs(surface.find_entities_filtered{force = platform.force}) do
    if e.valid and not SKIP_TYPES[e.type] and e.name ~= "fv-anchor" then
      local p = e.prototype
      local w, h = p.tile_width or 1, p.tile_height or 1
      if e.direction == defines.direction.east or e.direction == defines.direction.west then w, h = h, w end
      local rec = {name = e.name, type = e.type, x = e.position.x, y = e.position.y, w = w, h = h, dir = e.direction}
      -- shape reads only on the types that need them (one cheap call each)
      local t = e.type
      if t == "transport-belt" then
        rec.shape = e.belt_shape
      elseif t == "underground-belt" then
        rec.ug = e.belt_to_ground_type
      elseif t == "beacon" then
        -- module tier per slot (0 = empty, clamped to 3), for the beacon art with the right modules
        local inv, mods = e.get_module_inventory(), {}
        if inv then
          for i = 1, #inv do
            local st = inv[i]
            mods[i] = st.valid_for_read and math.min(3, st.prototype.tier or 1) or 0
          end
        end
        rec.mods = mods
      elseif t == "lamp" then
        local st = e.status
        if st == defines.entity_status.working or st == defines.entity_status.low_power then
          rec.lit = true
          local c = e.color
          if c then rec.color = {c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1} end
        end
      elseif t == "pipe" then
        local has, ex, ey = {}, e.position.x, e.position.y
        for _, c in ipairs(e.get_fluid_box_pipe_connections(1) or {}) do
          if c.target then
            local dx, dy = c.target_position.x - ex, c.target_position.y - ey
            if math.abs(dy) >= math.abs(dx) then has[dy < 0 and 1 or 4] = true else has[dx > 0 and 2 or 8] = true end
          end
        end
        local m = 0
        for bit in pairs(has) do m = m + bit end   -- bits 1 N, 2 E, 4 S, 8 W (no `|` in Lua 5.2)
        rec.pmask = m
      end
      ents[#ents + 1] = rec
    end
  end
  return snapshot.build_model(tiles, ents, game.tick)
end

return snapshot
