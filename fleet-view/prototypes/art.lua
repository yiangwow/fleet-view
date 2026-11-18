-- Data stage: sprites for the shape-dependent logistics art. One sprite per shape, all single `layers` sprites (the
-- runtime draws ONE render object per entity):
--   fv-e-<belt>-r<i>            curved belt, i = the DEFAULT 1-based belt_animation_set index (5..12, the curve rows)
--   fv-e-<underground>-in-<dir> / -out-<dir>   half belt + the structure frame, dir = north|east|south|west (flow direction)
--   fv-e-<pipe>-m<mask>         joined pipe, mask bits N 1, E 2, S 4, W 8 (0 = lone pipe)
-- Row / frame choices and the evidence for them: CLAUDE.md "Shape art" and the comments below.
local pictures = require("prototypes.pictures")
local M = {}

-- Defaults of TransportBeltAnimationSet(WithCorners) (prototype docs). The animation_set is a RotatedAnimation of 20
-- directions, one row of frame_count frames each: row = index - 1 (checked on the PNG: 1 east, 2 west, 3 north, 4 south).
M.BELT_DEFAULT = {
  east = 1, west = 2, north = 3, south = 4,
  east_to_north = 5, north_to_east = 6, west_to_north = 7, north_to_west = 8,
  south_to_east = 9, east_to_south = 10, south_to_west = 11, west_to_south = 12,
}
-- "<from>_to_<to>": belt enters from the <from> edge, leaves through the <to> edge (the art of rows 5..8 shows the
-- chevrons pointing out of the <to> edge; belt_shape probed in game: facing north, feeder from the west = "left").
local CURVES = { "east_to_north", "north_to_east", "west_to_north", "north_to_west",
  "south_to_east", "east_to_south", "south_to_west", "west_to_south" }

local function copy(l)
  local c = {}
  for k, v in pairs(l) do c[k] = v end
  return c
end

-- Layers of row `idx` (1-based) of a belt prototype's animation_set, frame 0.
local function belt_row(p, idx)
  local set = p.belt_animation_set
  local an = type(set) == "table" and set.animation_set
  if type(an) ~= "table" then return nil end
  local out = {}
  for _, raw in ipairs(an.layers or { an }) do
    local l = pictures.leaf(raw)
    if l then
      local fc = raw.frame_count or 1
      local ll = raw.line_length
      if not ll or ll < 1 then ll = fc end
      local rows = math.ceil(fc / ll)
      local line = (idx - 1) * rows
      -- Sheet split over several PNGs (`filenames` + `lines_per_file`, e.g. Factorio HD Age belts): the row sits in
      -- file floor(line / lpf) + 1 at line `line % lpf`. Reading on down file 1 crashed sprite loading (portal 2026-11-14).
      local lpf = raw.lines_per_file
      if type(raw.filenames) == "table" and type(lpf) == "number" and lpf >= 1 then
        local f = raw.filenames[math.floor(line / lpf) + 1]
        if type(f) ~= "string" then return nil end
        l.filename = f
        line = line % lpf
      end
      l.y = l.y + line * l.height
      out[#out + 1] = l
    end
  end
  if #out == 0 then return nil end
  return out
end
local function belt_index(p, key)
  local v = p.belt_animation_set[key .. "_index"]
  return type(v) == "number" and v or M.BELT_DEFAULT[key]
end

local DIRS = { "north", "east", "south", "west" }

-- Half of a belt frame: the half behind (kind "in": belt arrives at the hood) or in front of (kind "out") the tile
-- centre, cut out of the straight belt frame of the flow direction. The belt content is one tile = 32 / scale px wide,
-- centred in its frame; kept = the half tile (16 / scale px) on the right side, shifted back to where it was (+-1/4 tile).
local function half_belt(layers, dir, kind)
  local out = {}
  for _, l in ipairs(layers) do
    local c = copy(l)
    local sc = l.scale or 1
    local half = math.floor(16 / sc + 0.5)
    -- sign: -1 = the low side (west / north) of the tile
    local back = ({ east = -1, west = 1, north = 1, south = -1 })[dir]   -- side of the tile the belt comes from
    local side = kind == "in" and back or -back
    local sh = l.shift or { 0, 0 }
    local sx, sy = sh[1] or sh.x or 0, sh[2] or sh.y or 0
    if dir == "east" or dir == "west" then
      c.width = half
      c.x = l.x + (side < 0 and (l.width / 2 - half) or (l.width / 2))
      c.shift = { sx + side * 0.25, sy }
    else
      c.height = half
      c.y = l.y + (side < 0 and (l.height / 2 - half) or (l.height / 2))
      c.shift = { sx, sy + side * 0.25 }
    end
    out[#out + 1] = c
  end
  return out
end

-- Structure frame (hood) of direction `dir` of direction_in / direction_out (a Sprite4Way sheet), no patches.
local function structure(p, kind, dir)
  local node = type(p.structure) == "table" and p.structure["direction_" .. kind]
  if type(node) ~= "table" then return nil end
  local r = pictures.resolve(node, dir)
  if #r == 0 then return nil end
  return r
end

-- The direction_out sheet is stored flow-reversed: its "north" frame is an exit whose belt leaves SOUTH (viewed 2026-11-14:
-- base underground-belt-structure.png, out row frame 0 = chevrons pointing down, in row frame 0 = chevrons up). The model's
-- `dir` is the belt flow for both ends, so an exit takes the opposite frame (0.4.7 used `dir`: exits looked turned 180
-- degrees, portal report Maxorio 2026-11-14).
local OPPOSITE = { north = "south", east = "west", south = "north", west = "east" }
M.OPPOSITE = OPPOSITE

function M.underground(name, p)
  local out = {}
  if type(p.belt_animation_set) ~= "table" then return out end
  for _, dir in ipairs(DIRS) do
    local row = belt_row(p, belt_index(p, dir == "north" and "north" or dir))
    for _, kind in ipairs({ "in", "out" }) do
      local st = structure(p, kind, kind == "out" and OPPOSITE[dir] or dir)
      if row and st then
        local layers = half_belt(row, dir, kind)
        for _, l in ipairs(st) do layers[#layers + 1] = l end
        out[#out + 1] = { type = "sprite", name = "fv-e-" .. name .. "-" .. kind .. "-" .. dir, layers = pictures.clean(layers) }
      end
    end
  end
  return out
end

function M.curves(name, p)
  local out = {}
  if type(p.belt_animation_set) ~= "table" then return out end
  for _, key in ipairs(CURVES) do
    local row = belt_row(p, belt_index(p, key))
    if row then
      out[#out + 1] = { type = "sprite", name = "fv-e-" .. name .. "-r" .. M.BELT_DEFAULT[key], layers = pictures.clean(row) }
    end
  end
  return out
end

-- Mask -> key of `pictures`. Evidence: the 16 PNGs viewed in a contact sheet: ending_<d> = open flange on side <d>, cap on
-- the other; t_<d> = the bar plus the stem towards <d> (t_up = W+E+N); corner_<a>_<b> joins sides a and b.
local PIPE_KEY = {
  [0] = "straight_vertical_single",
  [1] = "ending_up", [2] = "ending_right", [4] = "ending_down", [8] = "ending_left",
  [3] = "corner_up_right", [6] = "corner_down_right", [12] = "corner_down_left", [9] = "corner_up_left",
  [5] = "straight_vertical", [10] = "straight_horizontal",
  [11] = "t_up", [7] = "t_right", [14] = "t_down", [13] = "t_left", [15] = "cross",
}
M.PIPE_KEY = PIPE_KEY

function M.pipes(name, p)
  local out = {}
  if type(p.pictures) ~= "table" then return out end
  for mask = 0, 15 do
    local node = p.pictures[PIPE_KEY[mask]]
    local layers = node and pictures.find_layers({ picture = node })
    if layers and #layers > 0 then
      out[#out + 1] = { type = "sprite", name = "fv-e-" .. name .. "-m" .. mask, layers = pictures.clean(layers) }
    end
  end
  return out
end

-- Beacon with the modules of each slot: fv-e-<beacon>-t<a>[<b>], one digit per slot = tier 0 (empty) .. 3. Only for <= 2
-- slots (4^n sprites); others keep the generic fv-e-<beacon> (tier 1 in every slot). Frame k of a slot's has_empty_slot
-- sheet = tier k (0 = empty slot), see pictures.module_slots.
M.BEACON_MAX_SLOTS = 2
function M.beacons(name, p)
  local out = {}
  local n = p.module_slots or 0
  if n < 1 or n > M.BEACON_MAX_SLOTS then return out end
  local function combos(i, tiers)
    if i > n then
      local layers = pictures.find_layers(p, "north", nil, tiers)
      if #layers > 0 then
        out[#out + 1] = { type = "sprite", name = "fv-e-" .. name .. "-t" .. table.concat(tiers), layers = pictures.clean(layers) }
      end
      return
    end
    for t = 0, 3 do
      tiers[i] = t
      combos(i + 1, tiers)
    end
    tiers[i] = nil
  end
  combos(1, {})
  return out
end

-- Inserter arm at rest, drawn north-facing (pickup side up) and turned with the render object's `orientation`:
-- fv-arm-<inserter> = hand_base centred on the shoulder + hand_open with its claw tip ARM_TIP tiles short of the pickup
-- position, hand over the base (south-facing real arms show the windowed forearm over the bar; north-facing ones hide it under the platform, not matched) (real idle inserters rest over the pickup side; measured against the art shot, CLAUDE.md "Inserter arms").
M.ARM_TIP = -0.1   -- negative = the claw tip reaches 0.1 tile PAST the pickup position
function M.arm(name, p)
  local base, hand = pictures.leaf(p.hand_base_picture), pictures.leaf(p.hand_open_picture)
  if not (base and hand) then return {} end
  local pk = p.pickup_position or { 0, -1 }
  local reach = math.abs(pk[2] or pk.y or -1) - M.ARM_TIP
  base.shift = { 0, 0 }
  hand.shift = { 0, -reach + hand.height * (hand.scale or 1) / 32 / 2 }
  return { { type = "sprite", name = "fv-arm-" .. name, layers = pictures.clean({ base, hand }) } }
end

-- All sprites for the prototypes in data.raw (a list of sprite prototypes).
function M.sprites(raw)
  local list = {}
  local function each(t, f)
    local names = {}
    for n in pairs(raw[t] or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      local ok, res = pcall(f, n, raw[t][n])
      if ok then
        for _, s in ipairs(res) do list[#list + 1] = s end
      else
        log("fleet-view skip shape art: " .. t .. "/" .. n .. " " .. tostring(res))
      end
    end
  end
  each("transport-belt", M.curves)
  each("underground-belt", M.underground)
  each("pipe", M.pipes)
  each("beacon", M.beacons)
  each("inserter", M.arm)
  return list
end

function M.make(raw)
  local list = M.sprites(raw)
  if #list > 0 then data:extend(list) end
  log("fleet-view: " .. #list .. " shape sprites (curved belts, undergrounds, joined pipes, beacon modules, inserter arms)")
  return list
end

return M
