-- Benchmark driver (not shipped). Two modes, picked by bench.sh (sed rewrites the locals below):
-- STRESS = 0: at SHOW puts holyskib on platform-2, draws via the remote interface; from then on moves the viewer
--   +-1 tile every tick (ships are fixed: no anchor work).
-- STRESS = N > 0: "lots of big ships" (portal report, WhosTigerCub 2026-10-31: laggy near a planet full of big ships).
--   Tick 1 creates N random big platforms (seeded, same every run) parked at a planet other than platform-2's.
--   At SHOW the viewer stands on platform-2; at ARRIVE platform-2 is moved to that planet (every ship gathers, fills
--   and animates in at once); at LEAVE it is moved back (every ship animates out). FV-STRESS log lines mark the ticks.
local SHOW = 5  -- bench.sh rewrites this with SHOW_TICK=
local STATS = 600  -- bench.sh rewrites this with STATS_EVERY=
local STRESS = 0  -- bench.sh rewrites this with STRESS=
local HIST = false  -- bench.sh HIST=1: log what the drawn ships are made of (render objects by kind) just before LEAVE
local FLOAT = ""  -- bench.sh rewrites this with FLOAT= (smooth|balanced|light: sets fleet-view-smoothness at SHOW; off = fleet-view-float false; "" = the default)
local DEBUG = false  -- true: stats lines after the arrival (stats is expensive: off for timed runs)
local HOLD = 1300  -- bench.sh rewrites this with HOLD= (ticks after SHOW that the viewer leaves again; 2300+ = a long parked stretch)
local ARRIVE, LEAVE = SHOW + 100, SHOW + HOLD
local snap = script.active_mods["fleet-view"] and require("__fleet-view__.scripts.snapshot")
local geom = script.active_mods["fleet-view"] and require("__fleet-view__.scripts.geom")
local t0, moves = nil, 0

-- One random big ship: a W x H deck of foundation around the hub, filled with machines, belts and pipes.
local GRID = {"assembling-machine-2", "assembling-machine-2", "chemical-plant", "steel-chest", "solar-panel"}
local function build_ship(i, loc, rng)
  local force = game.forces.player
  local p = force.create_space_platform{name = "fv-stress-" .. i, planet = loc, starter_pack = "space-platform-starter-pack"}
  p.apply_starter_pack()
  local s = p.surface
  local W, H = rng(80, 160), rng(120, 240)
  local x0, y0 = -math.floor(W / 2), -math.floor(H / 2)
  local tiles = {}
  for x = x0, x0 + W - 1 do for y = y0, y0 + H - 1 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
  s.set_tiles(tiles)
  local n = 0
  for y = y0 + 1, y0 + H - 4, 4 do
    for x = x0 + 1, x0 + W - 4, 4 do
      if math.abs(x) > 8 or math.abs(y) > 8 then -- keep clear of the hub
        local kind = rng(1, 10)
        if kind <= 5 then
          if s.create_entity{name = GRID[kind], position = {x + 1.5, y + 1.5}, force = force} then n = n + 1 end
        elseif kind <= 8 then
          for dx = 0, 3 do if s.create_entity{name = "transport-belt", position = {x + dx + 0.5, y + 3.5}, direction = defines.direction.east, force = force} then n = n + 1 end end
        else
          for dy = 0, 3 do if s.create_entity{name = "pipe", position = {x + 3.5, y + dy + 0.5}, force = force} then n = n + 1 end end
        end
      end
    end
  end
  log("FV-STRESS ship " .. i .. " force=" .. force.name .. " loc=" .. tostring(p.space_location and p.space_location.name) .. " state=" .. tostring(p.state) .. " " .. W .. "x" .. H .. " tiles=" .. #tiles .. " entities=" .. n)
end

script.on_event(defines.events.on_tick, function(e)
  local FV = script.active_mods["fleet-view"] ~= nil
  t0 = t0 or e.tick
  local n = e.tick - t0
  local P = game.get_player("holyskib")
  if STRESS > 0 then
    local plat = game.surfaces["platform-2"].platform
    if n == 1 then
      local home = plat.space_location.name
      local there = home == "vulcanus" and "nauvis" or "vulcanus"
      storage.stress = {home = home, there = there}
      local gen = game.create_random_generator(4242)
      local function rng(a, b) return gen(a, b) end
      for i = 1, STRESS do build_ship(i, there, rng) end
      if DEBUG then
        local sp
        for _, pl in pairs(game.forces.player.platforms) do if pl.name == "fv-stress-4" then sp = pl.surface end end
        local function t(label, f) local pr = helpers.create_profiler(); local r = f(); pr.stop(); log({"", "FV-PROF ", label, " ", pr}); return r end
        local names = {}
        for name, proto in pairs(prototypes.tile) do if proto.is_foundation then names[#names + 1] = name end end
        local raw = t("find_tiles", function() return sp.find_tiles_filtered{name = names} end)
        local tiles = t("tile loop", function() local o = {}; for _, x in ipairs(raw) do o[#o + 1] = {x = math.floor(x.position.x), y = math.floor(x.position.y)} end; return o end)
        local es = t("find_entities", function() return sp.find_entities_filtered{force = game.forces.player} end)
        local ents = t("entity loop", function() local o = {}; for _, e in ipairs(es) do if e.valid and e.type ~= "character" then local p = e.prototype; o[#o+1] = {name = e.name, type = e.type, x = e.position.x, y = e.position.y, w = p.tile_width or 1, h = p.tile_height or 1, dir = e.direction} end end; return o end)
        t("merge_tiles", function() return geom.merge_tiles(tiles) end)
        local m = t("build_model", function() return snap.build_model(tiles, ents, 0) end)
        local fp = t("floor_pieces", function() return snap.floor_pieces(m.rects) end)
        log("FV-PROF counts tiles=" .. #tiles .. " ents=" .. #ents .. " rects=" .. #m.rects .. " floor_pieces=" .. #fp .. " model ents=" .. #m.ents)
      end
      log("FV-STRESS built " .. STRESS .. " ships at " .. there .. ", viewer home " .. home)
    elseif n == SHOW then
      P.teleport({plat.hub.position.x, plat.hub.position.y + 4}, plat.surface)
      if FV and FLOAT == "off" then remote.call("fleet-view", "set_setting", P.index, "fleet-view-float", false)
      elseif FV and FLOAT ~= "" then
        -- the setting was fleet-view-float-smoothness in 0.4.9-0.4.11 (ZIP= an older build)
        local name = settings.player_default["fleet-view-smoothness"] and "fleet-view-smoothness" or "fleet-view-float-smoothness"
        remote.call("fleet-view", "set_setting", P.index, name, FLOAT)
      end
      if FV then remote.call("fleet-view", "show", P.index) end
    elseif n == ARRIVE then
      log("FV-STRESS arrive tick=" .. e.tick .. " viewer force=" .. P.force.name)
      plat.paused = true -- the save's own schedule would fly it off again
      plat.space_location = storage.stress.there
      log("FV-STRESS now loc=" .. tostring(plat.space_location and plat.space_location.name) .. " state=" .. plat.state)
      if FV then remote.call("fleet-view", "platforms_changed") end
    elseif DEBUG and (n == ARRIVE + 1 or n == ARRIVE + 10 or n == ARRIVE + 300) then
      local s = remote.call("fleet-view", "stats")
      local v = s.views[P.index]
      local c = 0; if v then for _ in pairs(v.ships) do c = c + 1 end end
      log("FV-STRESS dbg n=" .. n .. " loc=" .. tostring(plat.space_location and plat.space_location.name) .. " surface=" .. P.surface.name .. " view=" .. tostring(v ~= nil) .. " ships=" .. c .. " objects=" .. s.objects .. " queued=" .. s.queued .. " animating=" .. s.animating .. " models=" .. s.models)
    elseif n == LEAVE - 1 and FV then
      local s = remote.call("fleet-view", "stats")
      log("FV-STRESS before-leave objects=" .. s.objects .. " animating=" .. s.animating .. " queued=" .. s.queued)
      if HIST then
        -- what the ships are made of: render objects by kind (sprite name with digits and direction suffixes folded)
        local h = {}
        for _, o in pairs(rendering.get_all_objects("fleet-view")) do
          local k = tostring(o.type)
          if o.type == "sprite" then
            local n = tostring(o.sprite)
            if n:find("^fv%-t%d") then k = "floor piece (fv-t*)"
            elseif n:find("^fv%-px") then k = "px rect (fv-px*)"
            elseif n:find("^fv%-dot") then k = "light dot"
            elseif n:find("^fv%-e%-") then
              local base = n:gsub("^fv%-e%-", ""):gsub("%-fvq%d$", ""):gsub("%-sh$", "(shadow)")
              base = base:gsub("%-north$", ""):gsub("%-east$", ""):gsub("%-south$", ""):gsub("%-west$", ""):gsub("%-r%d+$", ""):gsub("%-m%d+$", ""):gsub("%-in$", ""):gsub("%-out$", "")
              k = "entity: " .. base
            else k = "other: " .. n:gsub("%d+", "#") end
          end
          h[k] = (h[k] or 0) + 1
        end
        local list = {}
        for k, c in pairs(h) do list[#list + 1] = {k, c} end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = 1, math.min(#list, 40) do log(string.format("FV-HIST %7d %s", list[i][2], list[i][1])) end
      end
    elseif n == LEAVE then
      log("FV-STRESS leave tick=" .. e.tick)
      plat.space_location = storage.stress.home
      if FV then remote.call("fleet-view", "platforms_changed") end
    end
    return
  end
  if n == SHOW then
    local plat = game.surfaces["platform-2"].platform
    local hub = plat.hub
    storage.home = {hub.position.x, hub.position.y + 4}
    P.teleport(storage.home, plat.surface)
    remote.call("fleet-view", "show", P.index)
    if STATS > 0 then  -- stats is expensive (entity counts on every surface): keep it out of timed runs
      local s = remote.call("fleet-view", "stats")
      log("FV-BENCH start: anchors=" .. s.anchors .. " objects=" .. s.objects .. " surface=" .. P.surface.name)
    end
  elseif n > SHOW then
    local dx = (n % 2 == 0) and 1 or -1
    P.teleport({storage.home[1] + dx, storage.home[2]})
    moves = moves + 1
    if STATS > 0 and (n <= SHOW + 4 or n % STATS == 0) then
      local s = remote.call("fleet-view", "stats")
      local a = {}
      for _, sh in pairs(s.views[P.index].ships) do a[#a + 1] = sh.anchor.x .. "," .. sh.anchor.y end
      log("FV-BENCH t" .. n .. " player=" .. P.position.x .. "," .. P.position.y .. " anchors=[" .. table.concat(a, " ") .. "]")
    end
    if STATS > 0 and n % STATS == 0 then
      local s = remote.call("fleet-view", "stats")
      log("FV-BENCH tick " .. n .. ": moves=" .. moves .. " anchors=" .. s.anchors .. " objects=" .. s.objects
        .. " pos=" .. P.position.x .. "," .. P.position.y)
    end
  end
end)
