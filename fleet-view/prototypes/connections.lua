-- Data stage: sprites for the cargo bay / hub connection pieces, bay lids and hub giga hatches (docs/bay-connections.md).
-- Writes the mod-data "fv-conn" read at runtime: {map = {["<mask>"] = {tileset index...}}, tiles = {[<tileset index>] =
-- {group = {variation = "<col>-<row>"}}}, bridges = {[kind] = {variation = "<col>-<row>"}}}; sprite of a piece layer L (0..3) = "fv-c-<col>-<row>-<L>".
local pictures = require("prototypes.pictures")
local M = {}

-- Phase of an entity layer by render layer: 0..3 follow the connection layers, 4 = everything above.
local PHASE = { ["lower-object-above-shadow"] = 0, ["lower-object-overlay"] = 1, ["object-under"] = 2, ["object"] = 3 }

local function shifted(l, ox, oy)
  local c = {}
  for k, v in pairs(l) do if k ~= "rl" then c[k] = v end end
  local s = l.shift or { 0, 0 }
  c.shift = { (s[1] or s.x or 0) + ox, (s[2] or s.y or 0) + oy }
  return c
end

local function phase_sprites(name, p)
  local layers = pictures.find_layers(p)
  local by = {}
  for _, l in ipairs(layers) do
    local ph = PHASE[l.rl or "object"] or 4
    by[ph] = by[ph] or {}
    by[ph][#by[ph] + 1] = l
  end
  for ph = 0, 4 do
    if by[ph] then
      data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-p" .. ph, layers = pictures.clean(by[ph]) } })
    end
  end
end

-- Bay lid: frame 0 of the first hatch's graphics, at the hatch offset.
local function lid(name, p)
  local h = p.hatch_definitions and p.hatch_definitions[1]
  if not (h and h.hatch_graphics) then return end
  local ls = pictures.find_layers({ animation = h.hatch_graphics })
  local off = h.offset or { 0, 0 }
  if #ls == 0 then return end
  data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-lid",
    layers = { shifted(ls[1], off[1] or off.x or 0, off[2] or off.y or 0) } } })
end

-- Hub giga hatches: back + front, frame 0, "gl" (lower, cargo-hatch layer) and "gu" (upper, above-inserters).
local function giga(name, p)
  local csp = p.cargo_station_parameters
  for _, g in ipairs(csp and csp.giga_hatch_definitions or {}) do
    local layers = {}
    for _, k in ipairs({ "hatch_graphics_back", "hatch_graphics_front" }) do
      if g[k] then
        for _, l in ipairs(pictures.find_layers({ animation = g[k] })) do layers[#layers + 1] = l end
      end
    end
    if #layers > 0 then
      local suffix = (g.hatch_render_layer_back == "cargo-hatch") and "gl" or "gu"
      data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-" .. suffix, layers = pictures.clean(layers) } })
    end
  end
end

local function pieces(conn)
  local made, tiles, seen = 0, {}, {}
  local function frame(v)
    local ls = {}
    for L = 1, 4 do
      local g = v[L]
      local n = (L == 4) and g.layers and g.layers[1] or g
      local l = pictures.leaf(n)
      if not l then return nil end
      ls[L] = l
    end
    local col, row = math.floor(ls[1].x / ls[1].width + 0.5), math.floor(ls[1].y / ls[1].height + 0.5)
    local id = col .. "-" .. row
    if not seen[id] then
      seen[id] = true
      for L = 1, 4 do
        data:extend({ { type = "sprite", name = "fv-c-" .. id .. "-" .. (L - 1), layers = pictures.clean({ ls[L] }) } })
        made = made + 1
      end
    end
    return id
  end
  for i, groups in ipairs(conn.tileset or {}) do
    tiles[i] = {}
    for gi, vars in ipairs(groups) do
      tiles[i][gi] = {}
      for vi, v in ipairs(vars) do tiles[i][gi][vi] = frame(v) or "" end
    end
  end
  local map = {}
  for mask, v in pairs(conn.tileset_mapping or {}) do
    map[tostring(mask)] = type(v) == "table" and v or { v }
  end
  -- bridges: kind 1 horizontal narrow, 2 horizontal wide, 3 vertical narrow, 4 vertical wide, 5 crossing (snapshot.conn_tiles)
  local bridges = {}
  for kind, key in ipairs({ "bridge_horizontal_narrow", "bridge_horizontal_wide", "bridge_vertical_narrow",
    "bridge_vertical_wide", "bridge_crossing" }) do
    bridges[kind] = {}
    for vi, v in ipairs(conn[key] or {}) do bridges[kind][vi] = frame(v) or "" end
  end
  data:extend({ { type = "mod-data", name = "fv-conn", data = { map = map, tiles = tiles, bridges = bridges } } })
  return made
end

function M.make(raw)
  local conn
  for _, t in ipairs({ "cargo-bay", "space-platform-hub" }) do
    local names = {}
    for name in pairs(raw[t] or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local p = raw[t][name]
      if not pcall(phase_sprites, name, p) then log("fleet-view skip phases: " .. name) end
      if t == "cargo-bay" then pcall(lid, name, p) else pcall(giga, name, p) end
      -- the space art's connections only (planet bays use the planet set)
      local gs = (t == "cargo-bay") and p.platform_graphics_set or (t ~= "cargo-bay" and p.graphics_set)
      if not conn and gs and gs.connections then conn = gs.connections end
    end
  end
  if conn then
    local ok, n = pcall(pieces, conn)
    log("fleet-view: connection pieces " .. tostring(ok and n or ("failed: " .. tostring(n))))
  end
end

return M
