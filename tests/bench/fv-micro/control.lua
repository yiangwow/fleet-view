-- Micro benchmark driver (not shipped). Phases of 600 ticks on platform-2's surface, in empty space right of the deck:
-- create at +0, IDLE window +50..+200 (objects exist, nothing moves), MOVE window +200..+500 (every anchor moved
-- 1/256 tile per tick), destroy at +550. tools read the --benchmark-verbose rows by relative tick (FVM log lines).
local PHASES = {
  {name = "teleport 10 anchors x 10000", kind = "fvm-anchor", anchors = 10, per = 10000, move = "teleport"},
  {name = "teleport 10 anchors x 1000",  kind = "fvm-anchor", anchors = 10, per = 1000,  move = "teleport"},
  {name = "teleport 1 anchor x 100000",  kind = "fvm-anchor", anchors = 1,  per = 100000, move = "teleport"},
  {name = "teleport 10 anchors x 0",     kind = "fvm-anchor", anchors = 10, per = 0,     move = "teleport"},
  {name = "car speed 10 cars x 10000",   kind = "fvm-car",    anchors = 10, per = 10000, move = "speed"},
  {name = "car speed 10 cars x 0",       kind = "fvm-car",    anchors = 10, per = 0,     move = "speed"},
  {name = "car teleport 10 cars x 10000", kind = "fvm-car",   anchors = 10, per = 10000, move = "teleport"},
  {name = "car speed 0.1 x 0 (diag)",    kind = "fvm-car",    anchors = 10, per = 0,     move = "speed", v = 0.1},
  {name = "car speed 0.1 x 10000",       kind = "fvm-car",    anchors = 10, per = 10000, move = "speed", v = 0.1},
  {name = "char walk 10 x 10000",        kind = "fvm-char",   anchors = 10, per = 10000, move = "walk"},
  {name = "char walk 10 x 0",            kind = "fvm-char",   anchors = 10, per = 0,     move = "walk"},
  {name = "tp 10 x 10000 1-layer sprite", kind = "fvm-anchor", anchors = 10, per = 10000, move = "teleport", sprite = "fvm-1"},
  {name = "tp 10 x 10000 2-layer+shift",  kind = "fvm-anchor", anchors = 10, per = 10000, move = "teleport", sprite = "fvm-2"},
  {name = "tp 10 x 625 16-layer sprite",  kind = "fvm-anchor", anchors = 10, per = 625,   move = "teleport", sprite = "fvm-16"},
  {name = "tp 10 x 10000 16-layer",       kind = "fvm-anchor", anchors = 10, per = 10000, move = "teleport", sprite = "fvm-16"},
}
local ONLY = nil  -- micro.sh ONLY=<first phase> skips the earlier ones
local LEN = 600
local STEP = 1 / 256
script.on_event(defines.events.on_tick, function(e)
  storage.t0 = storage.t0 or e.tick
  local t = e.tick - storage.t0
  local k = math.floor((t - 10) / LEN) + 1 + ((ONLY or 1) - 1)
  local P = PHASES[k]
  if t < 10 then return end
  if not P then
    if not storage.done then storage.done = true; log("FVM done t " .. t) end
    return
  end
  local dt = (t - 10) % LEN
  local s = game.surfaces["platform-2"]
  if dt == 0 then
    storage.a = {}
    for i = 1, P.anchors do
      local a = s.create_entity{name = P.kind, position = {200 + i * 12, 0}, force = "player"}
      if not a then error("fv-micro: could not create " .. P.kind) end
      if P.kind == "fvm-car" then a.orientation = 0.25 end
      if P.kind == "fvm-char" then a.character_running_speed_modifier = STEP / 0.15 - 1 end
      storage.a[i] = a
      for j = 1, P.per do
        rendering.draw_sprite{sprite = P.sprite or "item/iron-plate", surface = s, x_scale = 0.16, y_scale = 0.16,
          target = {entity = a, offset = {(j % 100) * 0.1 - 5, math.floor(j / 100) % 100 * 0.1 - 5}}}
      end
    end
    log(string.format("FVM phase %d t %d create: %s", k, t, P.name))
  elseif dt == 200 then
    storage.x0 = storage.a[1].position.x
    log(string.format("FVM phase %d t %d move start x %.6f", k, t, storage.x0))
  elseif dt == 500 then
    log(string.format("FVM phase %d t %d move end x %.6f moved %.6f (want %.6f)", k, t, storage.a[1].position.x,
      storage.a[1].position.x - storage.x0, 300 * STEP))
  elseif dt == 550 then
    for _, a in ipairs(storage.a) do if a.valid then a.destroy() end end
    rendering.clear("fv-micro")
    storage.a = nil
  end
  if dt >= 200 and dt < 500 then
    if P.move == "teleport" then
      for _, a in ipairs(storage.a) do local p = a.position; a.teleport({p.x + STEP, p.y}) end
    elseif P.move == "walk" then
      for _, a in ipairs(storage.a) do a.walking_state = {walking = true, direction = defines.direction.east} end
    else
      for _, a in ipairs(storage.a) do a.speed = P.v or STEP end
    end
  end
end)
