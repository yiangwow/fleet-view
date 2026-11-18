local draw = require("scripts.draw")
local snapshot = require("scripts.snapshot")
local transfer = require("scripts.transfer")

script.on_init(draw.init)

local function on_platform_state() draw.on_platform_state(game.tick) end

local function on_configuration_changed()
  draw.init()
  draw.reset()
  draw.drop_models()
  draw.refresh_all()
end
script.on_configuration_changed(on_configuration_changed)

local function on_setting_changed(e)
  if not (e.player_index and e.setting:find("^fleet%-view%-")) then return end
  if e.setting == "fleet-view-zoom-transfer" then return end -- read at check time
  if e.setting == "fleet-view-parallax" then draw.set_parallax(e.player_index)
  elseif e.setting == "fleet-view-smoothness" then draw.set_float_smoothness(e.player_index)
  else draw.refresh(e.player_index) end
end

-- Per tick: draw queue while non-empty, and ships mid arrive/leave (180 ticks). Ships are fixed in space.
script.on_event(defines.events.on_tick, draw.on_tick)

-- Models are rebuilt only after something changed on their platform (build/mine/die events mark them dirty),
-- at most every snapshot.REBUILD_TICKS per platform; this once-a-minute check does nothing while none is dirty.
script.on_nth_tick(60, function(e) draw.service_dirty(e.tick) end)

local ENTITY_FILTER = {{filter = "type", type = "asteroid", invert = true},
  {filter = "ghost", invert = true, mode = "and"}}
local function entity_changed(e)
  local ent = e.entity
  if ent and ent.valid then draw.mark_dirty_surface(ent.surface) end
end
local ev = defines.events
for _, id in ipairs{ev.on_built_entity, ev.on_robot_built_entity, ev.on_space_platform_built_entity,
  ev.script_raised_built, ev.script_raised_revive, ev.on_player_mined_entity, ev.on_robot_mined_entity,
  ev.on_space_platform_mined_entity, ev.script_raised_destroy, ev.on_entity_died} do
  script.on_event(id, entity_changed, ENTITY_FILTER)
end
local function tiles_changed(e)
  if e.platform then draw.mark_dirty(e.platform); draw.tiles_changed(e.platform)
  elseif e.surface_index then
    local surface = game.get_surface(e.surface_index)
    draw.mark_dirty_surface(surface)
    if surface and surface.valid then draw.tiles_changed(surface.platform) end
  end
end
for _, id in ipairs{ev.on_player_built_tile, ev.on_player_mined_tile, ev.on_robot_built_tile, ev.on_robot_mined_tile,
  ev.on_space_platform_built_tile, ev.on_space_platform_mined_tile, ev.script_raised_set_tiles, ev.on_surface_cleared} do
  script.on_event(id, tiles_changed)
end

script.on_event(defines.events.on_player_changed_surface, function(e)
  draw.refresh(e.player_index)
end)

-- Zoom transfer: zoom into a parked ship to continue in remote view of that platform (scripts/transfer.lua).
script.on_nth_tick(transfer.PERIOD, function() transfer.run() end)
script.on_event(defines.events.on_player_joined_game, function(e) draw.refresh(e.player_index) end)
script.on_event(defines.events.on_player_left_game, function(e)
  draw.clear(e.player_index)
  storage.surfaces[e.player_index] = nil
  storage.where[e.player_index] = nil
end)
script.on_event(defines.events.on_space_platform_changed_state, on_platform_state)

script.on_event(defines.events.on_runtime_mod_setting_changed, on_setting_changed)

-- A platform being deleted: remove its pictures everywhere first, rebuild views afterwards.
script.on_event(defines.events.on_pre_surface_deleted, function(e)
  local s = game.get_surface(e.surface_index)
  if s and s.platform then draw.drop_platform(s.platform.index) end
end)
script.on_event(defines.events.on_surface_deleted, function() draw.refresh_all() end)

-- Test/diagnostic interface: only registered when a helper mod is loaded (active_mods is the same on every client).
local HELPERS = {"fleet-view-test", "fleet-view-bench", "fleet-view-shot", "fleet-view-stress"}
local helper_active = false
for _, name in ipairs(HELPERS) do
  if script.active_mods[name] then helper_active = true end
end
if helper_active then remote.add_interface("fleet-view", {
  show = function(player_index) draw.refresh(player_index) end,
  clear = function(player_index) draw.clear(player_index) end,
  -- Writes the mod's own per-user setting (the real settings path); the engine raises the event.
  set_setting = function(player_index, name, value)
    game.get_player(player_index).mod_settings[name] = {value = value}
  end,
  -- Runs the exact on_configuration_changed handler.
  configuration_changed = on_configuration_changed,
  flush = function() draw.flush() end,
  -- Test hook: run the zoom-transfer check now; returns how many players were switched.
  transfer_run = function() return transfer.run() end,
  set_seed = function(seed) draw.set_seed(seed) end,
  -- Test hooks: model rebuild throttle (ticks) and the gather counters.
  set_rebuild_ticks = function(n) storage.rebuild_ticks = n end,
  set_min_step = function(v) draw.set_min_step(v) end,
  set_no_idle = function(v) draw.set_no_idle(v) end,
  set_no_parallax = function(v) draw.set_no_parallax(v) end,
  reset_gather_stats = function() storage.gather_stat.max = 0; storage.gather_stat.total = 0; storage.gather_stat.rebuilds = 0 end,
  stats = function() return draw.stats() end,
  shape_stats = function() return draw.shape_stats() end,
  pipe_probe = function(i) return draw.pipe_probe(i) end,
  gather_probe = function(i) return draw.gather_probe(i) end,
  -- Runs the exact on_space_platform_changed_state handler (tests move platforms via space_location).
  platforms_changed = on_platform_state,
  -- Test hook: make storage look like 0.1.0's (views with depth/follow/slots, last_pos) before configuration_changed.
  simulate_old_storage = function()
    storage.last_pos = {}
    storage.layouts = nil; storage.bounds = nil
    for pi, view in pairs(storage.views) do
      view.depth = true; view.slots = 2
      storage.last_pos[pi] = {x = 0, y = 0}
      for _, ship in pairs(view.ships) do ship.follow = 0.85; ship.slot = 1 end
    end
  end,
}) end
