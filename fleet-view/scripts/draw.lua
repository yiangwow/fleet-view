-- Draws the other platforms parked at the viewer's space location, per viewer.
-- State lives in storage: models[platform_index], views[player_index], surfaces[player_index],
-- animating[player_index][platform_index] (ships mid arrive/leave), layouts[viewer_platform_index] (where each
-- visible ship sits around that platform's deck, rolled once: shared by every viewer on the platform), bounds[platform_index].
-- Ships are fixed in space: the anchor is placed once at draw time and never follows the viewer.
-- ship = {anchor, base, objects, anim, entry}; base = its spot (the anchor position when parked); entry = the ship's
-- draw-queue entry while it is still filling in.
-- Models (storage.models) are gathered lazily, at most ONE gather per tick, from inside the draw queue.
-- A model is only rebuilt when something on its platform changed (storage.dirty, set by build/mine/die events),
-- at most every REBUILD_TICKS per platform; the redraw is a "swap": a second object set is built on the same
-- anchor (budgeted) and the old set is destroyed in the tick the new one completes, so ships never blink.
-- Queue entry kinds: fill (a new ship), rebuild (gather + spawn swaps), swap.
-- Drawing is staged: storage.draw_queue (ordered array of {pi, idx, items, next, arriving}) is worked off by on_tick,
-- at most FV_DRAW_BUDGET render objects per tick across all viewers. The anchor exists from the start.
-- An arriving ship is created already in its first animation frame (faint, behind its spot, small) and its animation
-- starts once it is complete. anim = {n = 0..ANIM_TICKS, dir = 1 leaving / -1 arriving, side = AHEAD / BEHIND,
-- base = per-object start values}.
-- Travel: the Factorio API only gives a platform's route as a space connection (no 2D heading), so "forward" is the
-- platform's own up = screen up. Travel is relative to the viewer: when ANOTHER platform moves, a leaving ship flies on
-- ahead (up) from its spot and an arriving one comes up from behind (DRIFT tiles below it); when the VIEWER's platform
-- moves, the parked ships fall behind (down) as it leaves and come in from ahead (above) as it arrives, like the
-- planet. storage.where[player] = {platform, loc} (the location last seen) tells which one moved. x never changes.
-- The screen-y offset from the spot is
-- geom.travel_dy(f, side, DRIFT) = side * DRIFT * f^2, f = anim.n / ANIM_TICKS (departures speed up, arrivals brake
-- into the spot); scale is linear in f. No fade on the way (owner: "it shouldnt vanish, it should just fly down"):
-- DRIFT is long enough to leave the screen, and alpha only falls to 0 over the last FADE_TAIL of f (a safety net when
-- zoomed far out).
-- Pace: the planet backdrop moves PLANET_A * km^2 tiles with the distance its platform has flown (measured
-- 2026-10-25 by filming departures at two held speeds: same offset at the same distance). anim.mover = the index of
-- the platform that is moving; each tick anim.n advances by its live speed (km/tick) * ANIM_TICKS / PLANET_KM, the
-- planet's own pace over DRIFT tiles, clamped to MIN_STEP..MAX_STEP (5 to 8 seconds in all). Arrivals ignore the speed
-- and take ARRIVE_STEP (10 s) - except when the VIEWER arrives: then the ships at the destination come in during the
-- approach, like the planet does (no clamp): within PLANET_KM of the destination their anim.n is set every tick from
-- the remaining distance, n = ANIM_TICKS * km / PLANET_KM (so the offset is the planet's PLANET_A * km^2, times
-- parallax), anim.approach = true; once the platform has arrived the last bit finishes at ARRIVE_STEP.
-- storage.transit[player] = true while the viewer's platform is on a space connection (on_tick looks for the approach),
-- storage.approaching[player] = destination name once its ships are wanted.
-- A flip (a leave cancelled into an arrival, or the other way) keeps
-- its side and retraces its path, so the position never jumps.
local geom = require("scripts.geom")
local snapshot = require("scripts.snapshot")
local bays = require("scripts.bays")
local edges = require("scripts.edges")
local sortkey = require("scripts.sortkey")

local draw = {}
-- Only render layers 0-2 sit under the deck (tools/shot-linux.sh deck mode 2026-11-04: layer 3 and up, e.g. "decals"
-- = 10, are drawn over bare deck floor). Layers 0-2 sort sprites by target y, not creation order (docs/layer-order.md).
-- Layer 0 "zero" is NOT used: Visible Planets in Space draws its planet there, and it hides every layer-0 sprite whose
-- target is above the planet's centre (the 0.4.3 bug). Everything on 1 (0.4.10): above any layer-0 planet, and in the
-- same sort as the viewer deck's hanging underside, which the sort-key shifts (scripts/sortkey.lua) put the ship under.
-- The floor sorts under the buildings by its bigger shift (0.4.3 tried all on 1 without shifts: floor cut buildings).
local LAYER_TILE, LAYER_FLAT, LAYER_TOP = "background-transitions", "background-transitions", "background-transitions"
local FALLBACK_LIGHT = {dir = {x = -0.5, y = -0.5, z = 0.7}, color = {1, 1, 1}}
local ANIM_TICKS = 180
local MIN_SCALE = 0.53 -- owner 2026-10-25: shrink a third less than 0.3 ("they get too small")
local DRIFT = 150 -- tiles travelled while leaving or arriving: off screen at normal zoom (about 70-110 tiles tall)
local FADE_TAIL = 0.1 -- alpha goes 1 -> 0 over the last tenth of the trip only
local IDLE_AMP = 0.5 -- tiles each way per axis: a parked ship floats on a slow Lissajous loop around its spot
local IDLE_MIN, IDLE_MAX = 1000, 1600 -- ticks per loop (~17-27 s; owner: 25-40 s felt too slow), its own per ship and axis
-- A floating ship's anchor is moved only once it is this far (tiles, per axis) from where it was last put: 1 px at zoom 1.
-- Moving an anchor costs time for EVERY render object on it, so a teleport per ship per tick was the whole parked cost
-- (0.4.8, portal report Maxorio 2026-11-14: 1.4 ms/tick; stress bench 10 big ships / 107k objects, script ms/tick
-- float on 6.2-7.5 vs off 0.10, without Fleet View 0.09). The float moves at most ~0.004 tiles/tick, so a step comes every
-- ~8+ ticks; the renderer snaps sprites to whole pixels anyway. Camera parallax moves are never held back.
-- Setting `fleet-view-smoothness` picks the step per viewer (view.step, geom.float_step): smooth 0 = every tick
-- (the 0.4.7 cost), balanced 1/32 (this), light 1/8 (0.4.9, portal report Maxorio: "too choppy").
local function float_step_of(player)
  local s = settings.get_player_settings(player)["fleet-view-smoothness"]
  return geom.float_step(s and s.value)
end
local FLOOR_BLOCK = 8 -- biggest floor block (snapshot.floor_pieces max; 2 = lone 2x2 pieces as before 0.5.0)
local PARALLAX = 2 -- travel distance x (1 + PARALLAX * (k - 1)): size 0.85..1.15 -> 0.7..1.3, nearer ships pass faster
local PARALLAX_CAM = 0.125 -- camera parallax "medium" (and views from builds that stored `true`): ships follow (camera - deck centre) * this / their parallax p (far = follows more); 0.25 felt like ships sliding with the camera, owner 2026-11-12: half
-- Setting `fleet-view-parallax` (dropdown, owner 2026-11-12: "so the person can choose"): follow factor per choice; off = nil.
local PARALLAX_OF = { subtle = 0.0625, medium = 0.125, strong = 0.25 }
local function parallax_of(player)
  local s = settings.get_player_settings(player)["fleet-view-parallax"]
  return s and PARALLAX_OF[s.value] or nil
end
local PARALLAX_EASE = 0.3 -- the follow eases towards its target this fraction per tick: no jump on toggle, surface change, drag
local PARALLAX_MAX = 20 -- tiles: the follow offset is capped (a camera far from the deck must not fling the ships)
local PLANET_A = 2.875e-5 -- tiles per km^2 the planet backdrop moves (measured at zoom 0.25: 2.3e-4 px / km^2, 8 px/tile)
local PLANET_KM = math.sqrt(DRIFT / PLANET_A) -- km the planet takes to move DRIFT tiles (~2280)
local MIN_STEP, MAX_STEP = 0.375, 0.6 -- departures, anim.n per tick: slowest 8 s, fastest 5 s (owner: 3-6 s was ~2 s too fast)
local ARRIVE_STEP = 0.3 -- arrivals: always 10 s, not speed-paced (a platform arrives at full speed: 5 s felt too fast)
local AHEAD, BEHIND = -1, 1 -- travel side (screen y): above / below the spot
local FV_DRAW_BUDGET = 150 -- render objects created per tick, all viewers together
-- Sprite updates (scale/offset/colour) per tick for ships under way, all viewers together. Anchors still move every
-- tick; with a big fleet the ships take turns resizing (least recently updated first, at least one per tick).
-- Portal report 2026-10-31 (WhosTigerCub, "laggy near a planet with a ton of big ships"): 10 big ships = 93k sprites
-- rewritten every tick = 35-55 ms/tick plus 1.6 s GC spikes in the stress bench (STRESS=10).
local FV_FRAME_BUDGET = 6000
local LIGHT_TINT = {r = 1, g = 0.72, b = 0.38, a = 1}
local WHITE = {r = 1, g = 1, b = 1, a = 1}
local SHADOW = {r = 1, g = 1, b = 1, a = 0.4}
local GLOW_NAME = "fv-glow"   -- data.lua: soft dot, additive blend_mode (the sprite's alpha is ignored: fade = colour)
local GLOW_GAIN = 0.2   -- additive: strength is the colour, a lamp row stacks up (colour * GLOW_GAIN)

function draw.init()
  storage.models = storage.models or {}
  storage.views = storage.views or {}
  storage.surfaces = storage.surfaces or {}
  storage.layouts = storage.layouts or {}    -- [viewer platform index] = {deck = {x, y}, ships = {[idx] = box}}
  storage.bounds = storage.bounds or {}      -- [platform index] = snapshot.bounds of its tiles
  storage.animating = storage.animating or {}
  storage.where = storage.where or {}          -- [player_index] = {platform = index, loc = name or nil}, last seen
  storage.transit = storage.transit or {}      -- [player_index] = true while the viewer's platform travels
  storage.approaching = storage.approaching or {} -- [player_index] = destination name while its ships come in
  storage.draw_queue = storage.draw_queue or {}
  storage.dirty = storage.dirty or {}          -- [platform_index] = true: changed since its model was built
  storage.rebuild_wait = storage.rebuild_wait or {} -- [platform_index] = queued rebuild entry
  storage.gather_stat = storage.gather_stat or {tick = -1, n = 0, max = 0, total = 0, rebuilds = 0}
end

local function setting(player, name)
  local s = settings.get_player_settings(player)[name]
  return s == nil or s.value
end

local function light_for(location)
  local md = prototypes.mod_data["fv-lights"]
  local l = md and md.data and md.data[location]
  if not l then return FALLBACK_LIGHT end
  return {dir = {x = l.dir[1], y = l.dir[2], z = l.dir[3]}, color = l.color}
end

-- The only place a platform is gathered (the expensive call). Callers keep to one per tick.
local function gather_model(platform)
  local st = storage.gather_stat
  if st.tick ~= game.tick then st.tick = game.tick; st.n = 0 end
  st.n = st.n + 1
  st.total = st.total + 1
  if st.n > st.max then st.max = st.n end
  storage.dirty[platform.index] = nil
  local m = snapshot.gather(platform)
  storage.models[platform.index] = m or nil
  return m
end

function draw.mark_dirty(platform)
  if platform and platform.valid and storage.models[platform.index] then storage.dirty[platform.index] = true end
end

function draw.mark_dirty_surface(surface)
  if surface and surface.valid then draw.mark_dirty(surface.platform) end
end

-- Other platforms of the viewer's force at the same location, sorted by index.
function draw.visible_ships(platform)
  local loc = platform.space_location
  return draw.ships_at(platform, loc and loc.name)
end

-- Other platforms of `platform`'s force parked at location `name`, sorted by index.
function draw.ships_at(platform, name)
  local out = {}
  if not name then return out end
  for _, p in pairs(platform.force.platforms) do
    if p.valid and p.index ~= platform.index and not p.hidden and p.space_location
      and p.space_location.name == name and p.surface and p.surface.valid then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

local DIR_NAME = { [4] = "east", [8] = "south", [12] = "west" }

-- dir: model direction (4/8/12, nil = north). Tries the directional sprite, then the base one, then the icon.
local function sprite_for(name, dir)
  local dn = dir and DIR_NAME[dir]
  if dn then
    local d = "fv-e-" .. name .. "-" .. dn
    if helpers.is_valid_sprite_path(d) then return d, false end
  end
  local own = "fv-e-" .. name
  if helpers.is_valid_sprite_path(own) then return own, false end
  local icon = "entity/" .. name
  if helpers.is_valid_sprite_path(icon) then return icon, true end
  return nil
end

-- Sprite of a model entity: the shape art first (curved belt row, underground in/out, pipe mask; only when the model
-- has the field, so older stored models draw as before), then sprite_for. Third result = true when a shape sprite was used
-- (it is already oriented: no `rot`).
local function sprite_of(e)
  local name = e.name
  local sp
  if e.row then sp = "fv-e-" .. name .. "-r" .. e.row
  elseif e.ug then sp = "fv-e-" .. name .. "-" .. e.ug .. "-" .. (DIR_NAME[e.dir] or "north")
  elseif e.pmask then sp = "fv-e-" .. name .. "-m" .. e.pmask
  elseif e.mods and #e.mods > 0 then sp = "fv-e-" .. name .. "-t" .. table.concat(e.mods) end   -- beacon: module tier per slot
  if sp and helpers.is_valid_sprite_path(sp) then return sp, false, true end
  local a, b = sprite_for(name, e.dir)
  return a, b, false
end

-- Shadow sprite of an entity (data-final-fixes: `fv-e-<name>-sh`, directional variants `-sh-<dir>`), or nil.
-- Prototype data only: cached in a module local, rebuilt after a load.
local EXTRA = {}
local function extra_for(name, dir, suffix)
  local dn = dir and DIR_NAME[dir]
  local key = name .. "|" .. (dn or "") .. "|" .. suffix
  local r = EXTRA[key]
  if r == nil then
    r = false
    if dn then
      local d = "fv-e-" .. name .. "-" .. suffix .. "-" .. dn
      if helpers.is_valid_sprite_path(d) then r = d end
    end
    if not r then
      local own = "fv-e-" .. name .. "-" .. suffix
      if helpers.is_valid_sprite_path(own) then r = own end
    end
    EXTRA[key] = r
  end
  return r or nil
end

local function remove_entry(entry)
  local q = storage.draw_queue
  for i = 1, #q do
    if q[i] == entry then table.remove(q, i); return end
  end
end

local function cancel_swap(ship)
  local sw = ship.swap
  if not sw then return end
  remove_entry(sw)
  for _, o in ipairs(sw.objects) do if o.valid then o.destroy() end end
  ship.swap = nil
end

local function destroy_ship(ship)
  if ship.entry then remove_entry(ship.entry); ship.entry = nil end
  cancel_swap(ship)
  for _, o in ipairs(ship.objects) do if o.valid then o.destroy() end end
  if ship.anchor and ship.anchor.valid then ship.anchor.destroy() end
end

function draw.clear(player_index)
  local view = storage.views[player_index]
  if view then
    for _, ship in pairs(view.ships) do destroy_ship(ship) end
  end
  storage.views[player_index] = nil
  storage.animating[player_index] = nil
end

-- Phase / lid / giga-hatch sprites of a hub or cargo bay (prototypes/connections.lua): {[0..4] = name, lid, gl, gu}, or
-- false when the prototype has none. Prototype data only: cached in a module local, rebuilt after a load.
local PHASED = {}
local function phased(name)
  local r = PHASED[name]
  if r == nil then
    r = {}
    local any = false
    local function try(k, suffix)
      local sp = "fv-e-" .. name .. "-" .. suffix
      if helpers.is_valid_sprite_path(sp) then r[k] = sp; any = true end
    end
    for ph = 0, 4 do try(ph, "p" .. ph) end
    try("lid", "lid"); try("gl", "gl"); try("gu", "gu")
    if not any then r = false end
    PHASED[name] = r
  end
  return r
end

-- mod-data "fv-conn" ({map, tiles}) or false.
local CONN
local function conn_data()
  if CONN == nil then
    local md = prototypes.mod_data["fv-conn"]
    CONN = md and md.data or false
  end
  return CONN
end

-- "fv-arm-<name>" for inserter prototypes (data stage: prototypes/art.lua), false for everything else. Cached per name.
local ARMS = {}
local function arm_sprite(name)
  local r = ARMS[name]
  if r == nil then
    local sp = "fv-arm-" .. name
    r = helpers.is_valid_sprite_path(sp) and sp or false
    ARMS[name] = r
  end
  return r
end

-- Turned copy of a sprite for orientation `o` (data-final-fixes "-fvq<q>"), else the sprite itself. Cached per name.
local TURNED = {}
local function turned_of(sprite, o)
  local t = sortkey.turned(sprite, o)
  if not t then return sprite end
  local r = TURNED[t]
  if r == nil then
    r = helpers.is_valid_sprite_path(t) and t or false
    TURNED[t] = r
  end
  return r or sprite
end

-- The list of things to draw for one ship, in creation order: {sprite, cx, cy (model units), xs, ys, color}.
local function plan_ship(m, light, detail, k)
  local S = geom.SCALE * (k or 1)
  local items = {}
  local R = math.max(m.radius, 1)
  local lc = light.color
  local function tint(x, y, base)
    local k = geom.shade(light.dir, x / R, y / R)
    base = base or {1, 1, 1}
    return {r = base[1] * k * lc[1], g = base[2] * k * lc[2], b = base[3] * k * lc[3], a = 1}
  end
  -- (cx, cy) = where the picture goes. Every fleet-view sprite has a sort-key shift (scripts/sortkey.lua): the target
  -- moves up by it, so the picture lands on (cx, cy) and the sprite sorts far above it. A turned sprite uses its
  -- turned copy (shift pre-turned) when there is one.
  local function add(sprite, cx, cy, xs, ys, color, rot, layer)
    if rot then sprite = turned_of(sprite, rot) end
    local fx, fy = sortkey.fold(sprite, xs, ys, rot)
    items[#items + 1] = {sprite = sprite, ox = cx * S - fx, oy = cy * S - fy, xs = xs, ys = ys, color = color, rot = rot, layer = layer or LAYER_TOP}
  end
  -- edge art first (floor family: sorts at its tile row like the game's own underside, so the floor below a top
  -- edge covers what hangs over it); models stored by older builds have no `edge`
  local ed = m.edge
  if ed then
    for i = 1, #ed, 3 do
      local x, y = ed[i], ed[i + 1]
      add(edges.sprite_name(ed[i + 2]), x, y + edges.HANG, S, S, tint(x, y), nil, LAYER_TILE)
    end
  end
  for _, p in ipairs(snapshot.floor_pieces(m.rects, FLOOR_BLOCK)) do
    local cx, cy = p.x + p.size / 2, p.y + p.size / 2
    -- lone pieces are drawn FLOOR_OVERLAP larger; a block has that in its layers (data.lua) and is drawn at S
    local fs = p.size > 2 and S or S * geom.floor_scale(p.size)   -- prototype scale 0.5 (data.lua)
    add("fv-t" .. p.size .. "-" .. p.v, cx, cy, fs, fs, tint(cx, cy), nil, LAYER_TILE)
  end
  if detail then
    for _, r in ipairs(m.crects) do
      local cx, cy = r.x + r.w / 2, r.y + r.h / 2
      add(sortkey.px_name(r.h), cx, cy, r.w * S * 4, r.h * S * 4, tint(cx, cy, r.color), nil, LAYER_FLAT)
    end
    -- Shadows of every entity (0.4.7), before any building art so they sit under it: white tint, only the fade alpha.
    for _, e in ipairs(m.ents) do
      local sh = extra_for(e.name, e.dir, "sh")
      if sh then add(sh, e.x, e.y, S, S, SHADOW, (e.rot or 0) ~= 0 and e.rot or nil, LAYER_FLAT) end
    end
    -- Hub + cargo bays (prio 0) in the engine's layer order, the connection pieces woven in (docs/bay-connections.md):
    -- art p0, connections 0, p1, conn 1, p2, conn 2, p3, conn 3, p4, then lids and giga hatches.
    local flat, rest = {}, {}
    for _, e in ipairs(m.ents) do
      if (e.prio or 2) == 0 then flat[#flat + 1] = e else rest[#rest + 1] = e end
    end
    local cd = m.conn and #m.conn > 0 and conn_data()
    local pieces = cd and bays.pieces(m.conn, cd.map, cd.tiles) or {}
    if cd and m.bridges and cd.bridges then bays.bridge_pieces(m.bridges, cd.bridges, pieces) end
    local sets = {}
    for i, e in ipairs(flat) do sets[i] = phased(e.name) end
    for ph = 0, 4 do
      for i, e in ipairs(flat) do
        local r = sets[i]
        if r then
          if r[ph] then add(r[ph], e.x, e.y, S, S, tint(e.x, e.y), nil, LAYER_FLAT) end
        elseif ph == 0 then
          local sprite = sprite_for(e.name, e.dir)
          if sprite then add(sprite, e.x, e.y, S, S, tint(e.x, e.y), nil, LAYER_FLAT) end
        end
      end
      if ph < 4 then
        for i = 1, #pieces, 3 do
          local x, y = pieces[i], pieces[i + 1]
          add("fv-c-" .. pieces[i + 2] .. "-" .. ph, x, y, S, S, tint(x, y), nil, LAYER_FLAT)
        end
      end
    end
    for _, key in ipairs({ "lid", "gl", "gu" }) do
      for i, e in ipairs(flat) do
        local r = sets[i]
        if r and r[key] then add(r[key], e.x, e.y, S, S, tint(e.x, e.y), nil, LAYER_FLAT) end
      end
    end
    for _, e in ipairs(rest) do
      local sprite, icon, shaped = sprite_of(e)
      if sprite then
        local sc = icon and (math.max(e.w, e.h) * S / 2) or S
        add(sprite, e.x, e.y, sc, sc, tint(e.x, e.y), (not shaped and (e.rot or 0) ~= 0) and e.rot or nil, LAYER_TOP)
        -- inserter: one more object, the arm at rest over the pickup side (the art is north-facing, e.dir 4/8/12 = turn)
        if not icon then
          local arm = arm_sprite(e.name)
          if arm then add(arm, e.x, e.y, S, S, tint(e.x, e.y), e.dir and e.dir / 16 or nil, LAYER_TOP) end
        end
      end
    end
  end
  for _, l in ipairs(m.lights) do
    add("fv-dot", l.x, l.y, S, S, LIGHT_TINT)   -- LIGHT_SIZE is the prototype scale (data.lua)
  end
  -- lamp glows: one additive sprite each (draw_light shows nothing on a platform surface: no darkness), the lamp's colour;
  -- last in the list; old models have none. Fades / scales with the ship like every other object.
  if detail and m.glows then
    local sc = S   -- GLOW_TILES is the prototype scale (data.lua)
    for _, g in ipairs(m.glows) do
      add(GLOW_NAME, g.x, g.y, sc, sc, {r = g.r * GLOW_GAIN, g = g.g * GLOW_GAIN, b = g.b * GLOW_GAIN, a = 1}, nil, LAYER_TOP)
      items[#items].add = true
    end
  end
  return items
end

-- Creates item `it` for `ship`. Arriving ships get the first animation frame (f = 1) so they start faint.
local function create_item(player, ship, it, arriving)
  local k, a = 1, it.color.a
  if arriving then k, a = MIN_SCALE, 0 end
  local c = it.color
  local g = (it.add and arriving) and 0 or 1   -- additive glows fade by colour, not alpha
  return rendering.draw_sprite{
    sprite = it.sprite, surface = ship.anchor.surface, target = {entity = ship.anchor, offset = {it.ox * k, it.oy * k}},
    x_scale = it.xs * k, y_scale = it.ys * k, tint = {r = c.r * g, g = c.g * g, b = c.b * g, a = a},
    render_layer = it.layer, players = {player}, orientation = it.rot,
  }
end

local function current_pos(ship)
  local anim = ship.anim
  -- parallax: a bigger (nearer) ship covers more ground in the same time, so ships side by side drift apart
  local p = 1 + PARALLAX * ((ship.k or 1) - 1)
  local dy = anim and geom.travel_dy(anim.n / ANIM_TICKS, anim.side or AHEAD, DRIFT * p) or 0
  -- idle float, also under way so nothing jumps when a ship starts or stops travelling
  local ix, iy = 0, 0
  local w = ship.idle
  if w and not storage.no_idle then
    local t = game.tick
    ix = IDLE_AMP * p * math.sin(2 * math.pi * t / w.px + w.fx)
    iy = IDLE_AMP * p * math.sin(2 * math.pi * t / w.py + w.fy)
  end
  local po = ship.po -- camera parallax of its view (shared table, eased in draw.on_tick), nearer ships follow less
  if po then ix, iy = ix + po.x / p, iy + po.y / p end
  return {x = ship.base.x + ix, y = ship.base.y + dy + iy}
end

-- Everything needed to draw for a viewer on `platform`, or nil.
local function context(player, platform, loc)
  loc = loc or (platform and platform.valid and platform.space_location and platform.space_location.name)
  if not (player.valid and platform and platform.valid and loc) then return nil end
  return {
    surface = player.surface,
    detail = setting(player, "fleet-view-detail"),
    light = light_for(loc),
  }
end

-- Tile extents of a platform (tile scan only, cached until its tiles change).
local function bounds_of(platform)
  local b = storage.bounds[platform.index]
  if not b then
    b = snapshot.gather_bounds(platform)
    storage.bounds[platform.index] = b or nil
  end
  return b
end

function draw.tiles_changed(platform)
  if platform and platform.valid then storage.bounds[platform.index] = nil end
end

-- Drop layout entries of ships that are neither visible from `platform` nor held by any view on it.
local function prune_layout(platform, others)
  local L = storage.layouts[platform.index]
  if not L then return end
  local keep = {}
  for _, o in ipairs(others) do keep[o.index] = true end
  for _, view in pairs(storage.views) do
    if view.platform_index == platform.index then
      for idx in pairs(view.ships) do keep[idx] = true end
    end
  end
  for idx in pairs(L.ships) do if not keep[idx] then L.ships[idx] = nil end end
  if next(L.ships) == nil then storage.layouts[platform.index] = nil end
end

-- The mod's random generator (LuaRandomGenerator, kept in storage: it saves and loads with its state, so every
-- machine in a multiplayer game draws the same numbers). Created lazily from the map seed mixed with the tick,
-- never in on_load. Float in [0, 1).
local function random()
  if not storage.rng then
    local nauvis = game.surfaces["nauvis"]
    local base = nauvis and nauvis.map_gen_settings.seed or 20261023
    storage.rng = game.create_random_generator((base + (game.tick % 1048576) * 2654435) % 4294967296)
  end
  return storage.rng()
end

-- Test/screenshot hook: restart the generator from a fixed seed.
function draw.set_seed(seed) storage.rng = game.create_random_generator(seed) end

-- geom.spot's `blocked(tx1, ty1, tx2, ty2)`: does the inclusive tile range hold any deck (a foundation tile, the same
-- set the model and bounds are built from)? The tile at (x, y) covers x..x+1, y..y+1, so the area is {tx1, ty1} ..
-- {tx2 + 1, ty2 + 1}. One call, stops at the first hit. NOT "any tile but empty-space": the corners of a big platform are
-- ungenerated chunks whose tiles read as out-of-map, which that test would count as deck.
local foundation_names
local function deck_blocked(surface)
  if not foundation_names then
    foundation_names = {}
    for name, proto in pairs(prototypes.tile) do
      if proto.is_foundation then foundation_names[#foundation_names + 1] = name end
    end
    table.sort(foundation_names)
  end
  local names = foundation_names
  return function(tx1, ty1, tx2, ty2)
    return surface.count_tiles_filtered{area = {{tx1, ty1}, {tx2 + 1, ty2 + 1}}, name = names, limit = 1} > 0
  end
end

-- Where `other` sits around the deck of `platform`: a box {x, y (bounding-box centre), hw, hh, k (scale factor),
-- ax, ay (anchor)}, rolled ONCE when the ship becomes visible there and stored in storage.layouts[platform.index],
-- shared by every viewer on that platform, until the ship leaves (prune_layout) - a new arrival re-rolls.
local function place(platform, other)
  local L = storage.layouts[platform.index]
  if not L then L = {ships = {}}; storage.layouts[platform.index] = L end
  local box = L.ships[other.index]
  if box then return box end
  local db = bounds_of(platform)
  local ob = bounds_of(other)
  if not (db and ob) then return nil end
  local S = geom.SCALE
  local deck = {cx = (db.minx + db.maxx + 1) / 2, cy = (db.miny + db.maxy + 1) / 2, hw = db.w / 2, hh = db.h / 2}
  L.deck = {x = deck.cx, y = deck.cy}
  local held = {}
  for _, h in pairs(L.ships) do held[#held + 1] = h end
  box = geom.spot(deck, held, ob.w * S / 2, ob.h * S / 2, random, deck_blocked(platform.surface))
  -- the anchor is the model centre (tile centroid); the bounding box centre sits (bbox - centroid) * scale from it
  box.ax = box.x - ((ob.minx + ob.maxx + 1) / 2 - ob.cx) * S * box.k
  box.ay = box.y - ((ob.miny + ob.maxy + 1) / 2 - ob.cy) * S * box.k
  L.ships[other.index] = box
  return box
end

-- A ship's float (loop periods and phases per axis), rolled with the spot; boxes from older builds get one on use.
local function idle_of(box)
  if not box.idle then
    box.idle = {px = IDLE_MIN + (IDLE_MAX - IDLE_MIN) * random(), py = IDLE_MIN + (IDLE_MAX - IDLE_MIN) * random(),
      fx = 2 * math.pi * random(), fy = 2 * math.pi * random()}
  end
  return box.idle
end

-- Remaining km of `platform` to location `dest` along its current space connection, or nil (not travelling, or the
-- connection does not end there). platform.distance runs 0..1 from the connection's `from` end, in both directions
-- (probed 2026-10-25: flying to `from` it falls 1 -> 0).
local function km_to(platform, dest)
  local c = platform.space_connection
  if not (c and dest) then return nil end
  local d = platform.distance or 0
  if c.to.name == dest then return (1 - d) * c.length end
  if c.from.name == dest then return d * c.length end
  return nil
end

-- km over which the planet leaves/arrives on `platform`'s current route (geom.planet_km: shorter routes = moons scale
-- PLANET_KM down by route length; 15000 km and longer, or no connection, = PLANET_KM).
local function planet_km_on(platform)
  local c = platform and platform.valid and platform.space_connection
  return geom.planet_km(PLANET_KM, c and c.length)
end

-- Where `platform` is flying: its schedule's current station, when that is an end of its current connection.
local function destination(platform)
  local s = platform.schedule
  local rec = s and s.records and s.records[s.current]
  local st = rec and rec.station
  if type(st) ~= "string" then return nil end
  return km_to(platform, st) and st or nil
end

-- A ship's fixed place: the anchor is created once, here, and never teleported for viewer movement.
local function add_ship(player, platform, view, ctx, others, i, arriving, side, mover)
  local other = others[i]
  local box = place(platform, other)
  if not box then return nil end
  local ship = {k = box.k, base = {x = box.ax, y = box.ay}, po = view.po, idle = view.float ~= false and idle_of(box) or nil}
  if arriving then ship.anim = {n = ANIM_TICKS, dir = -1, side = side or BEHIND, mover = mover, base = {}} end
  ship.anchor = ctx.surface.create_entity{name = "fv-anchor", position = current_pos(ship), force = player.force}
  if not ship.anchor then return nil end
  ship.anchor.destructible = false -- a dead anchor takes its pictures with it; nothing may kill it by accident
  ship.objects = {}
  ship.entry = {kind = "fill", pi = player.index, idx = other.index, light = ctx.light, detail = ctx.detail, k = ship.k, next = 1, arriving = arriving or nil}
  local q = storage.draw_queue
  q[#q + 1] = ship.entry
  view.ships[other.index] = ship
  return ship
end

local function new_view(player, platform)
  return {surface_index = player.surface.index, platform_index = platform.index,
    float = setting(player, "fleet-view-float"), par = parallax_of(player), step = float_step_of(player),
    po = {x = 0, y = 0}, ships = {}}
end

function draw.show(player, platform)
  draw.clear(player.index)
  if not (player.valid and platform and platform.valid) then return end
  storage.where[player.index] = {platform = platform.index, loc = platform.space_location and platform.space_location.name}
  storage.transit[player.index] = (not platform.space_location and platform.space_connection) and true or nil
  storage.approaching[player.index] = nil -- on_tick finds the approach again and reconciles
  local others = draw.visible_ships(platform)
  if #others == 0 then return end
  local ctx = context(player, platform)
  if not ctx then return end
  prune_layout(platform, others)
  local view = new_view(player, platform)
  for i in ipairs(others) do add_ship(player, platform, view, ctx, others, i) end
  if next(view.ships) then storage.views[player.index] = view end
end

-- Writes the animation frame (f = 0 full .. 1 gone) onto a ship's objects and anchor.
-- Reused for every sprite write (the API copies them): no garbage per sprite per tick.
local SCRATCH_TARGET = {entity = nil, offset = {0, 0}}
local SCRATCH_COLOR = {r = 1, g = 1, b = 1, a = 1}

-- The anchor follows the travel curve (and the idle float) every tick: cheap, one entity per ship.
local function move_anchor(ship)
  if ship.anchor.valid then ship.anchor.teleport(current_pos(ship)) end
end

-- Brings the ship's sprites to the current frame (scale, offset, alpha). Writes only what changed since the last
-- update (ship.drawn_k / ship.drawn_fade; nil = unknown, write it). Returns the number of sprites touched.
local function apply_frame(ship)
  local anim = ship.anim
  local f = anim.n / ANIM_TICKS
  local k = 1 - (1 - MIN_SCALE) * f
  local fade = math.min(1, (1 - f) / FADE_TAIL)
  local dk, df = k ~= ship.drawn_k, fade ~= ship.drawn_fade
  if not (dk or df) then return 0 end
  local T, C = SCRATCH_TARGET, SCRATCH_COLOR
  local off = T.offset
  T.entity = ship.anchor
  for i, o in ipairs(ship.objects) do
    local b = anim.base[i]
    if b and o.valid then
      if dk then
        o.x_scale = b.xs * k
        o.y_scale = b.ys * k
        off[1], off[2] = b.ox * k, b.oy * k
        o.target = T
      end
      if df then
        if b.add then C.r, C.g, C.b, C.a = b.r * fade, b.g * fade, b.b * fade, b.a   -- additive: alpha does nothing
        else C.r, C.g, C.b, C.a = b.r, b.g, b.b, b.a * fade end
        o.color = C
      end
    end
  end
  T.entity = nil
  ship.drawn_k, ship.drawn_fade, ship.drawn_tick = k, fade, game.tick
  return #ship.objects
end

local function end_anim(pi, idx)
  local set = storage.animating[pi]
  if set then
    set[idx] = nil
    if next(set) == nil then storage.animating[pi] = nil end
  end
end

-- A ship whose anchor is gone (destroyed by something else) cannot be animated or kept: drop it cleanly.
local function drop_ship(pi, view, idx, ship)
  destroy_ship(ship)
  view.ships[idx] = nil
  end_anim(pi, idx)
end

-- Start (or reverse) an animation: dir 1 = leaving, -1 = arriving; `mover` = index of the platform that moves (sets
-- the pace). A fresh one takes `side`; a reversal changes dir and mover and keeps the side, so the ship retraces its path.
local function begin_anim(pi, view, idx, ship, dir, side, mover)
  if not ship.anchor.valid then drop_ship(pi, view, idx, ship); return end
  cancel_swap(ship)
  if ship.anim then ship.anim.dir = dir; ship.anim.mover = mover
  else
    local base = {}
    local objs = ship.objects
    local ng = 0   -- glows (additive sprites) are the last objects of a ship
    while ng < #objs and objs[#objs - ng].valid and objs[#objs - ng].sprite == GLOW_NAME do ng = ng + 1 end
    for i, o in ipairs(objs) do
      if o.valid then
        local c, off = o.color, o.target.offset
        base[i] = {xs = o.x_scale, ys = o.y_scale, r = c.r, g = c.g, b = c.b, a = c.a,
          ox = off.x or off[1], oy = off.y or off[2], add = i > #objs - ng or nil}
      end
    end
    ship.anim = {n = dir == 1 and 0 or ANIM_TICKS, dir = dir, side = side, mover = mover, base = base}
    ship.drawn_k, ship.drawn_fade = 1, 1 -- what a parked ship shows
  end
  local set = storage.animating[pi]
  if not set then set = {}; storage.animating[pi] = set end
  set[idx] = true
end

-- Model for platform `idx` (force `force_name`): the cached one, or gathered now if this tick has not
-- gathered yet (st.gathered). Returns model, ready; ready=false means "try again next tick".
local function ensure_model(force_name, idx, st)
  local m = storage.models[idx]
  if m then return m, true end
  if st.gathered then return nil, false end
  st.gathered = true
  local f = game.forces[force_name]
  local p = f and f.platforms[idx]
  if p and p.valid then m = gather_model(p) end
  return m, true
end

-- A rebuilt model: every idle view of that ship gets a swap entry (second object set, then old set destroyed).
local function spawn_swaps(idx)
  local pis = {}
  for pi, view in pairs(storage.views) do
    if view.ships[idx] then pis[#pis + 1] = pi end
  end
  table.sort(pis)
  for _, pi in ipairs(pis) do
    local ship = storage.views[pi].ships[idx]
    local player = game.get_player(pi)
    local platform = player and player.valid and player.surface.platform
    if platform and platform.valid and platform.space_location
      and not (ship.entry or ship.anim or ship.swap) and ship.anchor.valid then
      ship.swap = {kind = "swap", pi = pi, idx = idx, light = light_for(platform.space_location.name),
        detail = setting(player, "fleet-view-detail"), k = ship.k, next = 1, objects = {}}
      local q = storage.draw_queue
      q[#q + 1] = ship.swap
    end
  end
end

-- Creates `n` more items of entry `e` (items planned from the cached model on first use). `target` is the list
-- the objects go to. Returns true when all items exist.
local function create_items(player, ship, e, target, budget)
  local n = math.min(budget, #e.items - e.next + 1)
  for i = e.next, e.next + n - 1 do
    target[#target + 1] = create_item(player, ship, e.items[i], e.arriving)
  end
  e.next = e.next + n
  return n, e.next > #e.items
end

-- Works off the queue: at most `budget` render objects created in total and one model gather. Entries that no
-- longer match their owner (ship.entry / ship.swap / storage.rebuild_wait) are dropped.
-- Entries added while processing  go to storage.draw_queue and are appended after `keep`.
local function process_queue(budget)
  local st = {gathered = false}
  local q = storage.draw_queue
  local fresh = {}
  storage.draw_queue = fresh
  local keep = {}
  for _, e in ipairs(q) do
    local k = e.kind
    if k == "rebuild" then
      if storage.rebuild_wait[e.idx] == e then
        if st.gathered then keep[#keep + 1] = e
        else
          st.gathered = true
          storage.rebuild_wait[e.idx] = nil
          local f = game.forces[e.force]
          local p = f and f.platforms[e.idx]
          if p and p.valid then
            storage.gather_stat.rebuilds = storage.gather_stat.rebuilds + 1
            if gather_model(p) then spawn_swaps(e.idx) end
          end
        end
      end
    elseif k == "swap" then
      local view = storage.views[e.pi]
      local ship = view and view.ships[e.idx]
      if ship and ship.swap == e then
        local player = game.get_player(e.pi)
        if not (player and player.valid and ship.anchor.valid and storage.models[e.idx]) then
          cancel_swap(ship)
        else
          if not e.items then e.items = plan_ship(storage.models[e.idx], e.light, e.detail, e.k) end
          local n, done = create_items(player, ship, e, e.objects, budget)
          budget = budget - n
          if done then
            for _, o in ipairs(ship.objects) do if o.valid then o.destroy() end end
            ship.objects = e.objects
            ship.swap = nil
          else
            keep[#keep + 1] = e
          end
        end
      end
    else -- fill
      local view = storage.views[e.pi]
      local ship = view and view.ships[e.idx]
      local player = game.get_player(e.pi)
      if ship and ship.entry == e then
        if not (player and player.valid and ship.anchor.valid) then
          destroy_ship(ship); view.ships[e.idx] = nil
          if next(view.ships) == nil then draw.clear(e.pi) end
        else
          if not e.items then
            local m, ready = ensure_model(player.force.name, e.idx, st)
            if m then
              e.items = plan_ship(m, e.light, e.detail, e.k); e.light = nil
            elseif ready then
              destroy_ship(ship); view.ships[e.idx] = nil
              if next(view.ships) == nil then draw.clear(e.pi) end
            end
          end
          if not ship.entry then
            -- dropped above
          elseif not e.items then
            keep[#keep + 1] = e
          else
            local n, done = create_items(player, ship, e, ship.objects, budget)
            budget = budget - n
            if done then
              ship.entry = nil
              if e.arriving then
                local base = ship.anim.base
                for i, it in ipairs(e.items) do
                  local c = it.color
                  base[i] = {xs = it.xs, ys = it.ys, r = c.r, g = c.g, b = c.b, a = c.a, ox = it.ox, oy = it.oy, add = it.add}
                end
                ship.drawn_k, ship.drawn_fade = MIN_SCALE, 0 -- create_item drew the arriving frame (f = 1)
                local set = storage.animating[e.pi]
                if not set then set = {}; storage.animating[e.pi] = set end
                set[e.idx] = true
              end
            else
              keep[#keep + 1] = e
            end
          end
        end
      end
    end
  end
  for _, e in ipairs(fresh) do keep[#keep + 1] = e end
  storage.draw_queue = keep
end

-- Test hook: finish all queued drawing at once.
function draw.flush()
  local guard = 0
  while storage.draw_queue[1] and guard < 1000 do process_queue(math.huge); guard = guard + 1 end
end

-- Once a minute: platforms whose model is dirty and older than the throttle are rebuilt if someone sees them
-- (queued gather + swap), otherwise their model is just dropped (the next show gathers it fresh).
function draw.service_dirty(tick)
  if next(storage.dirty) == nil then return end
  local idxs = {}
  for idx in pairs(storage.dirty) do idxs[#idxs + 1] = idx end
  table.sort(idxs)
  local limit = storage.rebuild_ticks or snapshot.REBUILD_TICKS
  for _, idx in ipairs(idxs) do
    local m = storage.models[idx]
    if not m then storage.dirty[idx] = nil
    elseif tick - m.tick >= limit and not storage.rebuild_wait[idx] then
      local force
      local pis = {}
      for pi, view in pairs(storage.views) do if view.ships[idx] then pis[#pis + 1] = pi end end
      table.sort(pis)
      for _, pi in ipairs(pis) do
        local pl = game.get_player(pi)
        if pl and pl.valid then force = pl.force.name; break end
      end
      if force then
        local e = {kind = "rebuild", idx = idx, force = force}
        storage.rebuild_wait[idx] = e
        local q = storage.draw_queue
        q[#q + 1] = e
      else
        storage.models[idx] = nil; storage.dirty[idx] = nil
      end
    end
  end
end

-- Reconcile every player the mod knows (connected ones and those with a recorded surface).
function draw.reconcile_all()
  for pi in pairs(storage.surfaces) do draw.reconcile(pi) end
  for _, p in pairs(game.connected_players) do
    if not storage.surfaces[p.index] then draw.reconcile(p.index) end
  end
end

-- A platform state event may arrive before space_location has changed: reconcile now, and once more
-- DEFER_TICKS later. storage.reconcile_at is nil whenever nothing is pending.
local DEFER_TICKS = 5
function draw.on_platform_state(tick)
  draw.reconcile_all()
  if not storage.reconcile_at then storage.reconcile_at = tick + DEFER_TICKS end
end

-- Event-driven (platform state changed): ships that left animate out, new ones animate in.
function draw.reconcile(player_index)
  local player = game.get_player(player_index)
  if not (player and player.valid) then draw.clear(player_index); return end
  storage.surfaces[player_index] = player.surface.index
  local platform = player.surface.platform
  if not (platform and platform.valid) then draw.clear(player_index); return end
  -- did the viewer's own platform change location since the last look? Then it is the one travelling.
  local here = platform.space_location and platform.space_location.name
  local was = storage.where[player_index]
  local moved = was ~= nil and was.platform == platform.index and was.loc ~= here
  storage.where[player_index] = {platform = platform.index, loc = here}
  -- travelling: the ships at the destination are wanted once on_tick has found the approach (storage.approaching)
  local appr
  if here or not platform.space_connection then
    storage.transit[player_index] = nil; storage.approaching[player_index] = nil
  else
    storage.transit[player_index] = true
    appr = storage.approaching[player_index]
  end
  local leave_side, arrive_side = AHEAD, BEHIND
  if moved then leave_side, arrive_side = BEHIND, AHEAD end
  local view = storage.views[player_index]
  if view and (view.surface_index ~= player.surface.index or view.platform_index ~= platform.index) then
    draw.show(player, platform); return
  end
  local others = here and draw.visible_ships(platform) or draw.ships_at(platform, appr)
  local want = {}
  for _, o in ipairs(others) do want[o.index] = true end
  if view then
    for idx, ship in pairs(view.ships) do
      if not ship.anchor.valid then
        drop_ship(player_index, view, idx, ship)
      elseif want[idx] then
        if ship.anim and ship.anim.dir == 1 then
          begin_anim(player_index, view, idx, ship, -1, arrive_side, moved and platform.index or idx)
        end
      elseif ship.entry then
        -- still filling in: nothing worth animating, drop it and its queue entry now
        destroy_ship(ship); view.ships[idx] = nil
      elseif not (ship.anim and ship.anim.dir == 1) then
        begin_anim(player_index, view, idx, ship, 1, leave_side, moved and platform.index or idx)
      end
    end
  end
  local ctx
  prune_layout(platform, others)
  for i, o in ipairs(others) do
    if not (view and view.ships[o.index]) then
      ctx = ctx or context(player, platform, here or appr)
      if not ctx then break end
      if not view then view = new_view(player, platform) end
      if appr then
        -- coming in during the viewer's approach: placed by the remaining distance, from ahead, like the planet
        local ship = add_ship(player, platform, view, ctx, others, i, true, AHEAD, platform.index)
        local km = ship and km_to(platform, appr)
        if km then
          ship.anim.approach = true
          ship.anim.n = math.min(ANIM_TICKS, ANIM_TICKS * km / planet_km_on(platform))
          ship.anchor.teleport(current_pos(ship))
        end
      else
        add_ship(player, platform, view, ctx, others, i, true, arrive_side, moved and platform.index or o.index)
      end
    end
  end
  if view and next(view.ships) then
    if not storage.views[player_index] then storage.views[player_index] = view end
  elseif view then
    draw.clear(player_index)
  end
end

function draw.refresh(player_index)
  local player = game.get_player(player_index)
  if not (player and player.valid) then draw.clear(player_index); return end
  storage.surfaces[player_index] = player.surface.index
  local platform = player.surface.platform
  if platform and platform.valid then draw.show(player, platform) else draw.clear(player_index) end
end

-- anim.n per tick for a ship whose travel is driven by platform `mover` (force `force`): the planet's pace at the
-- mover's live speed, clamped to MIN_STEP..MAX_STEP. storage.min_step overrides MIN_STEP (test hook; raises the top too).
-- `own` = the mover is the viewer's own platform: its planet is on screen, and on a short route (a moon) it leaves
-- faster than the clamp allows; the ships (nearer than the planet) are then never slower than it (owner 2026-11-16:
-- the clamp is there because ships are closer than the planet; slower than it breaks that). Routes >= 15000 km: as before.
local function step_of(force, mover, dir, own)
  if dir == -1 then return storage.min_step or ARRIVE_STEP end
  local p = mover and force.platforms[mover]
  local v = (p and p.valid and p.speed) or 0
  local lo = storage.min_step or MIN_STEP
  local step = math.max(lo, math.min(math.max(lo, MAX_STEP), math.abs(v) * ANIM_TICKS / PLANET_KM))
  if own then
    local pk = planet_km_on(p)
    if pk < PLANET_KM then step = math.max(step, math.abs(v) * ANIM_TICKS / pk) end
  end
  return step
end

-- The setting changed: ships ease to/from the camera follow (no redraw).
function draw.set_parallax(player_index)
  local view = storage.views[player_index]
  local player = game.get_player(player_index)
  if view and player and player.valid then view.par = parallax_of(player) end
end

-- The float smoothness setting changed: the next float step uses it (no redraw).
function draw.set_float_smoothness(player_index)
  local view = storage.views[player_index]
  local player = game.get_player(player_index)
  if view and player and player.valid then view.step = float_step_of(player) end
end

-- Test hook: camera parallax off (true) / on (nil).
function draw.set_no_parallax(v) storage.no_parallax = v end

-- One easing step of a view's follow offset `view.po` towards (camera - deck centre) * PARALLAX_CAM; true when it moved.
-- No API call while it is off and settled. The first step snaps (a new view starts on its target, nothing glides in).
local function parallax_step(pi, view)
  local po = view.po
  if not po then
    po = {x = 0, y = 0}; view.po = po
    view.par = parallax_of(game.get_player(pi)) -- drawn by an older build
    for _, ship in pairs(view.ships) do ship.po = po end
  end
  local on = view.par and not storage.no_parallax
  if not on and po.x == 0 and po.y == 0 then po.init = true; return false end -- a later toggle eases, never snaps
  local tx, ty = 0, 0
  if on then
    local player = game.get_player(pi)
    local L = storage.layouts[view.platform_index]
    if not (player and player.valid and L and L.deck) then return false end
    if player.surface.index == view.surface_index then
      tx, ty = geom.cam_offset(player.position, L.deck, type(view.par) == "number" and view.par or PARALLAX_CAM, PARALLAX_MAX)
    else
      on = false -- somewhere else: ease back (the surface event redraws)
    end
    if on and not po.init then po.init = true; po.x, po.y = tx, ty; return true end
  end
  local nx, ny = geom.ease(po.x, tx, PARALLAX_EASE, 1e-5), geom.ease(po.y, ty, PARALLAX_EASE, 1e-5)
  if nx == po.x and ny == po.y then return false end
  po.x, po.y = nx, ny
  return true
end

-- Test hook: idle float off (true) / on (nil).
function draw.set_no_idle(v) storage.no_idle = v end

-- Test hook: the slowest pace (nil = MIN_STEP).
function draw.set_min_step(v) storage.min_step = v end

-- Per tick: queued drawing and ships mid arrive/leave (storage.animating; empty = no work). Anchors never move
-- for viewer movement.
function draw.on_tick()
  if storage.reconcile_at and game.tick >= storage.reconcile_at then
    storage.reconcile_at = nil
    draw.reconcile_all()
  end
  if storage.draw_queue[1] then process_queue(FV_DRAW_BUDGET) end
  -- parked ships float and follow the camera (ships under way are moved by move_anchor below)
  local idle_on = not storage.no_idle
  for pi, view in pairs(storage.views) do
    local moved = parallax_step(pi, view)
    if idle_on or moved then
      local step = view.step or geom.float_step() -- a view drawn by an older build: balanced
      for idx, ship in pairs(view.ships) do
        if idle_on and not ship.idle and view.float ~= false then -- drawn by an older build: take the float from its layout box
          local L = storage.layouts[view.platform_index]
          local box = L and L.ships[idx]
          if box then ship.idle = idle_of(box) end
        end
        if ship.anim then
          ship.at = nil -- the animation moves the anchor: the next idle step starts from scratch
        elseif ship.anchor.valid and (moved or (idle_on and ship.idle)) then
          local pos, at = current_pos(ship), ship.at
          -- the engine stores positions in 1/256 tile: a float step that lands on the same grain would move nothing
          -- on screen but still cost a move of every attached object (0.5.0; only matters for smooth, step 0)
          if moved or not at or ((math.abs(pos.x - at.x) >= step or math.abs(pos.y - at.y) >= step)
              and not geom.same_grain(pos, at)) then
            ship.anchor.teleport(pos)
            ship.at = pos
          end
        end
      end
    end
  end
  -- travelling viewers: once within PLANET_KM of the destination, its ships are wanted (and dropped again if the
  -- platform turns away)
  for pi in pairs(storage.transit) do
    local player = game.get_player(pi)
    local pl = player and player.valid and player.surface.platform
    if not (pl and pl.valid and pl.space_connection and not pl.space_location) then
      storage.transit[pi] = nil
    else
      local dest = destination(pl)
      local km = dest and km_to(pl, dest)
      local want = km and km < planet_km_on(pl) and dest or nil
      if want ~= storage.approaching[pi] then
        storage.approaching[pi] = want
        draw.reconcile(pi)
      end
    end
  end
  if next(storage.animating) == nil then return end
  -- ships under way whose sprites may need a new frame: {ship, pi, idx}, worked off under FV_FRAME_BUDGET below
  local due = {}
  local budget = FV_FRAME_BUDGET
  for pi, set in pairs(storage.animating) do
    local view, player = storage.views[pi], game.get_player(pi)
    if not (view and player and player.valid) then
      draw.clear(pi)
    else
      for idx in pairs(set) do
        local ship = view.ships[idx]
        if not (ship and ship.anim) then
          set[idx] = nil
        elseif not ship.anchor.valid then
          drop_ship(pi, view, idx, ship)
        else
          local anim = ship.anim
          if anim.approach then
            -- set by the viewer's remaining distance; arrived or turned away = back to stepping
            local pl = player.surface.platform
            local dest = storage.approaching[pi]
            local km = dest and pl and pl.valid and not pl.space_location and km_to(pl, dest)
            if km then anim.n = math.min(ANIM_TICKS, ANIM_TICKS * km / planet_km_on(pl)) else anim.approach = nil end
          end
          if not anim.approach then
            local own_pl = player.surface.platform
            anim.n = anim.n + anim.dir * step_of(player.force, anim.mover, anim.dir,
              own_pl and own_pl.valid and anim.mover == own_pl.index)
          end
          if anim.dir == 1 and anim.n >= ANIM_TICKS then
            destroy_ship(ship); view.ships[idx] = nil; set[idx] = nil
            -- the ship is gone for good: forget its spot (a later arrival rolls a new one)
            local pl = player.surface.platform
            if pl and pl.valid then prune_layout(pl, draw.visible_ships(pl)) end
          elseif anim.dir == -1 and anim.n <= 0 then
            anim.n = 0
            move_anchor(ship)
            budget = budget - apply_frame(ship) -- the parked frame is always exact, whatever the budget
            ship.anim = nil; set[idx] = nil
          else
            move_anchor(ship)
            due[#due + 1] = {ship = ship, pi = pi, idx = idx}
          end
        end
      end
      if next(set) == nil then storage.animating[pi] = nil end
      if next(view.ships) == nil then draw.clear(pi) end
    end
  end
  -- least recently updated first (ties by viewer, then ship: same order on every peer); at least one per tick
  table.sort(due, function(a, b)
    local ta, tb = a.ship.drawn_tick or -1, b.ship.drawn_tick or -1
    if ta ~= tb then return ta < tb end
    if a.pi ~= b.pi then return a.pi < b.pi end
    return a.idx < b.idx
  end)
  for i, d in ipairs(due) do
    if budget <= 0 and i > 1 then break end
    if d.ship.anim and d.ship.anchor.valid then budget = budget - apply_frame(d.ship) end
  end
end

-- A platform's surface is going away: forget its model and remove it from every view.
function draw.drop_platform(platform_index)
  storage.models[platform_index] = nil
  storage.dirty[platform_index] = nil
  storage.rebuild_wait[platform_index] = nil
  storage.bounds[platform_index] = nil
  storage.layouts[platform_index] = nil
  for _, L in pairs(storage.layouts) do L.ships[platform_index] = nil end
  for _, view in pairs(storage.views) do
    local ship = view.ships[platform_index]
    if ship then destroy_ship(ship); view.ships[platform_index] = nil end
  end
  for pi, set in pairs(storage.animating) do
    set[platform_index] = nil
    if next(set) == nil then storage.animating[pi] = nil end
  end
end

-- Redraw for everyone we know about (and every connected player).
function draw.refresh_all()
  for pi in pairs(storage.surfaces) do draw.refresh(pi) end
  for pi in pairs(storage.views) do if not storage.surfaces[pi] then draw.refresh(pi) end end
  for _, p in pairs(game.connected_players) do if not storage.surfaces[p.index] then draw.refresh(p.index) end end
end

-- configuration_changed: whatever an older version left in storage (views with depth/follow/slots, last_pos,
-- anchors, pictures) is thrown away; the caller redraws from scratch.
function draw.reset()
  for _, view in pairs(storage.views) do
    for _, ship in pairs(view.ships) do
      if ship.anchor and ship.anchor.valid then ship.anchor.destroy() end
    end
  end
  rendering.clear("fleet-view")
  for _, surface in pairs(game.surfaces) do
    for _, a in pairs(surface.find_entities_filtered{name = "fv-anchor"}) do a.destroy() end
  end
  storage.views = {}
  storage.animating = {}
  storage.draw_queue = {}
  storage.last_pos = nil
  storage.layouts = {}
  storage.bounds = {}
  storage.reconcile_at = nil
  storage.transit = {}
  storage.approaching = {}
end

function draw.drop_models()
  storage.models = {}
  storage.dirty = {}
  storage.rebuild_wait = {}
end

-- Test hook: shape art of the gathered models: per platform counts of belts / curved belts / undergrounds with in-out /
-- pipes with a mask, and the shape sprite names the draw would try (for is_valid_sprite_path checks).
function draw.shape_stats()
  local out = {}
  for idx, m in pairs(storage.models) do
    local r = {belts = 0, curved = 0, ugs = 0, ug_typed = 0, pipes = 0, pipes_masked = 0, names = {}, edges = 0,
      inserters = 0, arms = 0, beacons = 0, beacon_mods = 0, glows = m.glows and #m.glows or 0}
    for i = 1, #(m.edge or {}), 3 do
      r.edges = r.edges + 1
      r.names[edges.sprite_name(m.edge[i + 2])] = true
    end
    for _, e in ipairs(m.ents) do
      local n = e.name
      if arm_sprite(n) then r.arms = r.arms + 1; r.names[arm_sprite(n)] = true end
      if n:find("inserter", 1, true) then r.inserters = r.inserters + 1 end
      if n == "beacon" then
        r.beacons = r.beacons + 1
        if e.mods then
          r.beacon_mods = r.beacon_mods + 1
          if #e.mods > 0 and #e.mods <= 2 then r.names["fv-e-beacon-t" .. table.concat(e.mods)] = true end
        end
      end
      if e.row then r.curved = r.curved + 1; r.names["fv-e-" .. n .. "-r" .. e.row] = true end
      if e.ug then r.ug_typed = r.ug_typed + 1; r.names["fv-e-" .. n .. "-" .. e.ug .. "-" .. (DIR_NAME[e.dir] or "north")] = true end
      if e.pmask then r.pipes_masked = r.pipes_masked + 1; r.names["fv-e-" .. n .. "-m" .. e.pmask] = true end
      if e.name:find("underground-belt", 1, true) then r.ugs = r.ugs + 1
      elseif e.name:find("transport-belt", 1, true) then r.belts = r.belts + 1
      elseif e.name == "pipe" then r.pipes = r.pipes + 1 end
    end
    out[idx] = r
  end
  return out
end

-- Test hook: a fresh gather of one platform: {beacons = {mods...}, glows = n}.
function draw.gather_probe(platform_index)
  local platform
  for _, f in pairs(game.forces) do
    for _, p in pairs(f.platforms) do if p.index == platform_index then platform = p end end
  end
  local m = platform and snapshot.gather(platform)
  local out = {beacons = {}, glows = 0, n = m and #m.ents or -1}
  if m then
    for _, e in ipairs(m.ents) do
      if e.name == "beacon" then out.beacons[#out.beacons + 1] = e.mods end
    end
    out.glows = #m.glows
  end
  return out
end

-- Test hook: a fresh gather of one platform, returns the pipe masks {x, y, pmask} in absolute tile positions.
function draw.pipe_probe(platform_index)
  local platform
  for _, f in pairs(game.forces) do
    for _, p in pairs(f.platforms) do if p.index == platform_index then platform = p end end
  end
  local m = platform and snapshot.gather(platform)
  local out = {}
  if m then
    for _, e in ipairs(m.ents) do
      if e.name == "pipe" then out[#out + 1] = {x = e.x + m.centre.x, y = e.y + m.centre.y, pmask = e.pmask} end
    end
  end
  return out
end

function draw.stats()
  local gs = storage.gather_stat
  local out = {rng = storage.rng ~= nil, models = 0, queued = #storage.draw_queue, gathers = {total = gs.total, max = gs.max, rebuilds = gs.rebuilds}, dirty = 0, anchors = 0, objects = 0, animating = 0, pending = storage.reconcile_at, views = {}, layouts = storage.layouts}
  for _, set in pairs(storage.animating or {}) do for _ in pairs(set) do out.animating = out.animating + 1 end end
  -- fields only older versions wrote (must be 0 after configuration_changed)
  out.legacy = storage.last_pos and 1 or 0
  for _, view in pairs(storage.views) do
    if view.depth ~= nil or view.slots ~= nil then out.legacy = out.legacy + 1 end
    for _, ship in pairs(view.ships) do
      if ship.follow ~= nil or ship.slot ~= nil then out.legacy = out.legacy + 1 end
    end
  end
  for _, s in pairs(game.surfaces) do
    out.anchors = out.anchors + s.count_entities_filtered{name = "fv-anchor"}
  end
  for _ in pairs(storage.models) do out.models = out.models + 1 end
  for _ in pairs(storage.dirty) do out.dirty = out.dirty + 1 end
  out.objects = #rendering.get_all_objects("fleet-view")
  for pi, view in pairs(storage.views) do
    local v = {surface_index = view.surface_index, par = view.par, step = view.step, po = view.po and {x = view.po.x, y = view.po.y} or nil, ships = {}}
    for idx, ship in pairs(view.ships) do
      local n = 0
      for _, o in ipairs(ship.objects) do if o.valid then n = n + 1 end end
      local first = ship.objects[1]
      v.ships[idx] = {objects = n, anchor = ship.anchor.valid and ship.anchor.position or nil,
        base = ship.base, -- the ship's spot: its anchor position when parked
        k = ship.k, -- its size factor (sets its parallax drift)
        idle = ship.idle and {px = ship.idle.px, py = ship.idle.py, fx = ship.idle.fx, fy = ship.idle.fy} or nil, -- float loop
        anim = ship.anim and {n = ship.anim.n, dir = ship.anim.dir, side = ship.anim.side, mover = ship.anim.mover, approach = ship.anim.approach} or nil,
        first = first and first.valid and {x_scale = first.x_scale, a = first.color.a} or nil}
    end
    out.views[pi] = v
  end
  return out
end

return draw
