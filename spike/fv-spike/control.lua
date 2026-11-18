local mode = require("mode")
local function tgt(ro) local t=ro.target; return serpent.line({type=t.type, entity_pos=t.entity and t.entity.position, offset=t.offset, position=t.position}) end
local function S() return game.surfaces["platform-2"] end

local function deck_extent(s)
  local maxx, minx, n = -1e9, 1e9, 0
  local names = {}
  for _, t in pairs(s.find_tiles_filtered{area={{-300,-300},{300,300}}}) do
    names[t.name] = (names[t.name] or 0) + 1
    if t.name == "space-platform-foundation" then
      n = n + 1
      if t.position.x > maxx then maxx = t.position.x end
      if t.position.x < minx then minx = t.position.x end
    end
  end
  log("FV tile names: " .. serpent.line(names))
  return minx, maxx, n
end

local function step2(tick)
  local s = S()
  if tick == 10 then
    local minx, maxx, n = deck_extent(s)
    log("FV deck x range " .. minx .. " .. " .. maxx .. " tiles " .. n)
    local pos = {maxx + 60, 0}
    storage.tile_at = s.get_tile(pos[1], pos[2]).name
    log("FV tile at anchor pos: " .. storage.tile_at)
    local ok, e = pcall(s.create_entity, {name="fv-anchor", position=pos, force="player"})
    log("FV create_entity ok=" .. tostring(ok) .. " result=" .. tostring(e) .. " valid=" .. tostring(ok and e and e.valid))
    if ok and e then
      storage.anchor = e; storage.t0 = tick
      storage.ro = rendering.draw_sprite{sprite="item.iron-plate", surface=s, target={entity=e, offset={3,0}}, render_layer="zero"}
      log("FV anchor pos " .. serpent.line(e.position) .. " ro.target.position " .. tgt(storage.ro))
    end
  elseif tick == 11 and storage.anchor then
    local e = storage.anchor
    log("FV before teleport anchor " .. serpent.line(e.position))
    local okt = e.teleport({e.position.x, e.position.y + 10})
    log("FV teleport returned " .. tostring(okt) .. " anchor now " .. serpent.line(e.position))
    log("FV same tick ro.target.position " .. tgt(storage.ro))
  elseif tick == 12 and storage.anchor then
    log("FV tick+1 ro.target.position " .. tgt(storage.ro) .. " anchor " .. serpent.line(storage.anchor.position))
  elseif tick == 611 and storage.anchor then
    log("FV after 600 ticks anchor valid=" .. tostring(storage.anchor.valid) .. " ro valid=" .. tostring(storage.ro.valid)
      .. (storage.anchor.valid and (" pos " .. serpent.line(storage.anchor.position) .. " ro.target.position " .. tgt(storage.ro)) or ""))
  end
end

-- bench: 6 anchors x 600 objects
local function bench_setup(retarget)
  local s = S()
  storage.anchors = {}; storage.objs = {}
  for a = 1, 6 do
    local e = s.create_entity{name="fv-anchor", position={500 + a*20, 0}, force="player"}
    storage.anchors[a] = e
    for i = 1, 600 do
      local off = {(i % 30) - 15, math.floor(i / 30) - 10}
      if retarget then
        storage.objs[#storage.objs+1] = {rendering.draw_sprite{sprite="item.iron-plate", surface=s, target={500 + a*20 + off[1], off[2]}, render_layer="zero", x_scale=0.5, y_scale=0.5}, off, 500 + a*20}
      else
        rendering.draw_sprite{sprite="item.iron-plate", surface=s, target={entity=e, offset=off}, render_layer="zero", x_scale=0.5, y_scale=0.5}
      end
    end
  end
  log("FV bench setup done, anchors=" .. #storage.anchors .. " retarget=" .. tostring(retarget) .. " objs=" .. #storage.objs)
end

local function shot_setup()
  local s = S()
  local minx, maxx = deck_extent(s)
  local sumy, cnt = 0, 0
  for _, t in pairs(s.find_tiles_filtered{area={{-300,-300},{300,300}}}) do
    if t.name == "space-platform-foundation" then sumy = sumy + t.position.y; cnt = cnt + 1 end
  end
  local cy = sumy / cnt
  storage.shot = {minx=minx, maxx=maxx, cy=cy}
  storage.ex = maxx + 1
  log("FV shot deck x " .. minx .. ".." .. maxx .. " cy " .. cy)
  local function sprite(name, x, y, layer)
    rendering.draw_sprite{sprite="virtual-signal/"..name, surface=s, target={x, cy+y}, x_scale=6, y_scale=6, render_layer=layer}
  end
  local function rect(rgb, x0, y0, x1, y1, layer)
    rendering.draw_rectangle{color={r=rgb[1],g=rgb[2],b=rgb[3],a=1}, filled=true, left_top={x0, cy+y0}, right_bottom={x1, cy+y1}, surface=s, render_layer=layer}
  end
  if mode == "layers" then
    -- sprites on 4 layers; left column over planet/space (x=-38), right column over deck (x=-12)
    for _, r in ipairs{{"signal-red","under-tiles",6},{"signal-green","zero",14},{"signal-blue","background-transitions",22},{"signal-yellow","decals",30}} do
      for _, x in ipairs{-38, -12} do sprite(r[1], x, r[3], r[2]) end
    end
  elseif mode == "rect" then
    -- row dy=6: over deck. rectangle (left, red) vs sprite (right, green), both render_layer "zero"
    rect({1,0,0}, -22, 3.5, -16.5, 9, "zero"); sprite("signal-green", -13.5, 6, "zero")
    -- row dy=20: over planet/space, same pair
    rect({1,0,0}, -42, 17.5, -36.5, 23, "zero"); sprite("signal-green", -32, 20, "zero")
  elseif mode == "follow" then
    local anc = s.create_entity{name="fv-anchor", position={storage.ex + 15, cy - 20}, force="player"}
    storage.anc = anc
    -- sprite on the chosen layer "zero", targeting the anchor with offset {3,0}
    storage.ro = rendering.draw_sprite{sprite="item.iron-plate", surface=s, target={entity=anc, offset={3,0}}, x_scale=8, y_scale=8, render_layer="zero"}
  end
end

local function shot(path, x, y, w, h, z)
  game.take_screenshot{surface=S(), position={x, y}, resolution={w,h}, zoom=z, path=path, show_gui=false, show_entity_info=false, force_render=true, daytime=0}
end

script.on_event(defines.events.on_tick, function(ev)
  storage.t_start = storage.t_start or ev.tick
  local t = ev.tick - storage.t_start
  if mode == "anchor" then step2(t)
  elseif mode == "benchA" or mode == "benchB" then
    if t == 5 then bench_setup(mode == "benchB") end
    if t > 5 then
      if mode == "benchA" then
        for _, e in pairs(storage.anchors) do e.teleport({e.position.x + ((t%2==0) and 1 or -1), e.position.y}) end
      else
        local d = (t % 2 == 0) and 1 or -1
        for _, o in pairs(storage.objs) do
          o[3] = o[3] + 0 -- keep base
          o[1].target = {o[3] + o[2][1] + d, o[2][2]}
        end
      end
    end
    if t == 605 then log("FV bench end") end
  elseif mode == "layers" or mode == "rect" or mode == "follow" then
    if t == 5 then shot_setup() end
    local sh = storage.shot
    if mode == "follow" then
      local fx, fy = (storage.ex or 0) + 10, (sh and sh.cy or 0) - 20
      if t == 120 then shot("fv-shot-follow-before.png", fx, fy, 1200, 800, 0.5) end
      if t == 122 then storage.anc.teleport({storage.ex + 15 + 20, sh.cy - 20 + 10}) end
      if t == 125 then shot("fv-shot-follow-after.png", fx, fy, 1200, 800, 0.5) end
    elseif t == 120 then
      shot("fv-shot-" .. mode .. ".png", -25, sh.cy + 14, 1600, 1000, 1)
    end
  end
end)
