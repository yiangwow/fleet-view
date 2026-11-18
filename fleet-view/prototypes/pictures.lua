-- Pure helpers: pick a still picture (frame 0) out of an entity prototype's graphics.
local M = {}

local KEYS = {
  "picture", "pictures", "animation", "graphics_set.animation", "graphics_set.idle_animation",
  "integration_patch", "structure", "base_picture", "sheet", "sheets",
  "graphics_set.picture", "graphics_set.base_picture", "graphics_set.structure",
  "on_animation", "off_animation", "folded_animation", "platform_picture",
  "belt_animation_set.animation_set", "idle_animation", "working_animation", "base_animation", "base", "animations",
  "sprite", "sprites", "picture_safe", "chargable_graphics.picture", "idle", "horizontal_animation",
}

-- Child keys tried (in order) when a node is a table of named variants rather than a sprite.
local CHILDREN = { "north", "sheet", "sheets", "picture", "animation", "animation_set",
  "straight_vertical", "structure", "base", "idle" }

-- Last resort: scan graphics_set children, skipping these.
local SKIP = { "shadow", "glow", "light", "frozen", "reflection", "connector", "sound", "working_vis", "icon" }
local function skippable(k)
  for _, s in ipairs(SKIP) do if k:find(s, 1, true) then return true end end
  return false
end

-- What the current find_layers call collects: nil = the plain picture (no shadow/glow/light layers), "shadow" =
-- draw_as_shadow layers only, "glow" = draw_as_glow / draw_as_light layers only (0.4.7).
local want

local function kind_of(n)
  if n.draw_as_shadow then return "shadow" end
  if n.draw_as_glow or n.draw_as_light then return "glow" end
  return nil
end

local function leaf(n)
  if type(n) ~= "table" then return nil end
  if kind_of(n) ~= want then return nil end
  local filename, x, y = n.filename, n.x or 0, n.y or 0
  if type(filename) ~= "string" then
    if type(n.filenames) == "table" and type(n.filenames[1]) == "string" then
      filename = n.filenames[1]
    elseif type(n.stripes) == "table" and type(n.stripes[1]) == "table"
      and type(n.stripes[1].filename) == "string" then
      filename, x, y = n.stripes[1].filename, n.stripes[1].x or 0, n.stripes[1].y or 0
    else
      return nil
    end
  end
  -- size wins over width/height, as in the game: a stale width next to it is ignored there (Carna sets both)
  local w, h = n.width, n.height
  if type(n.size) == "number" then w, h = n.size, n.size end
  if type(n.size) == "table" then w, h = n.size[1] or n.size.width, n.size[2] or n.size.height end
  if type(w) ~= "number" or type(h) ~= "number" then return nil end
  return { filename = filename, width = w, height = h, x = x, y = y,
           scale = n.scale, shift = n.shift, tint = n.tint }
end

-- SpriteNWaySheet: `frames` pictures side by side (default 4: north, east, south, west), wrapping every `line_length`
-- (default = frames). frame_repeat = how many neighbouring directions share a frame. Returns the pixel offset (dx, dy) of
-- direction `dir` for a frame of w x h; (0, 0) for north. A 2-frame sheet (storage tank) wraps: idx mod frames.
local DIR_INDEX = { north = 0, east = 1, south = 2, west = 3 }
-- pixel offset of frame f (0-based) in a sheet of `frames` frames wrapping every `line_length` (default frames)
local function frame_offset(f, frames, line_length, w, h)
  local ll = line_length
  if not ll or ll < 1 then ll = frames end
  return (f % ll) * w, math.floor(f / ll) * h
end
M.frame_offset = frame_offset
local function sheet_offset(sh, dir, w, h)
  local di = DIR_INDEX[dir]
  if not di or di == 0 or type(sh) ~= "table" then return 0, 0 end
  local frames = sh.frames or 4
  if frames < 1 then frames = 1 end
  local rep = math.max(sh.frame_repeat or 1, 1)
  local ways = math.max(4, frames * rep)
  local f = math.floor(di * (ways / 4) / rep) % frames
  return frame_offset(f, frames, sh.line_length, w, h)
end
M.sheet_offset = sheet_offset

-- All non-shadow/glow/light leaves of one graphics node, frame 0 each. `dir` (north/east/south/west, default north)
-- picks that child of a table of named variants (falls back to north when the node has no such child).
local function resolve(n, depth, dir)
  if type(n) ~= "table" or depth > 6 then return {} end
  if type(n[1]) == "table" and n[1].render_layer ~= nil and type(n[1].layers) == "table" then
    -- array of render-layer groups (space-platform-hub): one layered sprite, groups in order
    local out = {}
    for _, g in ipairs(n) do
      for _, s in ipairs(resolve(g, depth + 1, dir)) do
        if s.rl == nil then s.rl = g.render_layer end   -- the group's render layer (hub/bay art is split by it)
        out[#out + 1] = s
      end
    end
    return out
  end
  if n[1] ~= nil then return resolve(n[1], depth + 1, dir) end  -- array = alternatives, take first
  if type(n.layers) == "table" then
    local out = {}
    for _, l in ipairs(n.layers) do
      for _, s in ipairs(resolve(l, depth + 1, dir)) do out[#out + 1] = s end
    end
    return out
  end
  local l = leaf(n)
  if l then return { l } end
  if dir ~= "north" and n[dir] then
    local r = resolve(n[dir], depth + 1, dir)
    if #r > 0 then return r end
  end
  for _, k in ipairs(CHILDREN) do
    if n[k] then
      local r = resolve(n[k], depth + 1, dir)
      if #r > 0 then
        if (k == "sheet" or k == "sheets") and dir ~= "north" then
          -- one sheet holding all directions: move to this direction's frame
          local sh = n[k][1] or n[k]
          for _, s in ipairs(r) do
            local dx, dy = sheet_offset(sh, dir, s.width, s.height)
            s.x, s.y = s.x + dx, s.y + dy
          end
        end
        return r
      end
    end
  end
  return {}
end
M.resolve = function(n, dir) return resolve(n, 0, dir or "north") end

-- Beacon-style graphics_set.animation_list: every entry drawn unless always_draw = false, in order (bottom plate, top, ...).
-- Then, in every module slot, the first picture marked has_empty_slot at variation 1 (frame 0 = the empty slot, 1.. =
-- tier-1 module look), placed after the entries below render layer "object" (modules sit under the top).
-- tiers[i] = frame of slot i (0 empty, 1..3 tier; nil tiers = frame 1 everywhere, the generic tier-1 look).
local function module_slots(gs, tiers)
  local vis = type(gs.module_visualisations) == "table" and gs.module_visualisations[1]
  local out = {}
  if type(vis) ~= "table" or type(vis.slots) ~= "table" then return out end
  for si, slot in ipairs(vis.slots) do
    local frame = tiers and tiers[si] or 1
    for _, el in ipairs(type(slot) == "table" and slot or {}) do
      local pic = type(el) == "table" and el.has_empty_slot and el.pictures
      if type(pic) == "table" then
        local l
        if pic.filename and (pic.variation_count or 0) >= 2 then
          l = leaf(pic)
          if l then
            local dx, dy = frame_offset(math.min(frame, pic.variation_count - 1), pic.variation_count, pic.line_length, l.width, l.height)
            l.x, l.y = l.x + dx, l.y + dy
          end
        elseif type(pic[2]) == "table" then
          l = resolve(pic[math.min(frame + 1, #pic)], 1, "north")[1]
        end
        if l then out[#out + 1] = l end
        break
      end
    end
  end
  return out
end

local function from_animation_list(gs, dir, tiers)
  local out, mods_done = {}, false
  local function add_mods()
    mods_done = true
    for _, l in ipairs(module_slots(gs, tiers)) do out[#out + 1] = l end
  end
  for _, el in ipairs(gs.animation_list) do
    if type(el) == "table" and el.always_draw ~= false and el.animation then
      if not mods_done and (el.render_layer or "object") == "object" then add_mods() end
      for _, l in ipairs(resolve(el.animation, 1, dir)) do out[#out + 1] = l end
    end
  end
  if #out > 0 and not mods_done then add_mods() end
  return out
end

local function get(p, path)
  local cur = p
  for part in path:gmatch("[^.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[part]
  end
  return cur
end

local function find_in(proto, dir, tiers)
  local gs0 = type(proto) == "table" and proto.graphics_set
  if type(gs0) == "table" and type(gs0.animation_list) == "table" then
    local r = from_animation_list(gs0, dir, tiers)
    if #r > 0 then return r end
  end
  for _, k in ipairs(KEYS) do
    local node = get(proto, k)
    if k == "sheet" or k == "sheets" then node = { [k] = node } end   -- so the direction frame logic applies
    local r = resolve(node, 0, dir)
    if #r > 0 then return r end
  end
  local gs = type(proto) == "table" and proto.graphics_set
  if type(gs) == "table" then
    -- one graphics set per direction (fusion generator): that direction's set first
    local own = gs[dir .. "_graphics_set"]
    if type(own) == "table" then
      local r = resolve(own, 0, dir)
      if #r > 0 then return r end
    end
    local names = {}
    for k, v in pairs(gs) do
      if type(k) == "string" and type(v) == "table" and not skippable(k) then names[#names + 1] = k end
    end
    table.sort(names)
    for _, k in ipairs(names) do
      local r = resolve(gs[k], 0, dir)
      if #r > 0 then return r end
    end
  end
  return {}
end

-- dir: "north" (default), "east", "south" or "west". The space art (platform_graphics_set, cargo bay) wins over the
-- planet art (graphics_set) when the prototype has both.
-- kind: nil = plain art, "shadow" or "glow" = only those layers (the `fv-e-<name>-sh` / `-gw` sprites).
-- tiers: optional per-slot module frames for beacon-style animation_list art (see module_slots).
function M.find_layers(proto, dir, kind, tiers)
  dir = dir or "north"
  want = kind
  local ok, res = pcall(function()
    local pgs = type(proto) == "table" and proto.platform_graphics_set
    if type(pgs) == "table" then
      local r = find_in({ graphics_set = pgs }, dir, tiers)
      if #r > 0 then return r end
    end
    return find_in(proto, dir, tiers)
  end)
  want = nil
  if not ok then error(res, 0) end
  return res
end

-- True when the layers of two directions are the same pictures (filename/x/y per layer).
function M.same_layers(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].filename ~= b[i].filename or a[i].x ~= b[i].x or a[i].y ~= b[i].y then return false end
  end
  return true
end

-- Leaves without the `rl` (render layer) note, safe to hand to data:extend. plain = also drop the draw_as_shadow /
-- draw_as_glow / draw_as_light flags: script render objects ignore them and draw such a sprite as an opaque box
-- (tested 0.4.7), without the flag the png's own alpha works.
function M.clean(layers, plain)
  local out = {}
  for i, l in ipairs(layers) do
    local c = {}
    for k, v in pairs(l) do
      if k ~= "rl" and not (plain and (k == "draw_as_shadow" or k == "draw_as_glow" or k == "draw_as_light")) then c[k] = v end
    end
    out[i] = c
  end
  return out
end

-- connections.lua calls leaf on single plain nodes
function M.leaf(n)
  want = nil
  return leaf(n)
end

function M.find_layer(proto)
  return M.find_layers(proto)[1]
end

return M
