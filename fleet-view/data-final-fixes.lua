-- One still sprite "fv-e-<entity>" per placeable entity; runtime falls back to the icon when absent.
local pictures = require("prototypes.pictures")

local placed = {}
for _, group in pairs(data.raw) do
  for _, p in pairs(group) do
    if type(p) == "table" and type(p.place_result) == "string" then placed[p.place_result] = true end
  end
end

local made, skipped, seen, directional, shadows, glows = 0, 0, {}, 0, 0, 0
-- Shadow layers (0.4.7): `fv-e-<name>-sh` (+ `-sh-<dir>` when that direction differs), only when the entity has any.
local EXTRA = { { "sh", "shadow" } }  -- glow layers cannot be drawn by script sprites (docs/shadows-glows.md)
local function extras(name, p)
  for _, ex in ipairs(EXTRA) do
    local ok, base = pcall(pictures.find_layers, p, "north", ex[2])
    if ok and #base > 0 then
      data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-" .. ex[1], layers = pictures.clean(base, true) } })
      if ex[1] == "sh" then shadows = shadows + 1 else glows = glows + 1 end
      for _, d in ipairs({ "east", "south", "west" }) do
        local ok2, dl = pcall(pictures.find_layers, p, d, ex[2])
        if ok2 and #dl > 0 and not pictures.same_layers(base, dl) then
          data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-" .. ex[1] .. "-" .. d, layers = pictures.clean(dl, true) } })
        end
      end
    end
  end
end
local DIRS = { "east", "south", "west" }
for _, group in pairs(data.raw) do
  for name, p in pairs(group) do
    if type(p) == "table" and type(name) == "string" and p.stack_size == nil and (p.collision_box or p.selection_box)
      and (p.minable or placed[name]) and not seen[name] then
      seen[name] = true
      local ok = pcall(function()
        local layers = pictures.find_layers(p)
        if #layers == 0 then error("no usable graphic") end
        data:extend({ { type = "sprite", name = "fv-e-" .. name, layers = pictures.clean(layers) } })
        pcall(extras, name, p)
        -- extra sprite per direction only when it differs from north (runtime: fv-e-<name>-<dir>)
        for _, d in ipairs(DIRS) do
          local ok2, dl = pcall(pictures.find_layers, p, d)
          if ok2 and #dl > 0 and not pictures.same_layers(layers, dl) then
            data:extend({ { type = "sprite", name = "fv-e-" .. name .. "-" .. d, layers = pictures.clean(dl) } })
            directional = directional + 1
          end
        end
      end)
      if ok then made = made + 1 else skipped = skipped + 1; if placed[name] then log("fleet-view skip: " .. p.type .. "/" .. name) end end
    end
  end
end
log("fleet-view: " .. made .. " sprites, " .. skipped .. " skipped, " .. directional .. " directional, " .. shadows .. " shadow, " .. glows .. " glow")

-- Cargo bay / hub: art split by render layer, connection pieces, lids, giga hatches (docs/bay-connections.md).
require("prototypes.connections").make(data.raw)

-- Curved belts, underground belt halves, joined pipes (one layered sprite per shape).
require("prototypes.art").make(data.raw)

-- Platform edge pieces (underside art on the empty tiles next to the deck).
require("prototypes.edges").make()

-- Sort-key shifts (0.4.10, scripts/sortkey.lua, docs/layer-order.md): every fleet-view sprite gets a downward
-- `shift`; draw.lua targets it that much higher, so it draws where it did but sorts far above (under the viewer's
-- hanging deck edges; floor under buildings). Sprites drawn with `orientation` first get turned copies "-fvq<1..3>"
-- (the shift turns with the sprite: their copy's shift is pre-turned so it points down once rotated).
do
  local sortkey = require("scripts.sortkey")
  local sprites = data.raw.sprite
  local turn = {}
  for _, t in ipairs(sortkey.ROTATED_TYPES) do
    for name in pairs(data.raw[t] or {}) do
      for _, base in ipairs({ "fv-e-" .. name, "fv-e-" .. name .. "-sh" }) do
        if sprites[base] then turn[#turn + 1] = base end
      end
    end
  end
  for name in pairs(sprites) do
    if name:sub(1, 7) == "fv-arm-" then turn[#turn + 1] = name end
  end
  local copies = {}
  for _, base in ipairs(turn) do
    for q = 1, 3 do
      local c = table.deepcopy(sprites[base])
      c.name = base .. "-fvq" .. q
      copies[#copies + 1] = c
    end
  end
  if #copies > 0 then data:extend(copies) end
  local function add_shift(t, x, y)
    if t.layers then for _, l in ipairs(t.layers) do add_shift(l, x, y) end; return end
    local s = t.shift
    local sx, sy = 0, 0
    if s then sx, sy = s[1] or s.x or 0, s[2] or s.y or 0 end
    t.shift = { sx + x, sy + y }
  end
  local shifted, padded = 0, 0
  for name, sp in pairs(sprites) do
    if name:sub(1, 3) == "fv-" then
      local x, y = sortkey.shift(name)
      -- a shift over ~256 tiles is not drawn at all (docs/layer-order.md): fail the load instead of losing the sprite
      assert(math.sqrt(x * x + y * y) <= sortkey.MAX_SHIFT, "fleet-view: sort-key shift too big for " .. name)
      if x ~= 0 or y ~= 0 then
        add_shift(sp, x, y)
        shifted = shifted + 1
        -- culling looks at the first layer's (trimmed) size only: the pad in front keeps the sprite drawn while its
        -- target is above the view (scripts/sortkey.lua)
        local pad = { filename = sortkey.PAD.filename, width = sortkey.PAD.px, height = sortkey.PAD.px,
          scale = sortkey.PAD.scale, shift = { x, y } }
        if not sp.layers then
          local own = table.deepcopy(sp)
          own.type, own.name = nil, nil
          for k in pairs(sp) do if k ~= "type" and k ~= "name" then sp[k] = nil end end
          sp.layers = { own }
        end
        table.insert(sp.layers, 1, pad)
        padded = padded + 1
      end
    end
  end
  log("fleet-view: sort-key shift on " .. shifted .. " sprites (" .. padded .. " padded), " .. #copies .. " turned copies")
end

-- Light per space location, read at runtime (the runtime API does not expose platform_backdrop).
local lights = {}
for _, kind in ipairs({"planet", "space-location"}) do
  for name, p in pairs(data.raw[kind] or {}) do
    local b = p.platform_surface_render_parameters and p.platform_surface_render_parameters.platform_backdrop
    if b and b.light_direction then
      local d, c = b.light_direction, b.light_color
      lights[name] = {
        dir = {d[1] or d.x, d[2] or d.y, d[3] or d.z},
        color = c and {c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1} or {1, 1, 1},
      }
    end
  end
end
data:extend({{type = "mod-data", name = "fv-lights", data = lights}})
