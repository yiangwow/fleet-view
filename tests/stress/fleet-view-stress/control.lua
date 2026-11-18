-- Test only (not shipped): lots of big random ships to see Fleet View's cost on a real screen.
-- Portal report 2026-10-31 (WhosTigerCub): laggy near a planet with a ton of big ships. Same generator as the
-- STRESS mode of tests/bench/fleet-view-bench.
local GRID = {"assembling-machine-2", "assembling-machine-2", "chemical-plant", "steel-chest", "solar-panel"}

local function build_ship(force, name, loc, rng)
  local p = force.create_space_platform{name = name, planet = loc, starter_pack = "space-platform-starter-pack"}
  if not p then return nil end
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
      if math.abs(x) > 8 or math.abs(y) > 8 then
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
  p.paused = true
  return p, W, H, n
end

local function my_platform(cmd)
  local P = game.get_player(cmd.player_index)
  local pl = P and P.surface.platform
  if not pl then P.print("Stand on a space platform first."); return end
  return P, pl
end

commands.add_command("fv-stress", "[n=10] make n random big ships parked at your platform's planet (test only)", function(cmd)
  local P, pl = my_platform(cmd); if not pl then return end
  local loc = pl.space_location and pl.space_location.name
  if not loc then P.print("Your platform must be parked at a planet."); return end
  local n = tonumber(cmd.parameter or "") or 10
  storage.count = storage.count or 0
  local gen = game.create_random_generator(4242 + storage.count)
  for _ = 1, n do
    storage.count = storage.count + 1
    local p, W, H, ents = build_ship(P.force, "fv-stress-" .. storage.count, loc, function(a, b) return gen(a, b) end)
    if p then P.print("fv-stress-" .. storage.count .. ": " .. W .. "x" .. H .. ", " .. ents .. " entities") end
  end
  storage.planet = loc
  if remote.interfaces["fleet-view"] then remote.call("fleet-view", "platforms_changed") end
  P.print("Made " .. n .. " ships at " .. loc .. ". /fv-hop to fly away and back, /fv-stress-clear to delete them.")
end)

commands.add_command("fv-hop", "jump your platform away from the stress ships, or back to them (test only)", function(cmd)
  local P, pl = my_platform(cmd); if not pl then return end
  local here = pl.space_location and pl.space_location.name
  local home = storage.planet
  if not home then P.print("Run /fv-stress first."); return end
  local to = here == home and (home == "nauvis" and "vulcanus" or "nauvis") or home
  pl.paused = true -- the platform's own schedule would fly it off again
  pl.space_location = to
  if remote.interfaces["fleet-view"] then remote.call("fleet-view", "platforms_changed") end -- a script move raises no state event
  P.print("Platform moved to " .. to .. (to == home and " (ships arrive)" or " (ships leave)"))
end)

commands.add_command("fv-stress-clear", "delete every fv-stress platform (test only)", function(cmd)
  local P = game.get_player(cmd.player_index)
  local n = 0
  for _, p in pairs(P.force.platforms) do
    if p.valid and p.name:find("^fv%-stress%-") then p.destroy(0); n = n + 1 end
  end
  if remote.interfaces["fleet-view"] then remote.call("fleet-view", "platforms_changed") end
  P.print("Deleted " .. n .. " stress platforms.")
end)
