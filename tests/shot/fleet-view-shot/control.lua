-- Screenshot driver (not shipped). Viewer on platform-2, three shots with the real renderer:
--   1 depth+detail on, 2 detail off (via the real setting), 3 depth on again, viewer moved 20 tiles.
-- Camera stays fixed in world space so shot 3 shows the parallax against shot 1.
local SEED = require("seed")  -- spot seed for random and anim mode (require only works at control.lua parse time)
local LAYERS = require("layers")  -- the three fleet-view render layers of this build (vp mode markers)
local PAR_OK, PAR = pcall(require, "par")  -- pan mode: parallax setting (tools/shot-linux.sh FV_PAR)
local mode = require("mode")  -- "fleet" (3 shots), "default" (the shipped layout at zoom 0.5), "fixed", "random", "anim" (frames)
local ZOOM = 0.25         -- widest normal zoom that keeps both ships in frame even after the 20-tile move
local W, H = 1920, 1080
local SETTLE = 240        -- ticks for staged drawing (150 objects/tick) + gathers (1/tick)
local function P() return game.connected_players[1] or game.get_player("holyskib") end
local function shot(name, cam)
  game.take_screenshot{player = P(), surface = P().surface, position = cam, resolution = {W, H}, zoom = ZOOM,
    path = name, show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
  log("FVSHOT " .. name .. " cam " .. serpent.line(cam))
end
local function set(name, v) remote.call("fleet-view", "set_setting", P().index, name, v) end
local function shot_z(name, cam, zoom)
  game.take_screenshot{player = P(), surface = P().surface, position = cam, resolution = {W, H}, zoom = zoom,
    path = name, show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
  log("FVSHOT " .. name .. " cam " .. serpent.line(cam) .. " zoom " .. zoom)
end
-- default mode: the shipped layout, viewer 3 tiles in from the top deck edge, one shot at zoom 0.5.
local function default_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 10 then
    local hub = plat.hub.position
    local best
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      if math.abs(tl.position.x - hub.x) <= 2 and (not best or tl.position.y < best) then best = tl.position.y end
    end
    p.teleport({hub.x + 0.5, best + 3.5}, plat.surface)
    set("fleet-view-detail", true)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    log("FVSHOT queued " .. s.queued .. " animating " .. s.animating .. " objects " .. s.objects .. " player " .. serpent.line(p.position))
    for idx, sh in pairs(s.views[p.index].ships) do
      log("FVSHOT   ship " .. idx .. " anchor " .. serpent.line(sh.anchor) .. " objects " .. sh.objects)
    end
    shot_z("fv-shot-default-zoom05.png", p.position, 0.5)
    -- close-ups of every drawn ship (zoom 2 on its anchor) to judge individual buildings
    local list = {}
    for idx, sh in pairs(s.views[p.index].ships) do list[#list + 1] = {idx = idx, a = sh.anchor} end
    table.sort(list, function(a, b) return a.idx < b.idx end)
    for _, it in ipairs(list) do shot_z("fv-shot-default-ship" .. it.idx .. ".png", it.a, 2) end
  end
end
-- fixed mode: ships are fixed in space above the deck. Viewer on platform-2; shots with the camera on the viewer:
-- 3.5 tiles inside the top edge at zoom 0.5 and 1.0, then standing at the deck centre at zoom 0.5.
local function fixed_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 10 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2, top = miny}
    log("FVSHOT deck " .. serpent.line(storage.deck))
    set("fleet-view-detail", true)
    p.teleport({storage.deck.cx, storage.deck.top + 3.5}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    log("FVSHOT queued " .. s.queued .. " objects " .. s.objects .. " player " .. serpent.line(p.position))
    for idx, sh in pairs(s.views[p.index].ships) do
      log("FVSHOT   ship " .. idx .. " anchor " .. serpent.line(sh.anchor) .. " objects " .. sh.objects)
    end
    log("FVSHOT layout " .. serpent.line(s.layouts[plat.index]))
    shot_z("fv-shot-fixed-top-zoom05.png", p.position, 0.5)
    shot_z("fv-shot-fixed-top-zoom1.png", p.position, 1.0)
    p.teleport({storage.deck.cx, storage.deck.cy}, plat.surface)
  elseif t == 10 + SETTLE + 30 then
    shot_z("fv-shot-fixed-centre-zoom05.png", p.position, 0.5)
  end
end
-- random mode: spots are random per seed. Viewer at the deck centre, zoom 0.35, one shot (FV_SEED picks the seed).
local function random_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2}
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({storage.deck.cx, storage.deck.cy}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 5 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    log("FVSHOT queued " .. s.queued .. " objects " .. s.objects .. " deck " .. serpent.line(storage.deck))
    log("FVSHOT layout " .. serpent.line(s.layouts[plat.index]))
    shot_z("fv-shot-random.png", p.position, 0.35)
  end
end
-- anim mode: how a ship travels. Viewer at the deck centre of platform-2 (as in random mode); platform-3 leaves (flies on
-- ahead = up the screen), waits, then comes back (rises from behind into a NEW spot). Frames are taken on a FIXED tick
-- schedule, every FRAME_STEP ticks WITHIN each phase (leave, arrive), so the PNG count is known in advance (tools/shot.sh
-- EXPECT = 2 x ANIM_COUNT = 142). The 30-tick wait between the phases is not filmed: tools/gif.sh plays the frames at
-- 60 / FRAME_STEP = 10 fps, which is real time inside each phase, and that wait plays as one frame step (0.1 s).
-- Two cameras per frame, ONE zero-padded counter across both phases (lexical order = time order), 1280x720:
--   fv-shot-anim-wide-NNN.png   deck centre, zoom fitting the deck box + MARGIN tiles on every side (capped at 0.5)
--   fv-shot-anim-close-NNN.png  the phase's spot, centred CLOSE_OFFSET tiles ahead of it (up) while leaving and behind
--                               it (down) while arriving, zoom CLOSE_ZOOM
local AW, AH = 1280, 720
local FRAME_STEP = 6
local MARGIN, CLOSE_ZOOM, CLOSE_OFFSET = 50, 0.45, 12
local T_START = 5                          -- setup: viewer, detail on, seed, show
local T_LEAVE = T_START + SETTLE           -- platform-3 leaves; its first frame is taken here
local LEAVE_SPAN = 180 + 12                -- the 180-tick leave plus a short hold on the empty scene
local T_BACK = T_LEAVE + LEAVE_SPAN + 30   -- platform-3 comes back 30 ticks after the last leave frame
local ARRIVE_SPAN = 222                    -- staged fill (~10 ticks) + the 180-tick arrival + 20 ticks, with margin
local ANIM_FRAMES, ANIM_COUNT = {}, 0      -- [relative tick] = {phase, counter}
for _, ph in ipairs{{"leave", T_LEAVE, LEAVE_SPAN}, {"arrive", T_BACK, ARRIVE_SPAN}} do
  for dt = 0, ph[3], FRAME_STEP do
    ANIM_COUNT = ANIM_COUNT + 1
    ANIM_FRAMES[ph[2] + dt] = {ph[1], ANIM_COUNT}
  end
end
local function anim_shot(name, pos, zoom)
  game.take_screenshot{player = P(), surface = P().surface, position = pos, resolution = {AW, AH}, zoom = zoom,
    path = name, show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
end
-- platform-3 parked at / away from the viewer's location (written like the headless test does; the mod is told
-- through the same remote the platform state event would reach)
local function anim_move(loc)
  game.surfaces["platform-3"].platform.space_location = loc
  remote.call("fleet-view", "platforms_changed")
end
-- The centre of platform-3's current spot (its box in the viewer platform's layout), read from stats.
local function anim_spot(plat)
  local L = remote.call("fleet-view", "stats").layouts[plat.index]
  local box = L and L.ships[storage.idx3]
  if not box then error("fleet-view-shot anim: platform-3 has no spot around platform-2 (is it parked at the same location?)") end
  log("FVSHOT anim spot " .. serpent.line(box))
  return {x = box.x, y = box.y}
end
local function anim_frame(p, phase, n)
  local sh = (remote.call("fleet-view", "stats").views[p.index] or {ships = {}}).ships[storage.idx3]
  log(string.format("FVSHOT anim %03d %s tick %d anim %s anchor %s", n, phase, game.tick,
    serpent.line(sh and sh.anim), serpent.line(sh and sh.anchor)))
  local dy = phase == "leave" and -CLOSE_OFFSET or CLOSE_OFFSET   -- screen y: ahead (up) leaving, behind (down) arriving
  anim_shot(string.format("fv-shot-anim-wide-%03d.png", n), {storage.deck.cx, storage.deck.cy}, storage.wide_zoom)
  anim_shot(string.format("fv-shot-anim-close-%03d.png", n), {storage.spot.x, storage.spot.y + dy}, CLOSE_ZOOM)
end
local function anim_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == T_START then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    local w, h = maxx - minx + 1, maxy - miny + 1
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2, w = w, h = h}
    -- zoom 1 = 32 px per tile: the largest zoom that still shows the deck box plus MARGIN tiles on every side
    storage.wide_zoom = math.min(0.5, AW / (32 * (w + 2 * MARGIN)), AH / (32 * (h + 2 * MARGIN)))
    storage.idx3 = game.surfaces["platform-3"].platform.index
    log("FVSHOT anim deck " .. serpent.line(storage.deck) .. " wide zoom " .. storage.wide_zoom .. " frames " .. ANIM_COUNT
      .. " png " .. 2 * ANIM_COUNT)
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({storage.deck.cx, storage.deck.cy}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == T_LEAVE then
    local s = remote.call("fleet-view", "stats")
    log("FVSHOT queued " .. s.queued .. " objects " .. s.objects .. " deck " .. serpent.line(storage.deck))
    log("FVSHOT layout " .. serpent.line(s.layouts[plat.index]))
    storage.spot = anim_spot(plat)
    anim_move("vulcanus")
  elseif t == T_BACK then
    anim_move("nauvis")
    storage.spot = anim_spot(plat)   -- a new arrival rolls a NEW spot, already in the layout (the anchor exists now)
  end
  local fr = ANIM_FRAMES[t]
  if fr then anim_frame(p, fr[1], fr[2]) end
end
-- idle mode: parked ships floating. Viewer at deck centre; after SETTLE, one 1280x720 frame EVERY tick for IDLE_FRAMES
-- ticks at zoom IDLE_ZOOM (play zoom), camera fixed on the deck centre: fv-shot-idle-NNNN.png = a true 60 fps clip.
local IDLE = require("idle")   -- {frames, zoom}, written by tools/shot-linux.sh (FV_IDLE_FRAMES, FV_IDLE_ZOOM)
local IDLE_FRAMES, IDLE_ZOOM, IDLE_SHIP = IDLE[1], IDLE[2], IDLE[3] or 0   -- IDLE_SHIP > 0: camera follows that ship's anchor
local function idle_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.cam = {(minx + maxx + 1) / 2, (miny + maxy + 1) / 2}
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport(storage.cam, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t > 5 + SETTLE and t <= 5 + SETTLE + IDLE_FRAMES then
    local n = t - 5 - SETTLE
    local cam = storage.cam
    if IDLE_SHIP > 0 then
      local sh = (remote.call("fleet-view", "stats").views[p.index] or {ships = {}}).ships[IDLE_SHIP]
      if sh and sh.anchor then cam = {sh.anchor.x, sh.anchor.y} end
    end
    game.take_screenshot{player = p, surface = p.surface, position = cam, resolution = {1280, 720}, zoom = IDLE_ZOOM,
      path = string.format("fv-shot-idle-%04d.png", n), show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
    if n == IDLE_FRAMES then log("FVSHOT idle done") end
    if n % 60 == 1 then
      for idx, sh in pairs((remote.call("fleet-view", "stats").views[p.index] or {ships = {}}).ships) do
        log(string.format("FVSHOT idle %04d ship %d anchor %s", n, idx, serpent.line(sh.anchor)))
      end
    end
  end
end
-- pan mode: a camera pan across the deck with the ships in view, one 1280x720 frame EVERY tick (a 60 fps clip), zoom PAN_ZOOM.
-- Parallax on/off comes from par.lua (tools/shot-linux.sh FV_PAR); the camera is the viewer walking (player.position).
-- Also logs what the API gives for the camera in remote view (position = camera, physical_position = character).
local PAN_ZOOM, PAN_HOLD, PAN_MOVE, PAN_RANGE = 0.5, 40, 300, 22
local function pan_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.cam = {(minx + maxx + 1) / 2, (miny + maxy + 1) / 2}
    set("fleet-view-detail", true)
    set("fleet-view-parallax", (not PAR_OK or PAR) and "medium" or "off")
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport(storage.cam, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 5 + SETTLE - 20 then
    -- API probe: character walking vs remote view
    log("FVSHOT probe walking position " .. serpent.line(p.position) .. " physical " .. serpent.line(p.physical_position) .. " render_mode " .. tostring(p.render_mode))
    p.set_controller{type = defines.controllers.remote, position = {storage.cam[1] + 30, storage.cam[2] - 10}, surface = plat.surface}
  elseif t == 5 + SETTLE - 18 then
    log("FVSHOT probe remote position " .. serpent.line(p.position) .. " physical " .. serpent.line(p.physical_position) .. " render_mode " .. tostring(p.render_mode) .. " controller " .. tostring(p.controller_type))
    p.set_controller{type = defines.controllers.remote, position = {storage.cam[1] - 12, storage.cam[2] + 7}, surface = plat.surface}
  elseif t == 5 + SETTLE - 16 then
    log("FVSHOT probe remote moved position " .. serpent.line(p.position) .. " physical " .. serpent.line(p.physical_position))
    p.exit_remote_view()
    p.teleport(storage.cam, plat.surface)
  elseif t > 5 + SETTLE and t <= 5 + SETTLE + PAN_HOLD + PAN_MOVE + PAN_HOLD then
    local n = t - 5 - SETTLE
    local f = math.min(1, math.max(0, (n - PAN_HOLD) / PAN_MOVE))
    f = f * f * (3 - 2 * f)
    local x = storage.cam[1] - PAN_RANGE + 2 * PAN_RANGE * f
    p.teleport({x, storage.cam[2]}, plat.surface)
    game.take_screenshot{player = p, surface = p.surface, position = p.position, resolution = {1280, 720}, zoom = PAN_ZOOM,
      path = string.format("fv-shot-pan-%04d.png", n), show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
    if n % 30 == 1 then
      for idx, sh in pairs((remote.call("fleet-view", "stats").views[p.index] or {ships = {}}).ships) do
        log(string.format("FVSHOT pan %04d cam %.2f ship %d anchor %s", n, p.position.x, idx, serpent.line(sh.anchor)))
      end
    end
    if n == PAN_HOLD * 2 + PAN_MOVE then log("FVSHOT dirs done") end
  end
end
-- vp mode: Visible Planets in Space (portal report 2026-11-03, floor vanishes over the planet). Viewer at the deck
-- centre. A mod cannot change another mod's settings, so tools/shot-linux.sh sets VP's planet scale default to
-- VP_SCALE in its test copy (FV_VP_SCALE). Shots at two times. Plus marker sprites on the three fleet-view layers (FV_LAYERS,
-- layers.lua), half over the own deck and half over space, to see which layers the deck still hides.
-- Without VP the same shots run, so the shifted layers can be compared with the shipped ones.
local function vp_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local vp = script.active_mods["visible-planets"] ~= nil
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2, minx = minx, maxx = maxx, miny = miny, maxy = maxy}
    log("FVSHOT vp=" .. tostring(vp) .. " deck " .. serpent.line(storage.deck) .. " layers " .. serpent.line(LAYERS))
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({storage.deck.cx, storage.deck.cy}, plat.surface)
    remote.call("fleet-view", "show", p.index)
    -- markers: one per layer, straddling the deck's left edge (left half over space, right half over the deck)
    local L = LAYERS
    for i, r in ipairs{{"signal-green", L[1]}, {"signal-blue", L[2]}, {"signal-red", L[3]}} do
      rendering.draw_sprite{sprite = "virtual-signal/" .. r[1], surface = plat.surface, render_layer = r[2],
        target = {minx, storage.deck.cy - 12 + i * 7}, x_scale = 6, y_scale = 6}
    end
  elseif t == 5 + SETTLE then
    shot_z("fv-shot-vp-1-before.png", {storage.deck.cx, storage.deck.cy}, 0.15)
  elseif t == 5 + SETTLE + 60 then
    local s = remote.call("fleet-view", "stats")
    for idx, sh in pairs(s.views[p.index].ships) do log("FVSHOT ship " .. idx .. " anchor " .. serpent.line(sh.anchor)) end
    shot_z("fv-shot-vp-2-after.png", {storage.deck.cx, storage.deck.cy}, 0.15)
    shot_z("fv-shot-vp-3-markers.png", {storage.deck.minx, storage.deck.cy - 1}, 0.6)
    local list = {}
    for idx, sh in pairs(s.views[p.index].ships) do list[#list + 1] = {idx = idx, a = sh.anchor} end
    table.sort(list, function(a, b) return a.idx < b.idx end)
    for i = 1, math.min(3, #list) do shot_z("fv-shot-vp-4-ship" .. list[i].idx .. ".png", list[i].a, 1) end
  end
end
-- deck mode: which render layers does the OWN deck hide? One marker per layer (DECK_LAYERS, numbers as strings),
-- each fully on bare deck floor (a strip of foundation the mode lays next to platform-2), one close-up per marker. Hidden =
-- safe for fleet sprites; visible = the fleet would draw over the viewer's own floor. (2026-11-04: "decals" (10) was
-- found drawn over bare deck floor in the vp-mode zoom.)
local DECK_LAYERS = {"1", "2", "3", "5", "7", "9", "10"}
local function deck_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local s = plat.surface
  if t == 5 then
    -- the save's decks are fully built: lay a bare strip of foundation next to platform-2 (save copy only)
    local x0, y0 = 60, -4
    local tiles = {}
    for x = x0, x0 + 6 * #DECK_LAYERS do for y = y0, y0 + 8 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    s.set_tiles(tiles)
    p.teleport({x0 + 3 * #DECK_LAYERS, y0 + 4}, s)   -- screenshots use the player's surface
    local spots = {}
    for i = 1, #DECK_LAYERS do spots[i] = {x0 + 3 + 6 * (i - 1), y0 + 4.5} end
    storage.spots = spots
    -- second row: layers 0, 1, 2 across the strip's bottom edge (half over the underside art that hangs below it)
    for i, l in ipairs{"0", "1", "2"} do
      rendering.draw_sprite{sprite = "virtual-signal/signal-blue", surface = s, render_layer = l,
        target = {x0 + 3 + 6 * (i - 1), y0 + 9.5}, x_scale = 1.5, y_scale = 1.5}
      log("FVSHOT edge marker layer " .. l .. " at x " .. (x0 + 3 + 6 * (i - 1)))
    end
    for i, pos in ipairs(spots) do
      rendering.draw_sprite{sprite = "virtual-signal/signal-red", surface = s, render_layer = DECK_LAYERS[i],
        target = pos, x_scale = 1.5, y_scale = 1.5}
      log("FVSHOT deck marker layer " .. DECK_LAYERS[i] .. " at " .. serpent.line(pos))
    end
    if #spots < #DECK_LAYERS then log("FVSHOT deck only " .. #spots .. " empty spots") end
  elseif t == 30 then
    shot_z("fv-shot-deck-strip.png", {63 + 3 * (#DECK_LAYERS - 1), 0.5}, 0.6)
    shot_z("fv-shot-deck-edge.png", {69, 5.5}, 2)
  end
end
-- dump mode: what the background platform (platform-3) is made of; log only.
local function dump_step(t, p)
  if t ~= 5 then return end
  local plat = game.surfaces["platform-3"].platform
  local sf = plat.surface
  local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
  for _, tl in pairs(sf.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
    minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
    miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
  end
  log("FVSHOT dump tiles " .. serpent.line({minx, maxx, miny, maxy}) .. " hub " .. serpent.line(plat.hub.position))
  local counts = {}
  for _, e in pairs(sf.find_entities_filtered{area = {{-300, -300}, {300, 300}}}) do
    if e.type == "cargo-bay" or e.type == "space-platform-hub" or e.type == "fusion-generator" or e.type == "fusion-reactor" then
      log("FVSHOT dump " .. e.name .. " " .. serpent.line(e.position) .. " dir " .. e.direction)
    end
    counts[e.name] = (counts[e.name] or 0) + 1
  end
  log("FVSHOT dump counts " .. serpent.line(counts))
end
-- dirs mode (0.4.4): fusion generators facing all four ways + extra cargo bays on platform-3's hub, then (a) the
-- Fleet View ship at zoom 3 (anchor centred; ship scale is 0.16 x k, k = 0.85..1.15) and (b) the REAL platform-3 at
-- zoom 0.48 (= 3 x 0.16) centred on its tile centroid. Edits the save COPY only.
local function dirs_prepare()
  local plat = game.surfaces["platform-3"].platform
  local sf = plat.surface
  local tiles = {}
  for x = 20, 60 do for y = -12, 8 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
  for x = -12, 12 do for y = -12, 12 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
  sf.set_tiles(tiles)
  local hub = plat.hub
  for _, e in pairs(sf.find_entities_filtered{area = {{-14, -14}, {14, 14}}}) do
    if e ~= hub and e.type ~= "cargo-bay" then e.destroy() end
  end
  for _, e in pairs(sf.find_entities_filtered{area = {{19, -13}, {62, 9}}}) do e.destroy() end
  for _, b in ipairs{{-6, -2}, {-6, 2}, {6, -2}, {6, 2}, {-2, 6}, {2, 6}, {-2, -10}, {2, -10}} do
    local e = sf.create_entity{name = "cargo-bay", position = b, force = plat.force, raise_built = true}
    log("FVSHOT dirs bay " .. serpent.line(b) .. " " .. tostring(e ~= nil))
  end
  for i, d in ipairs{defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west} do
    local pos = {24 + (i - 1) * 9, -2}
    local e = sf.create_entity{name = "fusion-generator", position = pos, direction = d, force = plat.force, raise_built = true}
    log("FVSHOT dirs fusion " .. serpent.line(pos) .. " dir " .. d .. " " .. tostring(e ~= nil))
  end
  remote.call("fleet-view", "platforms_changed")
end
local function dirs_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local p3 = game.surfaces["platform-3"].platform
  if t == 2 then dirs_prepare()
  elseif t == 10 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2}
    set("fleet-view-detail", true)
    local hub = plat.hub.position
    local best
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      if math.abs(tl.position.x - hub.x) <= 2 and (not best or tl.position.y < best) then best = tl.position.y end
    end
    p.teleport({hub.x + 0.5, best + 3.5}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[p3.index]
    log("FVSHOT dirs ship " .. serpent.line(sh and sh.anchor) .. " objects " .. tostring(sh and sh.objects) .. " queued " .. s.queued)
    -- centroid of platform-3's foundation tiles = the model centre (anchor)
    local sx, sy, n = 0, 0, 0
    for _, tl in pairs(p3.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      sx = sx + tl.position.x + 0.5; sy = sy + tl.position.y + 0.5; n = n + 1
    end
    local c3 = {sx / n, sy / n}
    local k = s.layouts[plat.index].ships[p3.index].k
    local S = 0.16 * k
    storage.cam3, storage.S = c3, S
    log("FVSHOT dirs k " .. k .. " S " .. S)
    local function at(wx, wy) return {x = sh.anchor.x + (wx - c3[1]) * S, y = sh.anchor.y + (wy - c3[2]) * S} end
    shot_z("fv-shot-dirs-fleetview.png", sh.anchor, 3)
    shot_z("fv-shot-dirs-fleetview-fusion.png", at(37.5, -2), 6)
    shot_z("fv-shot-dirs-fleetview-hub.png", at(0, -2), 6)
  elseif t == 10 + SETTLE + 5 then
    remote.call("fleet-view", "clear", p.index)   -- screenshots render at the end of the tick: clear only later
    p.teleport(storage.cam3, game.surfaces["platform-3"])
  elseif t == 10 + SETTLE + 45 then
    local S = storage.S
    shot_z("fv-shot-dirs-real.png", storage.cam3, 3 * S)
    shot_z("fv-shot-dirs-real-fusion.png", {37.5, -2}, 6 * S)
    shot_z("fv-shot-dirs-real-hub.png", {0, -2}, 6 * S)
    shot_z("fv-shot-dirs-real-fusion-z1.png", {37.5, -2}, 1)
    shot_z("fv-shot-dirs-real-hub-z1.png", {0, -2}, 1)
    log("FVSHOT dirs done")
  end
end
-- seams mode (0.4.8): the dirs patch (a big plain floor on platform-3), then one 1280x720 frame EVERY tick for IDLE_FRAMES
-- ticks at IDLE_ZOOM, camera on the patch centre of the ship (follows the floating anchor): fv-shot-seams-NNNN.png.
-- `art` mode (0.4.6 shape art): on a COPY, a patch of platform-3 (x 20..60, y -12..8) with inserters facing N/E/S/W,
-- a beacon with 2 modules, 3 more with other module tiers, lit/unlit lamps, underground pairs (east, north), two belt loops (clockwise + counter-clockwise = all 8 curves)
-- and a pipe network (cross, T, corners, endings); shot like `dirs` (Fleet View ship vs the real platform at the same scale).
local function art_prepare()
  dirs_prepare()
  local plat = game.surfaces["platform-3"].platform
  local sf, force = plat.surface, plat.force
  for _, e in pairs(sf.find_entities_filtered{area = {{19, -13}, {62, 9}}}) do e.destroy() end
  local D = defines.direction
  local function mk(name, x, y, dir, extra)
    local spec = {name = name, position = {x, y}, direction = dir, force = force}
    for k, v in pairs(extra or {}) do spec[k] = v end
    local e = sf.create_entity(spec)
    if not e then log("FVSHOT art FAILED " .. name .. " " .. x .. "," .. y) end
    return e
  end
  for i, d in ipairs{D.north, D.east, D.south, D.west} do mk("inserter", 21.5 + (i - 1) * 2, -10.5, d) end
  local b = mk("beacon", 31.5, -9.5)
  if b then b.get_module_inventory().insert{name = "speed-module", count = 2} end
  -- beacons with different module tiers: empty / tier 1 + empty / tier 2 + tier 3 / tier 3 x2
  local function beacon(x, mods)
    local bb = mk("beacon", x, -9.5)
    if bb then for _, m in ipairs(mods) do bb.get_module_inventory().insert{name = m, count = 1} end end
  end
  beacon(49.5, {}); beacon(53.5, {"speed-module"}); beacon(57.5, {"speed-module-2", "efficiency-module-3"})
  -- lamps: a power source + poles; the first row is always_on (lit, the last one coloured), the second row is off (daytime)
  local src = mk("electric-energy-interface", 47.5, -3.5)
  if src then src.power_production = 1e6 / 60; src.electric_buffer_size = 1e8; src.energy = 1e8 end
  mk("small-electric-pole", 48.5, -3.5); mk("small-electric-pole", 53, -4.5); mk("small-electric-pole", 54, -1.5)
  mk("small-electric-pole", 54, 0.5); mk("small-electric-pole", 57, 0.5)
  for i = 0, 5 do
    local l = mk("small-lamp", 50.5 + i, -3.5)
    if l then l.always_on = true end   -- platform surfaces are always day: lamps stay off unless always_on
    if l and i == 5 then l.color = {r = 0.2, g = 1, b = 0.3} end
  end
  for i = 0, 3 do mk("small-lamp", 52.5 + i, 1.5) end
  mk("transport-belt", 20.5, -5.5, D.east); mk("underground-belt", 21.5, -5.5, D.east, {type = "input"})
  mk("underground-belt", 25.5, -5.5, D.east, {type = "output"}); mk("transport-belt", 26.5, -5.5, D.east)
  mk("transport-belt", 30.5, -1.5, D.north); mk("underground-belt", 30.5, -2.5, D.north, {type = "input"})
  mk("underground-belt", 30.5, -6.5, D.north, {type = "output"}); mk("transport-belt", 30.5, -7.5, D.north)
  local function loop(x0, y0, n, cw)
    local pts = {}
    for i = 0, n - 1 do pts[#pts + 1] = {x0 + i, y0, D.east} end
    for i = 0, n - 1 do pts[#pts + 1] = {x0 + n, y0 + i, D.south} end
    for i = 0, n - 1 do pts[#pts + 1] = {x0 + n - i, y0 + n, D.west} end
    for i = 0, n - 1 do pts[#pts + 1] = {x0, y0 + n - i, D.north} end
    if not cw then   -- counter-clockwise: same square, every belt turned around
      local flip = {[D.east] = D.west, [D.west] = D.east, [D.north] = D.south, [D.south] = D.north}
      for _, q in ipairs(pts) do q[3] = flip[q[3]] end
    end
    for _, q in ipairs(pts) do mk("transport-belt", q[1] + 0.5, q[2] + 0.5, q[3]) end
  end
  loop(36, -11, 4, true); loop(43, -11, 4, false)
  for x = 21, 27 do mk("pipe", x + 0.5, 3.5) end
  for y = 0, 6 do if y ~= 3 then mk("pipe", 24.5, y + 0.5) end end
  for y = 4, 6 do mk("pipe", 27.5, y + 0.5) end
  mk("pipe", 27.5, 2.5)
  for x = 18, 20 do mk("pipe", x + 0.5, 6.5) end
  for y = 4, 5 do mk("pipe", 21.5, y + 0.5) end
  mk("pipe", 21.5, 6.5)
  -- 0.4.8: pipe-to-ground pairs in all four directions (each direction has its own picture), with a pipe on the open end
  mk("pipe", 35.5, 0.5); mk("pipe-to-ground", 35.5, 1.5, D.north); mk("pipe-to-ground", 35.5, 5.5, D.south); mk("pipe", 35.5, 6.5)
  mk("pipe", 37.5, 3.5); mk("pipe-to-ground", 38.5, 3.5, D.west); mk("pipe-to-ground", 42.5, 3.5, D.east); mk("pipe", 43.5, 3.5)
  remote.call("fleet-view", "platforms_changed")
end

local function art_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local p3 = game.surfaces["platform-3"].platform
  if t == 2 then art_prepare()
  elseif t == 10 then
    set("fleet-view-detail", true)
    local hub = plat.hub.position
    p.teleport({hub.x + 0.5, hub.y - 6}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[p3.index]
    local sx, sy, n = 0, 0, 0
    for _, tl in pairs(p3.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      sx = sx + tl.position.x + 0.5; sy = sy + tl.position.y + 0.5; n = n + 1
    end
    local c3 = {sx / n, sy / n}
    local S = 0.16 * s.layouts[plat.index].ships[p3.index].k
    storage.cam3, storage.S = c3, S
    local function at(wx, wy) return {x = sh.anchor.x + (wx - c3[1]) * S, y = sh.anchor.y + (wy - c3[2]) * S} end
    shot_z("fv-shot-art-fleetview-top.png", at(34, -6), 6)
    shot_z("fv-shot-art-fleetview-pipes.png", at(24, 3.5), 6)
    shot_z("fv-shot-art-fleetview-mods.png", at(53.5, -4), 10)
    shot_z("fv-shot-art-fleetview-ug.png", at(26, -4), 12)    -- 0.4.8: underground exits (east pair, north pair)
    shot_z("fv-shot-art-fleetview-ptg.png", at(39.5, 3.5), 12) -- 0.4.8: pipe-to-ground N/S/W/E
    for _, l in pairs(p3.surface.find_entities_filtered{name = "small-lamp"}) do
      log("FVSHOT art lamp " .. l.position.x .. "," .. l.position.y .. " status " .. (function() for k, v in pairs(defines.entity_status) do if v == l.status then return k end end end)())
    end
    log("FVSHOT art ship objects " .. tostring(sh and sh.objects) .. " queued " .. s.queued)
    for idx, r in pairs(remote.call("fleet-view", "shape_stats")) do log("FVSHOT art edge pieces platform " .. idx .. ": " .. r.edges) end
  elseif t == 10 + SETTLE + 5 then
    remote.call("fleet-view", "clear", p.index)   -- screenshots render at the end of the tick: clear only later
    p.teleport(storage.cam3, game.surfaces["platform-3"])
  elseif t == 10 + SETTLE + 45 then
    local S = storage.S
    shot_z("fv-shot-art-real-top.png", {34, -6}, 6 * S)
    shot_z("fv-shot-art-real-pipes.png", {24, 3.5}, 6 * S)
    shot_z("fv-shot-art-real-mods.png", {53.5, -4}, 10 * S)
    shot_z("fv-shot-art-real-ug.png", {26, -4}, 12 * S)
    shot_z("fv-shot-art-real-ptg.png", {39.5, 3.5}, 12 * S)
    shot_z("fv-shot-art-real-top-z1.png", {34, -6}, 1)
    shot_z("fv-shot-art-real-pipes-z1.png", {24, 3.5}, 1)
    shot_z("fv-shot-art-real-mods-z1.png", {53.5, -4}, 1)
    log("FVSHOT art done")
  end
end

-- `edges` mode (0.4.6 edge art): a test map of deck shapes on a cleared patch of platform-3 (x 20.., y -12..): block (sides,
-- outer corners), L (inner corner), strip (double side, ends), gap + notch (double, u), checker (inner corners), island; shot as
-- the Fleet View ship and the REAL platform at the same scale: fv-shot-edges-{fleetview,real}-{all,a,b}.png (EXPECT=6).
local EDGE_MAP = {
  ".#######..#######..#...#.#.....#..",
  ".#######..#######..#...#.#........",
  ".#######..###......#...#.#........",
  ".#######..###......#...###..#.#...",
  "..................#..........#....",
}
local function edges_prepare()
  local plat = game.surfaces["platform-3"].platform
  local sf = plat.surface
  for _, e in pairs(sf.find_entities_filtered{area = {{19, -14}, {62, 2}}}) do
    if e ~= plat.hub and e.type ~= "cargo-bay" then e.destroy() end
  end
  local tiles = {}
  for x = 19, 60 do for y = -14, 1 do tiles[#tiles + 1] = {name = "empty-space", position = {x, y}} end end
  for r, line in ipairs(EDGE_MAP) do
    for c = 1, #line do
      if line:sub(c, c) == "#" then tiles[#tiles + 1] = {name = "space-platform-foundation", position = {19 + c, -13 + r}} end
    end
  end
  sf.set_tiles(tiles)
  remote.call("fleet-view", "platforms_changed")
end
local EDGE_SHOTS = {{"all", 17, -9, 5}, {"a", 28, -9, 12}, {"b", 46, -9, 12}}
local function edges_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local p3 = game.surfaces["platform-3"].platform
  if t == 2 then edges_prepare()
  elseif t == 10 then
    set("fleet-view-detail", true)
    local hub = plat.hub.position
    p.teleport({hub.x + 0.5, hub.y - 6}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[p3.index]
    local sx, sy, n = 0, 0, 0
    for _, tl in pairs(p3.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      sx = sx + tl.position.x + 0.5; sy = sy + tl.position.y + 0.5; n = n + 1
    end
    local c3 = {sx / n, sy / n}
    local S = 0.16 * s.layouts[plat.index].ships[p3.index].k
    storage.cam3, storage.S = c3, S
    for _, e in ipairs(EDGE_SHOTS) do
      shot_z("fv-shot-edges-fleetview-" .. e[1] .. ".png", {x = sh.anchor.x + (e[2] - c3[1]) * S, y = sh.anchor.y + (e[3] - c3[2]) * S}, e[4])
    end
    log("FVSHOT edges ship objects " .. tostring(sh and sh.objects) .. " queued " .. s.queued .. " tiles " .. n)
  elseif t == 10 + SETTLE + 5 then
    remote.call("fleet-view", "clear", p.index)   -- screenshots render at the end of the tick: clear only later
    p.teleport(storage.cam3, game.surfaces["platform-3"])
  elseif t == 10 + SETTLE + 45 then
    local S = storage.S
    for _, e in ipairs(EDGE_SHOTS) do shot_z("fv-shot-edges-real-" .. e[1] .. ".png", {e[2], e[3]}, e[4] * S) end
    log("FVSHOT art done")
  end
end
local function seams_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local p3 = game.surfaces["platform-3"].platform
  if t == 2 then dirs_prepare()
  elseif t == 10 then
    local hub = plat.hub.position
    local best
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      if math.abs(tl.position.x - hub.x) <= 2 and (not best or tl.position.y < best) then best = tl.position.y end
    end
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({hub.x + 0.5, best + 3.5}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local sx, sy, n = 0, 0, 0
    for _, tl in pairs(p3.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      sx = sx + tl.position.x + 0.5; sy = sy + tl.position.y + 0.5; n = n + 1
    end
    storage.c3 = {sx / n, sy / n}
  elseif t > 10 + SETTLE and t <= 10 + SETTLE + IDLE_FRAMES then
    local n = t - 10 - SETTLE
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[p3.index]
    local S = 0.16 * s.layouts[plat.index].ships[p3.index].k
    local cam = {x = sh.anchor.x + (40 - storage.c3[1]) * S, y = sh.anchor.y + (-2 - storage.c3[2]) * S}
    game.take_screenshot{player = p, surface = p.surface, position = cam, resolution = {1280, 720}, zoom = IDLE_ZOOM,
      path = string.format("fv-shot-seams-%04d.png", n), show_gui = false, show_entity_info = false, force_render = true, daytime = 0}
    if n == IDLE_FRAMES then log("FVSHOT idle done") end
  end
end
-- conn mode (0.4.5): experiments for the cargo-bay connection rules. A grid of small bay layouts on a fresh foundation
-- patch of platform-3 (`CONN_BAYS`, bay centres), shot as the REAL platform (t=40) and, with the Fleet View ship, from
-- platform-2 (second half). Edits the save COPY only.
local CONN_BAYS = {
  {24, 0}, {28, 0},                                   -- A pair side by side
  {24, 8}, {24, 12},                                  -- B pair stacked
  {40, 0}, {44, 2},                                   -- C offset 2
  {40, 10}, {44, 11},                                 -- D offset 1
  {56, 0}, {60, 4},                                   -- E diagonal only
  {56, 10}, {61, 10},                                 -- F gap 1
  {56, 18}, {62, 18},                                 -- G gap 2
  {24, 20},                                           -- H single
  {40, 20}, {44, 20}, {44, 24},                       -- I L shape
  {24, 32}, {20, 32}, {28, 32}, {24, 28}, {24, 36},   -- J plus
  {40, 32}, {44, 32}, {40, 36}, {44, 36},             -- K 2x2
}
local CONN_CAMS = { {34, 4}, {58, 10}, {34, 28} }
local function conn_step(t, p)
  local p3 = game.surfaces["platform-3"].platform
  local plat = game.surfaces["platform-2"].platform
  local sf = p3.surface
  if t == 2 then
    local tiles = {}
    for x = 12, 80 do for y = -8, 44 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    sf.set_tiles(tiles)
    for _, e in pairs(sf.find_entities_filtered{area = {{11, -9}, {82, 46}}}) do e.destroy() end
    for _, b in ipairs(CONN_BAYS) do
      local e = sf.create_entity{name = "cargo-bay", position = b, force = p3.force, raise_built = true}
      log("FVSHOT conn bay " .. serpent.line(b) .. " " .. tostring(e ~= nil))
    end
    remote.call("fleet-view", "platforms_changed")
  elseif t == 10 then
    local hub = plat.hub.position
    local best
    for _, tl in pairs(plat.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      if math.abs(tl.position.x - hub.x) <= 2 and (not best or tl.position.y < best) then best = tl.position.y end
    end
    p.teleport({hub.x + 0.5, best + 3.5}, plat.surface)
    set("fleet-view-detail", true)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[p3.index]
    local sx, sy, n = 0, 0, 0
    for _, tl in pairs(sf.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      sx = sx + tl.position.x + 0.5; sy = sy + tl.position.y + 0.5; n = n + 1
    end
    local c3 = {sx / n, sy / n}
    local S = 0.16 * s.layouts[plat.index].ships[p3.index].k
    storage.S = S
    log("FVSHOT conn ship " .. serpent.line(sh and sh.anchor) .. " objects " .. tostring(sh and sh.objects) .. " S " .. S)
    for i, c in ipairs(CONN_CAMS) do
      shot_z("fv-shot-conn-fleetview-" .. i .. ".png", {x = sh.anchor.x + (c[1] - c3[1]) * S, y = sh.anchor.y + (c[2] - c3[2]) * S}, 1.5 / S)
    end
  elseif t == 10 + SETTLE + 5 then
    remote.call("fleet-view", "clear", p.index)
    p.teleport({30, 0}, sf)
  elseif t == 10 + SETTLE + 45 then
    for i, c in ipairs(CONN_CAMS) do shot_z("fv-shot-conn-real-" .. i .. ".png", c, 1.5) end
    log("FVSHOT dirs done")
  end
end
-- transfer mode (0.4.6): zoom transfer. Viewer in remote view over platform-2's ship (the first one), zoom = 0.405 / S
-- (capped at the closest zoom 3), the setting off. Tick A: screenshot of the camera as it is (before); A+1: setting on and
-- the transfer check runs once (remote `transfer_run`, the same function the on_nth_tick handler calls); A+2: screenshot of
-- the SAME region (camera = the player's new position and zoom, on the other platform) = after; A+120: again, after the
-- ships of the new view have been staged in.
local TR_ZOOM = 0.405
local function transfer_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  if t == 5 then
    set("fleet-view-detail", true)
    set("fleet-view-zoom-transfer", false)
    -- parallax off: with it on, a far ship drifts out of the remote camera's reach (the camera is clamped near the
    -- platform, measured y 56) and never settles under it; the parallax term of the mapping is checked headless
    set("fleet-view-parallax", "off")
    remote.call("fleet-view", "set_seed", SEED)
    local hub = plat.hub.position
    p.teleport({hub.x + 0.5, hub.y + 4}, plat.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 5 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local idx, sh = next(s.views[p.index].ships)
    storage.tr = {idx = idx, S = 0.16 * sh.k, k = sh.k}
    log("FVSHOT transfer ship " .. idx .. " k " .. sh.k .. " anchor " .. serpent.line(sh.anchor) .. " objects " .. sh.objects .. " queued " .. s.queued)
    local S = storage.tr.S
    -- a point 3 / 2 model tiles from the ship's centre
    p.set_controller{type = defines.controllers.remote, surface = plat.surface, position = {sh.anchor.x + 3 * S, sh.anchor.y + 2 * S}}
    p.zoom = math.min(3, TR_ZOOM / S)
    log("FVSHOT transfer limits " .. serpent.line(p.zoom_limits) .. " zoom " .. p.zoom .. " S " .. S .. " zoom*S " .. p.zoom * S)
  elseif t > 5 + SETTLE and t < 5 + SETTLE + 40 then
    -- the ship follows the camera a little (parallax): keep re-aiming at its anchor until it settles
    local sh = remote.call("fleet-view", "stats").views[p.index].ships[storage.tr.idx]
    local S = storage.tr.S
    p.set_controller{type = defines.controllers.remote, surface = plat.surface, position = {sh.anchor.x + 3 * S, sh.anchor.y + 2 * S}}
    p.zoom = math.min(3, TR_ZOOM / S)
    if t % 5 == 0 then log("FVSHOT transfer aim t " .. t .. " anchor " .. serpent.line(sh.anchor) .. " cam " .. serpent.line(p.position) .. " base " .. serpent.line(sh.base) .. " par " .. tostring(remote.call("fleet-view", "stats").views[p.index].par) .. " setting " .. tostring(settings.get_player_settings(p)["fleet-view-parallax"].value)) end
  elseif t == 5 + SETTLE + 40 then
    local s = remote.call("fleet-view", "stats")
    local sh = s.views[p.index].ships[storage.tr.idx]
    storage.tr.before = {surface = p.surface.name, pos = {x = p.position.x, y = p.position.y}, zoom = p.zoom}
    log("FVSHOT transfer before " .. serpent.line(storage.tr.before) .. " anchor " .. serpent.line(sh.anchor))
    shot_z("fv-shot-transfer-1-before.png", p.position, p.zoom)
  elseif t == 5 + SETTLE + 41 then
    set("fleet-view-zoom-transfer", true)
    log("FVSHOT transfer render_mode " .. tostring(p.render_mode) .. " game=" .. tostring(defines.render_mode.game) .. " zoom " .. p.zoom)
    log("FVSHOT transfer run -> " .. tostring(remote.call("fleet-view", "transfer_run")))
  elseif t == 5 + SETTLE + 42 then
    log("FVSHOT transfer after " .. serpent.line({surface = p.surface.name, pos = {x = p.position.x, y = p.position.y}, zoom = p.zoom, ctrl = p.controller_type}))
    shot_z("fv-shot-transfer-2-after.png", p.position, p.zoom)
  elseif t == 5 + SETTLE + 160 then
    local s = remote.call("fleet-view", "stats")
    log("FVSHOT transfer later queued " .. s.queued .. " anchors " .. s.anchors .. " objects " .. s.objects)
    shot_z("fv-shot-transfer-3-later.png", p.position, p.zoom)
    log("FVSHOT dirs done")
  end
end
-- cross mode (0.4.9, portal report versuffer): a new platform at platform-2's planet with a 600-tile cross deck (arms
-- 60 wide), viewer at its hub. Ships should sit in the empty corners near the arms (the 0.4.8 rule put them 300+ tiles
-- out, off the wide shot). fv-shot-cross-wide.png (zoom 0.1, whole cross) + fv-shot-cross-ship<n>.png (zoom 0.5).
local function cross_step(t, p)
  if t == 5 then
    local home = game.surfaces["platform-2"].platform.space_location.name
    local cp = game.forces.player.create_space_platform{name = "fv-cross", planet = home, starter_pack = "space-platform-starter-pack"}
    cp.apply_starter_pack()
    storage.cross = cp
    local tiles = {}
    for x = -300, 299 do for y = -30, 29 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    for x = -30, 29 do for y = -300, 299 do if y < -30 or y >= 30 then tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end end
    cp.surface.set_tiles(tiles, true, false, true, true)
  elseif t == 15 then
    local cp = storage.cross
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({cp.hub.position.x, cp.hub.position.y + 4}, cp.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 15 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local L = s.layouts[storage.cross.index]
    log("FVSHOT cross queued " .. s.queued .. " objects " .. s.objects)
    shot_z("fv-shot-cross-wide.png", {0, 0}, 0.1)
    local n = 0
    for _, b in pairs(L and L.ships or {}) do
      n = n + 1
      log("FVSHOT cross ship " .. n .. " " .. string.format("%.1f,%.1f hw %.1f hh %.1f", b.x, b.y, b.hw, b.hh))
      shot_z("fv-shot-cross-ship" .. n .. ".png", {b.x, b.y}, 0.5)
    end
    log("FVSHOT cross done " .. n)
  end
end
-- order mode (2026-11-15, portal report Qazerowl "Rendering on top of edges"): what decides the draw order of script
-- sprites that share ONE render layer (layer 1, the only one under the deck's hanging underside apart from 0)?
-- Pairs of a big blue "back" square and a small red "front" square, all on layer "1", in every order we can think of;
-- per case the log says what each hypothesis predicts. Row C straddles a laid foundation strip's bottom edge (the
-- underside art hangs there). Then close-ups of the real ships (whatever FV_LAYERS says) at zoom 4.
-- B3/B4 use fleet-view's own fv-t2-0 / fv-e sprites: since 0.4.10 those carry sort-key shifts, so they no longer show
-- the plain rule (results above were taken on 0.4.9 sprites).
local ORDER_X, ORDER_Y = 60, 36
local ORDER_SP = 6
local function order_pair(s, cx, cy, first, fy, opts)
  opts = opts or {}
  local back_sprite = opts.back or "virtual-signal/signal-blue"
  local front_sprite = opts.front or "virtual-signal/signal-red"
  local function mk(which)
    local front = which == "F"
    local off = front and {0, fy} or {0, 0}
    local tgt
    if opts.anchor then tgt = {entity = opts.anchor, offset = off} else tgt = {cx + off[1], cy + off[2]} end
    return rendering.draw_sprite{sprite = front and front_sprite or back_sprite, surface = s,
      render_layer = front and (opts.front_layer or "1") or (opts.back_layer or "1"), target = tgt,
      x_scale = front and (opts.fs or 1.2) or (opts.bs or 3), y_scale = front and (opts.fs or 1.2) or (opts.bs or 3)}
  end
  local a = mk(first)
  local b = mk(first == "F" and "B" or "F")
  return first == "F" and a or b, first == "F" and b or a   -- front, back
end
local function order_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local s = plat.surface
  if t == 5 then
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({0, 0}, s)
    remote.call("fleet-view", "show", p.index)
    -- foundation strip for row C: tiles y 22..26, bottom edge at y 27 (underside hangs below it)
    local tiles = {}
    for x = ORDER_X - 4, ORDER_X + 6 * ORDER_SP + 4 do for y = 22, 26 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    s.set_tiles(tiles)
    local bld = "fv-e-assembling-machine-2"
    if not helpers.is_valid_sprite_path(bld) then bld = "item/assembling-machine-2" end
    local floor = helpers.is_valid_sprite_path("fv-t2-0") and "fv-t2-0" or "virtual-signal/signal-blue"
    log("FVSHOT order sprites building " .. bld .. " floor " .. floor)
    local A, B = ORDER_Y, ORDER_Y + ORDER_SP
    local X = function(i) return ORDER_X + ORDER_SP * (i - 1) end
    -- fy > 0 = front sits LOWER on screen (higher y) than the back's centre
    local cases = {
      {"A1 back first, front below", X(1), A, "B", 1},
      {"A2 back first, front above", X(2), A, "B", -1},
      {"A3 front first, front below", X(3), A, "F", 1},
      {"A4 front first, front above", X(4), A, "F", -1},
      {"A5 front first + bring_to_front", X(5), A, "F", -1, {bring = true}},
      {"A6 back first + move_to_back on front", X(6), A, "B", 1, {to_back = true}},
      {"B1 anchor target, back first, front above", X(1), B, "B", -1, {anchor = true}},
      {"B2 anchor target, front first, front below", X(2), B, "F", 1, {anchor = true}},
      {"B3 real art: floor first, building above", X(3), B, "B", -1, {back = floor, front = bld, bs = 2, fs = 0.6}},
      {"B4 real art: building first, floor second, building below", X(4), B, "F", 1, {back = floor, front = bld, bs = 2, fs = 0.6}},
      {"B5 control: front on layer 1, back on layer 2", X(5), B, "B", 1, {back_layer = "2"}},
      {"B6 tick split: back now, front next tick, front above", X(6), B, "B", -1, {split = true}},
    }
    storage.order_late = {}
    for _, c in ipairs(cases) do
      local name, cx, cy, first, fy, o = c[1], c[2], c[3], c[4], c[5], c[6] or {}
      if o.anchor then o.anchor = s.create_entity{name = "fv-anchor", position = {cx, cy}, force = p.force} end
      if o.split then
        rendering.draw_sprite{sprite = "virtual-signal/signal-blue", surface = s, render_layer = "1", target = {cx, cy}, x_scale = 3, y_scale = 3}
        storage.order_late[#storage.order_late + 1] = {cx, cy + fy}
      else
        local f, b = order_pair(s, cx, cy, first, fy, o)
        if o.bring then f.bring_to_front() end
        if o.to_back then f.move_to_back() end
      end
      log("FVSHOT order case " .. name .. " at " .. cx .. "," .. cy .. " | creation predicts front " ..
        ((first == "B" and not o.to_back or o.bring) and "ON TOP" or "HIDDEN") .. ", y-sort predicts front " .. (fy > 0 and "ON TOP" or "HIDDEN"))
    end
    -- row C: layer-1 red markers straddling the strip's bottom edge (y 27), plain and brought to front; layer 2 control
    local c1 = rendering.draw_sprite{sprite = "virtual-signal/signal-red", surface = s, render_layer = "1", target = {X(1), 27.5}, x_scale = 1.5, y_scale = 1.5}
    local c2 = rendering.draw_sprite{sprite = "virtual-signal/signal-red", surface = s, render_layer = "1", target = {X(2), 27.5}, x_scale = 1.5, y_scale = 1.5}
    c2.bring_to_front()
    rendering.draw_sprite{sprite = "virtual-signal/signal-green", surface = s, render_layer = "2", target = {X(3), 27.5}, x_scale = 1.5, y_scale = 1.5}
    log("FVSHOT order row C at y 27.5: x " .. X(1) .. " layer 1, x " .. X(2) .. " layer 1 + bring_to_front, x " .. X(3) .. " layer 2 (green)")
  elseif t == 6 then
    for _, pos in ipairs(storage.order_late) do
      rendering.draw_sprite{sprite = "virtual-signal/signal-red", surface = s, render_layer = "1", target = pos, x_scale = 1.2, y_scale = 1.2}
    end
  elseif t == 40 then
    shot_z("fv-shot-order-1-markers.png", {ORDER_X + 2.5 * ORDER_SP, ORDER_Y + 0.5 * ORDER_SP - 4}, 1.4)
  elseif t == 5 + SETTLE then
    local st = remote.call("fleet-view", "stats")
    local list = {}
    for idx, sh in pairs(st.views[p.index].ships) do list[#list + 1] = {idx = idx, a = sh.anchor} end
    table.sort(list, function(a, b) return a.idx < b.idx end)
    for i = 1, math.min(3, #list) do
      log("FVSHOT order ship " .. list[i].idx .. " anchor " .. serpent.line(list[i].a))
      shot_z("fv-shot-order-2-ship" .. list[i].idx .. ".png", list[i].a, 4)
    end
    shot_z("fv-shot-order-3-markers-later.png", {ORDER_X + 2.5 * ORDER_SP, ORDER_Y + 0.5 * ORDER_SP - 4}, 1.4)
    log("FVSHOT order done")
  end
end
-- order2 mode (2026-11-15, follow-up of order mode, which found layer 1 sorted by y, creation order and
-- bring_to_front ignored): (a) markers on layers 0 (green) / 1 (red) / 2 (blue) at depths below a laid strip's bottom
-- edge (y 27): which sit under the hanging underside art? (b) is the same y-sort used on layers 0, 2, 10, arrow?
-- (c) sort key = sprite centre or sprite bottom?
local function order2_step(t, p)
  local s = game.surfaces["platform-2"]
  local function spr(name, layer, pos, xs, ys)
    return rendering.draw_sprite{sprite = "virtual-signal/" .. name, surface = s, render_layer = layer, target = pos,
      x_scale = xs or 1, y_scale = ys or xs or 1}
  end
  if t == 5 then
    p.teleport({0, 0}, s)
    local tiles = {}
    for x = 52, 104 do for y = 22, 26 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    s.set_tiles(tiles)
    -- (a) depth columns
    for i, d in ipairs{0.5, 1.5, 2.5, 4, 6, 8} do
      local x = 56 + 8 * (i - 1)
      spr("signal-green", "0", {x - 2, 27 + d}, 0.9)
      spr("signal-red", "1", {x, 27 + d}, 0.9)
      spr("signal-blue", "2", {x + 2, 27 + d}, 0.9)
      log("FVSHOT order2 depth " .. d .. " column x " .. x .. " (green 0 / red 1 / blue 2)")
    end
    -- (b) per layer: back (blue, big) first, front (red, small) ABOVE its centre: y-sort = red hidden, creation = red on top;
    -- and front first, front BELOW: y-sort = red on top, creation = red hidden
    for i, L in ipairs{"0", "1", "2", "10", "arrow"} do
      local x = 58 + 9 * (i - 1)
      spr("signal-blue", L, {x, 44}, 3); spr("signal-red", L, {x, 43}, 1.2)
      spr("signal-red", L, {x, 51}, 1.2); spr("signal-blue", L, {x, 50}, 3)
      log("FVSHOT order2 layer " .. L .. " x " .. x .. ": y 44 back-first/front-above, y 50 front-first/front-below")
    end
    -- (c) tall green (y_scale 4, centre 57, bottom 59) vs small red (centre 58, bottom 58.5): centre-sort = red on top,
    -- bottom-sort = green on top. Both orders of creation.
    spr("signal-green", "1", {60, 57}, 1.5, 4); spr("signal-red", "1", {60, 58}, 1)
    spr("signal-red", "1", {66, 58}, 1); spr("signal-green", "1", {66, 57}, 1.5, 4)
    log("FVSHOT order2 key test x 60 (tall first) / x 66 (small first): centre-sort = red on top, bottom-sort = green on top")
  elseif t == 40 then
    shot_z("fv-shot-order2-1-depth.png", {76, 30}, 1.6)
    shot_z("fv-shot-order2-2-layers.png", {78, 50}, 1.1)
    log("FVSHOT order done")
  end
end
-- order3 mode (2026-11-15): can a sprite SORT at one y and be DRAWN at another? Two levers: a prototype `shift`
-- (data.lua fvt-red-s*) and `oriented_offset` (needs orientation_target; Visible Planets uses it for its parallax).
-- U: red pictures 1.5 / 3 tiles below a strip's bottom edge (y 27), key 10 tiles higher (above the edge row):
--    plain red = over the underside (known); key moved up = under it if the key is the target.
-- K: big blue back at y 44, red PICTURE at 45 (lower = on top by picture) but TARGET at 38 (hidden by target).
-- R: where does the picture land when the sprite also has orientation 0.25 (belts etc. are rotated)?
-- C: culling: picture on screen, target 10 / 40 tiles off screen (zoom 2 shot).
-- VP (only with FV_VP=1): layer-0 reds above / below the planet's target (y 20), and one with the key moved.
local function order3_step(t, p)
  local s = game.surfaces["platform-2"]
  local NORTH = function(x) return {x, -99999} end
  local function red(target, o)
    o = o or {}
    local a = {sprite = o.sprite or "virtual-signal/signal-red", surface = s, render_layer = o.layer or "1", target = target,
      x_scale = o.sc or 1, y_scale = o.sc or 1, orientation = o.ori}
    if o.off then a.orientation_target = o.otarget or NORTH(target[1] or 0); a.oriented_offset = o.off; a.use_target_orientation = o.use end
    return rendering.draw_sprite(a)
  end
  local function mark(pos, name, layer, sc)
    rendering.draw_sprite{sprite = "virtual-signal/" .. (name or "signal-green"), surface = s, render_layer = layer or "2",
      target = pos, x_scale = sc or 0.4, y_scale = sc or 0.4}
  end
  if t == 5 then
    p.teleport({0, 0}, s)
    local tiles = {}
    for x = 52, 84 do for y = 22, 26 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    s.set_tiles(tiles)
    -- U rows: depth 1.5 (y 28.5) at x 56/62/68/74, depth 3 (y 30) at x 59/65/71/77
    for _, r in ipairs{{1.5, 0}, {3, 3}} do
      local y, dx = 27 + r[1], r[2]
      red({56 + dx, y})                                                     -- U1 plain
      red({62 + dx, y - 10}, {sprite = "fvt-red-s10"})                      -- U2 prototype shift
      red({68 + dx, y - 10}, {off = {0, 10}})                               -- U3 oriented_offset, position target north
      local an = s.create_entity{name = "fv-anchor", position = {74 + dx, y - 10}, force = p.force}
      red({entity = an}, {off = {0, 10}, otarget = an, use = true})         -- U4 oriented_offset, anchor entity orientation
    end
    log("FVSHOT order3 U depth 1.5 x 56/62/68/74, depth 3 x 59/65/71/77: plain / shift s10 / oriented_offset pos / oriented_offset anchor")
    -- K row: blue back at (x, 44) scale 3, red picture at 45 with target 38
    for _, x in ipairs{58, 66, 74, 82, 90} do mark({x, 44}, "signal-blue", "1", 3) end
    red({58, 38}, {sprite = "fvt-red-s7"})                                  -- K1 shift
    red({66, 41.5}, {sprite = "fvt-red-s7", sc = 0.5})                      -- K2 shift at runtime scale 0.5: lands 45 if scaled, 48.5 if not
    red({74, 38}, {off = {0, 7}})                                           -- K3 oriented_offset, position target
    local an = s.create_entity{name = "fv-anchor", position = {82, 38}, force = p.force}
    red({entity = an}, {off = {0, 7}, otarget = an, use = true})            -- K4 oriented_offset, anchor entity
    local bld = helpers.is_valid_sprite_path("fv-e-assembling-machine-2") and "fv-e-assembling-machine-2" or "item/assembling-machine-2"
    rendering.draw_sprite{sprite = "fv-t2-0", surface = s, render_layer = "1", target = {98, 44}, x_scale = 2, y_scale = 2}
    red({98, 49}, {sprite = bld, sc = 0.6, off = {0, -6}})                  -- K5 real art: building picture at 43 (above floor centre), key 49
    log("FVSHOT order3 K x 58 shift / 66 shift x0.5 / 74 oriented pos / 82 oriented anchor / 98 real art (floor plain, building key below): red on top = sorted by TARGET? no: on top = by picture for 58-82; 98 building visible = key moved works")
    -- R row: orientation 0.25 plus a downward offset of 7; green dots at the candidate landing points
    red({60, 52}, {off = {0, 7}, ori = 0.25}); mark({60, 59}); mark({53, 52}); mark({67, 52})
    red({80, 52}, {sprite = "fvt-red-s7", ori = 0.25}); mark({80, 59}); mark({73, 52}); mark({87, 52})
    log("FVSHOT order3 R x 60 oriented_offset+ori 0.25, x 80 shift+ori 0.25: green dots at (x, 59) unrotated, (x-7, 52), (x+7, 52)")
    -- C: culling, pictures at y 60
    red({122, 60})
    red({126, 20}, {sprite = "fvt-red-s40"})
    red({130, 20}, {off = {0, 40}})
    red({134, 50}, {sprite = "fvt-red-s10"})
    red({138, 50}, {off = {0, 10}})
    log("FVSHOT order3 C at y 60: x 122 plain, 126 shift 40, 130 oriented 40, 134 shift 10, 138 oriented 10")
    if script.active_mods["visible-planets"] then
      red({-75, 10}, {layer = "0", sc = 2}); red({-75, 30}, {layer = "0", sc = 2})
      red({-65, 30}, {layer = "0", sc = 2, off = {0, -20}})                 -- picture at y 10, key 30
      log("FVSHOT order3 VP layer 0: (-75, 10) above planet target y 20, (-75, 30) below, (-65, 10 drawn / 30 key)")
    end
  elseif t == 40 then
    shot_z("fv-shot-order3-1-underside.png", {66.5, 28.5}, 2)
    shot_z("fv-shot-order3-2-key.png", {78, 44}, 1.2)
    shot_z("fv-shot-order3-3-rot.png", {70, 55}, 1.2)
    shot_z("fv-shot-order3-4-cull-near.png", {130, 60}, 2)
    shot_z("fv-shot-order3-5-cull-wide.png", {130, 42}, 0.5)
    if not script.active_mods["visible-planets"] then log("FVSHOT order done") end
  elseif t == 5 + SETTLE and script.active_mods["visible-planets"] then
    shot_z("fv-shot-order3-6-vp.png", {-70, 20}, 0.5)
    log("FVSHOT order done")
  end
end
-- order4 mode (2026-11-15): order2's key test could not tell CENTRE from TOP (both said red); order3's VP shot had a
-- layer-0 red ABOVE the planet's target drawn over the planet. (a) centre vs top: tall green (centre 57, top 55) vs
-- small red (centre 56.5, top 56): centre-sort = green on top, top-sort = red on top; both creation orders.
-- (b) with FV_VP=1: layer-0 (x -60) and layer-1 (x -52) reds every 10 tiles from y -30 to 50 over the planet.
local function order4_step(t, p)
  local s = game.surfaces["platform-2"]
  local function spr(name, layer, pos, xs, ys)
    return rendering.draw_sprite{sprite = "virtual-signal/" .. name, surface = s, render_layer = layer, target = pos,
      x_scale = xs, y_scale = ys or xs}
  end
  if t == 5 then
    p.teleport({0, 0}, s)
    spr("signal-green", "1", {60, 57}, 1.5, 4); spr("signal-red", "1", {60, 56.5}, 1)
    spr("signal-red", "1", {66, 56.5}, 1); spr("signal-green", "1", {66, 57}, 1.5, 4)
    -- same on layer 0 and 2
    spr("signal-green", "0", {72, 57}, 1.5, 4); spr("signal-red", "0", {72, 56.5}, 1)
    spr("signal-green", "2", {78, 57}, 1.5, 4); spr("signal-red", "2", {78, 56.5}, 1)
    log("FVSHOT order4 (a) x 60/66 layer 1 (tall first / small first), x 72 layer 0, x 78 layer 2: red on top = TOP-sort, green on top = CENTRE-sort")
    if script.active_mods["visible-planets"] then
      for y = -30, 50, 10 do spr("signal-red", "0", {-60, y}, 1.5); spr("signal-blue", "1", {-52, y}, 1.5) end
      for _, o in pairs(rendering.get_all_objects("visible-planets")) do
        if o.valid and o.type == "sprite" then log("FVSHOT order4 VP sprite layer " .. tostring(o.render_layer) .. " target " .. serpent.line(o.target.position) .. " scale " .. o.x_scale .. " oriented_offset " .. serpent.line(o.oriented_offset) .. " orientation " .. o.orientation) end
      end
    end
  elseif t == 40 then
    shot_z("fv-shot-order4-1-key.png", {69, 57}, 2)
    if not script.active_mods["visible-planets"] then log("FVSHOT order done") end
  elseif t == 5 + SETTLE and script.active_mods["visible-planets"] then
    for _, o in pairs(rendering.get_all_objects("visible-planets")) do
      if o.valid and o.type == "sprite" then log("FVSHOT order4 VP sprite layer " .. tostring(o.render_layer) .. " target " .. serpent.line(o.target.position) .. " scale " .. o.x_scale .. " oriented_offset " .. serpent.line(o.oriented_offset) .. " orientation " .. o.orientation) end
    end
    shot_z("fv-shot-order4-2-vp.png", {-56, 10}, 0.35)
    log("FVSHOT order done")
  end
end
-- under mode (0.4.10, portal report Qazerowl "Rendering on top of edges"): after the ships are drawn, lay a strip of
-- foundation whose bottom edge runs 2 tiles above ship 1's anchor, so the strip's hanging underside crosses the ship's
-- top. Close-ups: 0.4.9 draws the ship over the hanging art, 0.4.10 under it.
local function under_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local s = plat.surface
  if t == 5 then
    set("fleet-view-detail", true)
    remote.call("fleet-view", "set_seed", SEED)
    p.teleport({0, 0}, s)
    remote.call("fleet-view", "show", p.index)
  elseif t == 5 + SETTLE then
    local st = remote.call("fleet-view", "stats")
    local list = {}
    for idx, sh in pairs(st.views[p.index].ships) do list[#list + 1] = {idx = idx, a = sh.anchor} end
    table.sort(list, function(a, b) return a.a.y > b.a.y end)   -- the lowest ship (below the deck)
    local a = list[1].a
    storage.under = {x = a.x, y = a.y, idx = list[1].idx}
    local tiles = {}
    local ey = math.floor(a.y) - 2   -- strip rows end at ey - 1: bottom edge at y = ey
    for x = math.floor(a.x) - 14, math.floor(a.x) + 14 do for y = ey - 8, ey - 1 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    s.set_tiles(tiles)
    log("FVSHOT under ship " .. list[1].idx .. " anchor " .. serpent.line(a) .. " strip bottom edge y " .. ey)
  elseif t == 5 + SETTLE + 30 then
    local st = remote.call("fleet-view", "stats")
    local sh = st.views[p.index].ships[storage.under.idx]
    log("FVSHOT under ship anchor after tiles " .. serpent.line(sh and sh.anchor))
    local u = storage.under
    shot_z("fv-shot-under-1-close.png", {u.x, u.y - 1}, 3)
    shot_z("fv-shot-under-2-wide.png", {u.x, u.y}, 1.2)
    -- culling worst case: zoom 4, the ship's anchor 1.5 tiles below the TOP edge of the view (targets above the view)
    shot_z("fv-shot-under-3-topedge.png", {u.x, u.y + 540 / (32 * 4) - 1.5}, 4)
    log("FVSHOT order done")
  end
end
-- order5 mode (2026-11-15): why did 0.4.10's floor vanish? Floor pieces (fvt-sq-*, data.lua) drawn so the picture
-- lands on a row of green dots. Row A (y 60): runtime scale = 10 / shift (picture always 10 tiles below its target:
-- isolates the SHIFT SIZE). Row B (y 66): runtime scale 0.08 like the real floor (world distance = 0.08 x shift).
-- Columns per shift 20/100/150/200/280: s (simple, scale 1), h (simple, scale 0.5), l (layered). Green dot = where the
-- picture should be; a piece missing = not drawn. Last column: the mod's own fv-t2-0 the same way (row B only).
local function order5_step(t, p)
  local s = game.surfaces["platform-2"]
  if t == 5 then
    p.teleport({0, 0}, s)
    local x = 100
    for _, dy in ipairs{20, 100, 150, 200, 280} do
      for _, kind in ipairs{"s", "h", "l"} do
        local name = "fvt-sq-" .. kind .. dy
        local half = kind == "h" and 0.5 or 1
        for _, row in ipairs{{60, 10 / dy}, {66, 0.08}} do
          local y, r = row[1], row[2]
          local world = dy * r   -- picture distance below the target
          rendering.draw_sprite{sprite = name, surface = s, render_layer = "1", target = {x, y - world}, x_scale = r, y_scale = r}
          rendering.draw_sprite{sprite = "virtual-signal/signal-green", surface = s, render_layer = "2", target = {x, y + 1.2}, x_scale = 0.3, y_scale = 0.3}
        end
        log("FVSHOT order5 x " .. x .. " " .. name .. " (picture size A " .. string.format("%.2f", 4 * half * 10 / dy) .. " tiles, B " .. string.format("%.2f", 4 * half * 0.08) .. ")")
        x = x + 2
      end
      x = x + 1
    end
    local sh = helpers.is_valid_sprite_path("fv-t2-0") and "fv-t2-0"
    if sh then
      rendering.draw_sprite{sprite = sh, surface = s, render_layer = "1", target = {x, 66 - 280 * 0.08}, x_scale = 0.08, y_scale = 0.08}
      rendering.draw_sprite{sprite = "virtual-signal/signal-red", surface = s, render_layer = "2", target = {x, 67.2}, x_scale = 0.3, y_scale = 0.3}
      log("FVSHOT order5 x " .. x .. " fv-t2-0 (the mod's floor piece, row B, red dot)")
    end
  elseif t == 40 then
    shot_z("fv-shot-order5-1.png", {118, 63}, 1.6)
    log("FVSHOT order done")
  end
end
-- order6 mode (2026-11-15): 0.4.10 v2 floor drew in a zoom-1.2 shot but partly vanished at zoom 3 (culling?). Pictures
-- on one row (y 80, green dots under them), each target `world` tiles above its picture, shot at zooms 0.5..6.
-- Columns: floor fv-t2-0 (shift 140) at world 8 / 16 / 24 / 32, building fv-e-assembling-machine-2 (shift 100) at the
-- same, test red fvt-red-s40 at 24 / 40.
local ORDER6_ZOOMS = {0.5, 1, 2, 3, 4, 6}
local function order6_step(t, p)
  local s = game.surfaces["platform-2"]
  if t == 5 then
    p.teleport({0, 0}, s)
    local x = 100
    local function put(sprite, shift, world)
      local r = world / shift
      rendering.draw_sprite{sprite = sprite, surface = s, render_layer = "1", target = {x, 80 - world}, x_scale = r, y_scale = r}
      rendering.draw_sprite{sprite = "virtual-signal/signal-green", surface = s, render_layer = "2", target = {x, 80.8}, x_scale = 0.2, y_scale = 0.2}
      log("FVSHOT order6 x " .. x .. " " .. sprite .. " world " .. world .. " runtime scale " .. string.format("%.3f", r))
      x = x + 1.5
    end
    for _, w in ipairs{8, 16, 24, 32} do put("fv-t2-0", 140, w) end
    x = x + 1
    for _, w in ipairs{8, 16, 24, 32} do put("fv-e-assembling-machine-2", 100, w) end
    x = x + 1
    put("fvt-red-s40", 40, 24); put("fvt-red-s40", 40, 40)
  elseif t == 40 then
    for _, z in ipairs(ORDER6_ZOOMS) do shot_z("fv-shot-order6-z" .. z .. ".png", {106.5, 80}, z) end
    log("FVSHOT order done")
  end
end
-- order7 mode (2026-11-15): order6 showed simple sprites (floor, red) culled when zoomed in while layered entity sprites
-- (buildings) drew at every zoom. Same floor picture with shift 100 as simple scale 1 ("s"), simple scale 0.5 ("h"),
-- ONE-layer layered ("l"), at world 8 / 16 / 24 / 32, plus the building; zooms 2 / 3 / 4 / 6, camera on each group.
local function order7_step(t, p)
  local s = game.surfaces["platform-2"]
  if t == 5 then
    p.teleport({0, 0}, s)
    local x = 100
    for _, sp in ipairs{"fvt-sq-s100", "fvt-sq-h100", "fvt-sq-l100", "fv-e-assembling-machine-2"} do
      for _, w in ipairs{8, 16, 24, 32} do
        local r = w / 100
        rendering.draw_sprite{sprite = sp, surface = s, render_layer = "1", target = {x, 80 - w}, x_scale = r, y_scale = r}
        rendering.draw_sprite{sprite = "virtual-signal/signal-green", surface = s, render_layer = "2", target = {x, 82}, x_scale = 0.2, y_scale = 0.2}
        x = x + 2.5
      end
      log("FVSHOT order7 " .. sp .. " x " .. (x - 10) .. ".." .. (x - 2.5) .. " world 8/16/24/32")
      x = x + 2
    end
  elseif t == 40 then
    for _, z in ipairs{2, 3, 4, 6} do shot_z("fv-shot-order7-z" .. z .. ".png", {118.5, 80}, z) end
    log("FVSHOT order done")
  end
end
-- order8 mode (2026-11-15): pictures on one row (y 80) at runtime scale 0.17, the camera put so the row sits 0.5 tiles
-- below the TOP edge of the view (the worst case: the target is shift x scale above, outside the view).
-- Columns: fvt-f64-s66 (64 px simple, shift 66: predicted culled), fvt-f64-l66 (same, one layer: culled),
-- fvt-f64-p66 (+ 256 px transparent pad layer: visible if the pad widens the margin), this build's fv-t2-0 (128 px,
-- shift 140: culled) and fv-e-assembling-machine-2 (big, shift 100: visible).
local function order8_step(t, p)
  local s = game.surfaces["platform-2"]
  if t == 5 then
    p.teleport({0, 0}, s)
    local x = 100
    for _, sp in ipairs{"fvt-f64-s66", "fvt-f64-l66", "fvt-f64-p66", "fv-t2-0", "fv-e-assembling-machine-2", "fvt-f64-c2", "fvt-f64-c1", "fvt-f64-c2big"} do
      local shift = (sp == "fv-t2-0") and 140 or (sp:find("^fv%-e") and 100) or 66
      local r = 0.17
      rendering.draw_sprite{sprite = sp, surface = s, render_layer = "1", target = {x, 80 - shift * r}, x_scale = r, y_scale = r}
      rendering.draw_sprite{sprite = "virtual-signal/signal-green", surface = s, render_layer = "2", target = {x, 81}, x_scale = 0.15, y_scale = 0.15}
      log("FVSHOT order8 x " .. x .. " " .. sp .. " shift " .. shift .. " target " .. string.format("%.1f", shift * r) .. " above")
      x = x + 1.5
    end
  elseif t == 40 then
    for _, z in ipairs{1, 2, 3, 4, 6} do
      local half = 540 / (32 * z)
      shot_z("fv-shot-order8-z" .. z .. ".png", {105, 80 + half - 0.5}, z)
    end
    log("FVSHOT order done")
  end
end
-- planet mode (2026-11-16, portal versuffer: moons ~1000 km out, the planet leaves much faster than the ships). The
-- viewer's platform-2 flies off nauvis at a HELD speed on two routes: A = nauvis-fvt-moon (1000 km, data.lua), then
-- B = nauvis-vulcanus (15000 km). Camera fixed on the deck centre, zoom PL_ZOOM; one frame each time the km flown
-- passes the next multiple of the route's step: fv-shot-planet-<A|B>-NNN.png + "FVSHOT planet <route> NNN km <km>".
-- tools/planet-edge.py reads the planet's top edge per frame; same edge at the same km on both routes = the backdrop
-- follows absolute km (Fleet View's PLANET_KM model), same edge at the same FRACTION = it follows trip fraction.
local PL_ZOOM, PL_SPEED = 0.25, 1          -- km/tick held while under way
local PL_ROUTES = {
  {name = "A", dest = "fvt-moon", step = 5, stop = 1000},
  {name = "B", dest = "vulcanus", step = 20, stop = 3000},
  -- arrivals: start `start` of the way out on `conn`, fly to nauvis, a frame each time the remaining km drops a step
  {name = "C", dest = "nauvis", conn = "nauvis-fvt-moon", start = 0.2, step = 2},
  {name = "D", dest = "nauvis", conn = "nauvis-vulcanus", start = 0.2, step = 20},
}
local function planet_km(pl)
  local c = pl.space_connection
  if not c then return nil end
  return c.from.name == "nauvis" and pl.distance * c.length or (1 - pl.distance) * c.length, c.length
end
function planet_step(t, p)
  local pl = game.surfaces["platform-2"].platform
  local S = storage.planet
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(pl.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2}
    for _, loc in ipairs{"fvt-moon", "vulcanus"} do pcall(function() pl.force.unlock_space_location(loc) end) end
    pl.schedule = nil
    if pl.space_location == nil or pl.space_location.name ~= "nauvis" then pl.space_location = "nauvis" end
    p.teleport({storage.deck.cx, storage.deck.cy}, pl.surface)
    remote.call("fleet-view", "show", p.index)
    storage.planet = {route = 0, wait = t + SETTLE}
    log("FVSHOT planet deck " .. serpent.line(storage.deck) .. " at " .. tostring(pl.space_location and pl.space_location.name))
    return
  end
  if not S then return end
  if S.wait then
    if t < S.wait then return end
    S.wait = nil
    S.route = S.route + 1
    local R = PL_ROUTES[S.route]
    if not R then log("FVSHOT planet done"); S.finished = true; return end
    S.next_km, S.n = 0, 0
    -- frame 0: parked, before the schedule starts
    S.n = S.n + 1
    game.take_screenshot{player = p, surface = pl.surface, position = {storage.deck.cx, storage.deck.cy}, resolution = {W, H},
      zoom = PL_ZOOM, path = string.format("fv-shot-planet-%s-%03d.png", R.name, 0), show_gui = false,
      show_entity_info = false, force_render = true, daytime = 0}
    log(string.format("FVSHOT planet %s %03d km parked tick %d", R.name, 0, game.tick))
    S.next_km = R.step
    if R.conn then
      pl.space_connection = R.conn
      pl.distance = R.start
      S.next_km = prototypes.space_connection[R.conn].length * R.start - R.step
    end
    pl.schedule = {current = 1, records = {{station = R.dest, wait_conditions = {}}}}
    pl.paused = false
    return
  end
  if S.finished then return end
  local R = PL_ROUTES[S.route]
  local km, len = planet_km(pl)
  if km then
    if not S.len_logged then log("FVSHOT planet " .. R.name .. " connection " .. pl.space_connection.name .. " length " .. len); S.len_logged = true end
    if (R.conn and km <= S.next_km) or (not R.conn and km >= S.next_km) then
      game.take_screenshot{player = p, surface = pl.surface, position = {storage.deck.cx, storage.deck.cy}, resolution = {W, H},
        zoom = PL_ZOOM, path = string.format("fv-shot-planet-%s-%03d.png", R.name, S.n), show_gui = false,
        show_entity_info = false, force_render = true, daytime = 0}
      log(string.format("FVSHOT planet %s %03d km %.2f frac %.5f tick %d speed %.3f", R.name, S.n, km, km / len, game.tick, pl.speed))
      S.n = S.n + 1
      if R.conn then
        while S.next_km >= km do S.next_km = S.next_km - R.step end
      else
        while S.next_km <= km do S.next_km = S.next_km + R.step end
      end
    end
    pl.speed = PL_SPEED
  end
  if (km and R.stop and km >= R.stop) or (not km and S.n > 1 and pl.space_location) then
    if R.conn then
      game.take_screenshot{player = p, surface = pl.surface, position = {storage.deck.cx, storage.deck.cy}, resolution = {W, H},
        zoom = PL_ZOOM, path = string.format("fv-shot-planet-%s-%03d.png", R.name, S.n), show_gui = false,
        show_entity_info = false, force_render = true, daytime = 0}
      log(string.format("FVSHOT planet %s %03d km 0.00 frac 0.00000 tick %d arrived", R.name, S.n, game.tick))
    end
    pl.schedule = nil
    pl.space_location = "nauvis"
    S.len_logged = nil
    S.wait = t + 120
  end
end
-- moon mode (2026-11-16): the clip for the owner. Viewer at the deck centre of platform-2 at nauvis with the other
-- platforms parked there drawn; platform-2 leaves for fvt-moon (1000 km, data.lua) at a held MOON_SPEED km/tick;
-- one 1280x720 frame every MOON_EVERY ticks for MOON_TICKS: fv-shot-moon-NNN.png. Run once per build to compare.
-- moonlong = the same departure on nauvis-vulcanus (15000 km): must match the build before the moon fix.
local MOON_SPEED, MOON_EVERY, MOON_TICKS, MOON_ZOOM = 1.7, 2, 480, 0.2
-- moonarrive / moonarrivelong: the viewer starts ARR_START of the way out on the 1000 / 15000 km route and flies IN to
-- nauvis, where the other platforms are parked (the approach: their ships come in with the planet).
local MOON_DEST = mode == "moonlong" and "vulcanus" or "fvt-moon"
if mode == "moonlong" then MOON_TICKS = 600 end
local ARR = ({moonarrive = {conn = "nauvis-fvt-moon", start = 0.3, ticks = 420},
  moonarrivelong = {conn = "nauvis-vulcanus", start = 0.2, ticks = 2400, every = 6}})[mode]
if ARR then MOON_DEST, MOON_TICKS, MOON_EVERY = "nauvis", ARR.ticks, ARR.every or MOON_EVERY end
function moon_step(t, p)
  local pl = game.surfaces["platform-2"].platform
  if t == 5 then
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, tl in pairs(pl.surface.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      minx = math.min(minx, tl.position.x); maxx = math.max(maxx, tl.position.x)
      miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    storage.deck = {cx = (minx + maxx + 1) / 2, cy = (miny + maxy + 1) / 2}
    for _, loc in ipairs{"fvt-moon", "vulcanus"} do pcall(function() pl.force.unlock_space_location(loc) end) end
    pl.schedule = nil
    for _, s in pairs(game.surfaces) do
      if s.platform and s.platform.valid then s.platform.schedule = nil; s.platform.paused = true end
    end
    for _, n in ipairs{"platform-1", "platform-3"} do
      local o = game.surfaces[n] and game.surfaces[n].platform
      if o then o.space_location = "nauvis" end
    end
    pl.space_location = "nauvis"
    if ARR then
      pl.space_connection = ARR.conn
      pl.distance = ARR.start
      pl.schedule = {current = 1, records = {{station = "nauvis", wait_conditions = {}}}}
      pl.paused = true
    end
    remote.call("fleet-view", "set_seed", SEED)
    remote.call("fleet-view", "platforms_changed")
    p.teleport({storage.deck.cx, storage.deck.cy}, pl.surface)
    remote.call("fleet-view", "show", p.index)
  elseif t == 5 + SETTLE then
    storage.moon_t0 = t
    pl.schedule = {current = 1, records = {{station = MOON_DEST, wait_conditions = {}}}}
    pl.paused = false
  end
  local t0 = storage.moon_t0
  if not t0 then return end
  if not pl.space_location then pl.speed = MOON_SPEED elseif ARR and not storage.moon_arrived then
    storage.moon_arrived = true; pl.schedule = nil; log("FVSHOT moon arrived tick " .. game.tick) end
  local dt = t - t0
  if dt <= MOON_TICKS and dt % MOON_EVERY == 0 then
    local n = dt / MOON_EVERY
    game.take_screenshot{player = p, surface = pl.surface, position = {storage.deck.cx, storage.deck.cy}, resolution = {1280, 720},
      zoom = MOON_ZOOM, path = string.format("fv-shot-moon-%03d.png", n), show_gui = false, show_entity_info = false,
      force_render = true, daytime = 0}
    local c = pl.space_connection
    local s = remote.call("fleet-view", "stats")
    local v = s.views[p.index]
    local cnt = 0
    if v then for _ in pairs(v.ships) do cnt = cnt + 1 end end
    log(string.format("FVSHOT moon %03d tick %d km %s ships %d", n, game.tick, c and string.format("%.1f", pl.distance * c.length) or "-", cnt))
  end
  if dt == MOON_TICKS + 1 then log("FVSHOT moon done") end
end
-- subpx mode (2026-11-16, 0.5.0 float research): does the renderer draw positions between whole screen pixels?
-- Three test pictures in empty space right of platform-2's deck, each moved +1/256 tile in x per tick (the engine's
-- position grain = 1/8 px at zoom 1, 1/4 px at zoom 2) for SUB_TICKS ticks:
--   A  floor piece attached to an fv-anchor entity that is teleported (how Fleet View moves a ship)
--   B  floor piece with a plain position target that is rewritten
--   C  a 5x5 block of floor pieces at scale 0.16 on one teleported anchor (a tiny ship floor)
-- One 640x360 frame per tick at zoom 1 and zoom 2, camera fixed: fv-shot-subpx-z<1|2>-NNN.png. Snapping = the crop
-- around a picture is unchanged 7 of 8 ticks (zoom 1); sub-pixel drawing = it changes every tick.
local SUB_TICKS = 64
function subpx_step(t, p)
  local plat = game.surfaces["platform-2"].platform
  local s = plat.surface
  if t == 5 then
    local maxx, miny, maxy = -1e9, 1e9, -1e9
    for _, tl in pairs(s.find_tiles_filtered{area = {{-300, -300}, {300, 300}}, name = "space-platform-foundation"}) do
      maxx = math.max(maxx, tl.position.x); miny = math.min(miny, tl.position.y); maxy = math.max(maxy, tl.position.y)
    end
    local cx, cy = math.floor(maxx) + 30, math.floor((miny + maxy) / 2)
    storage.sub = {cam = {cx, cy}}
    local S = storage.sub
    p.teleport({cx - 28, cy}, s)
    S.a = s.create_entity{name = "fv-anchor", position = {cx - 2, cy - 1.5}, force = p.force}
    rendering.draw_sprite{sprite = "fvt-sub", surface = s, target = {entity = S.a, offset = {0, 0}}}
    S.b = rendering.draw_sprite{sprite = "fvt-sub", surface = s, target = {cx - 2, cy + 1.5}}
    S.c = s.create_entity{name = "fv-anchor", position = {cx + 3, cy - 1.5}, force = p.force}
    for i = 0, 4 do for j = 0, 4 do
      rendering.draw_sprite{sprite = "fvt-sub", surface = s, x_scale = 0.16, y_scale = 0.16,
        target = {entity = S.c, offset = {(i - 2) * 0.32, (j - 2) * 0.32}}}
    end end
    log("FVSHOT subpx cam " .. serpent.line(S.cam) .. " a " .. serpent.line(S.a.position))
    return
  end
  local S = storage.sub
  if not S then return end
  local n = t - 60
  if n < 0 or n > SUB_TICKS then return end
  local d = n / 256
  S.a.teleport({S.cam[1] - 2 + d, S.cam[2] - 1.5})
  S.b.target = {S.cam[1] - 2 + d, S.cam[2] + 1.5}
  S.c.teleport({S.cam[1] + 3 + d, S.cam[2] - 1.5})
  for _, z in ipairs{1, 2} do
    game.take_screenshot{player = p, surface = s, position = S.cam, resolution = {640, 360}, zoom = z,
      path = string.format("fv-shot-subpx-z%d-%03d.png", z, n), show_gui = false, show_entity_info = false,
      force_render = true, daytime = 0}
  end
  log(string.format("FVSHOT subpx %03d a.x %.6f", n, S.a.position.x))
  if n == SUB_TICKS then log("FVSHOT subpx done") end
end
script.on_event(defines.events.on_tick, function(e)
  storage.t0 = storage.t0 or e.tick
  local t = e.tick - storage.t0
  local p = P()
  if not p then return end
  if mode == "planet" then return planet_step(t, p) end
  if mode:sub(1, 4) == "moon" then return moon_step(t, p) end
  if mode == "subpx" then return subpx_step(t, p) end
  if mode == "dirs" then return dirs_step(t, p) end
  if mode == "art" then return art_step(t, p) end
  if mode == "edges" then return edges_step(t, p) end
  if mode == "seams" then return seams_step(t, p) end
  if mode == "conn" then return conn_step(t, p) end
  if mode == "dump" then return dump_step(t, p) end
  if mode == "vp" then return vp_step(t, p) end
  if mode == "deck" then return deck_step(t, p) end
  if mode == "default" then return default_step(t, p) end
  if mode == "fixed" then return fixed_step(t, p) end
  if mode == "random" then return random_step(t, p) end
  if mode == "anim" then return anim_step(t, p) end
  if mode == "idle" then return idle_step(t, p) end
  if mode == "pan" then return pan_step(t, p) end
  if mode == "transfer" then return transfer_step(t, p) end
  if mode == "cross" then return cross_step(t, p) end
  if mode == "order" then return order_step(t, p) end
  if mode == "order2" then return order2_step(t, p) end
  if mode == "order3" then return order3_step(t, p) end
  if mode == "order4" then return order4_step(t, p) end
  if mode == "under" then return under_step(t, p) end
  if mode == "order5" then return order5_step(t, p) end
  if mode == "order6" then return order6_step(t, p) end
  if mode == "order7" then return order7_step(t, p) end
  if mode == "order8" then return order8_step(t, p) end
  if t == 10 then
    local plat = game.surfaces["platform-2"].platform
    local hub = plat.hub
    storage.home = {hub.position.x, hub.position.y + 4}
    p.teleport(storage.home, plat.surface)
    set("fleet-view-detail", true)
    remote.call("fleet-view", "show", p.index)
  elseif t == 10 + SETTLE then
    local s = remote.call("fleet-view", "stats")
    local sx, sy, n = storage.home[1], storage.home[2], 1
    for idx, sh in pairs(s.views[p.index].ships) do
      log("FVSHOT ship " .. idx .. " anchor " .. serpent.line(sh.anchor) .. " objects " .. sh.objects)
      sx = sx + sh.anchor.x; sy = sy + sh.anchor.y; n = n + 1
    end
    log("FVSHOT queued " .. s.queued .. " objects " .. s.objects .. " home " .. serpent.line(storage.home) .. " player " .. serpent.line(p.position))
    storage.cam = {sx / n, sy / n}
    shot("fv-shot-1-depth-detail.png", storage.cam)
  elseif t == 20 + SETTLE then
    set("fleet-view-detail", false)
  elseif t == 20 + 2 * SETTLE then
    log("FVSHOT queued " .. remote.call("fleet-view", "stats").queued)
    shot("fv-shot-2-detail-off.png", storage.cam)
  elseif t == 30 + 2 * SETTLE then
    set("fleet-view-detail", true)
  elseif t == 30 + 3 * SETTLE then
    p.teleport({storage.home[1] + 20, storage.home[2]})
  elseif t == 30 + 3 * SETTLE + 30 then
    log("FVSHOT queued " .. remote.call("fleet-view", "stats").queued .. " player " .. serpent.line(p.position))
    shot("fv-shot-3-moved-20.png", storage.cam)
  end
end)
