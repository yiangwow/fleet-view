-- Platform art (0.4.6): sheet frames per direction, beacon layers + modules, curved belts, undergrounds, joined pipes.
package.path = "fleet-view/?.lua;fleet-view/scripts/?.lua;" .. package.path
local pictures = require("prototypes.pictures")
local art = require("prototypes.art")
local snapshot = require("scripts.snapshot")

local function tiles(n)
  local t = {}
  for y = 0, n - 1 do for x = 0, n - 1 do t[#t + 1] = {x = x, y = y} end end
  return t
end
local function ent(e) e.w = e.w or 1; e.h = e.h or 1; return e end
local function find(m, name) for _, e in ipairs(m.ents) do if e.name == name then return e end end end

return {
  sheet_frame_per_direction = function()
    local p = { platform_picture = { sheet = { filename = "i.png", width = 105, height = 79, x = 0, y = 0 } } }
    p.platform_picture.sheet.frames = nil
    local want = { north = 0, east = 105, south = 210, west = 315 }
    for d, x in pairs(want) do
      local l = pictures.find_layers({ platform_picture = p.platform_picture }, d)[1]
      assert_eq(l.x, x, d); assert_eq(l.y, 0, d)
    end
  end,
  sheet_keeps_start_offset = function()   -- underground structure: y = 192 row, frame per direction in x
    local n = { sheet = { filename = "u.png", width = 192, height = 192, y = 192 } }
    local l = pictures.resolve(n, "south")[1]
    assert_eq(l.x, 384); assert_eq(l.y, 192)
  end,
  two_frame_sheet_wraps = function()   -- storage tank: north/south = frame 0, east/west = frame 1
    local n = { sheets = { { filename = "t.png", width = 219, height = 235, frames = 2 } } }
    assert_eq(pictures.resolve(n, "north")[1].x, 0)
    assert_eq(pictures.resolve(n, "east")[1].x, 219)
    assert_eq(pictures.resolve(n, "south")[1].x, 0)
    assert_eq(pictures.resolve(n, "west")[1].x, 219)
  end,
  sheet_line_length_wraps_rows = function()
    local n = { sheet = { filename = "t.png", width = 10, height = 20, frames = 4, line_length = 2 } }
    local w = pictures.resolve(n, "west")[1]    -- frame 3 = column 1, row 1
    assert_eq(w.x, 10); assert_eq(w.y, 20)
    local s = pictures.resolve(n, "south")[1]   -- frame 2 = column 0, row 1
    assert_eq(s.x, 0); assert_eq(s.y, 20)
  end,
  beacon_layers_and_modules = function()
    local p = { graphics_set = {
      animation_list = {
        { render_layer = "floor-mechanics", always_draw = true, animation = { layers = {
          { filename = "bottom.png", width = 212, height = 192 },
          { filename = "shadow.png", width = 244, height = 176, draw_as_shadow = true } } } },
        { render_layer = "object", always_draw = true, animation = { filename = "top.png", width = 96, height = 140 } },
        { render_layer = "object", always_draw = false, animation = { filename = "light.png", width = 110, height = 186 } },
      },
      module_visualisations = { { slots = {
        { { has_empty_slot = true, pictures = { filename = "s1.png", line_length = 4, width = 50, height = 66, variation_count = 4 } },
          { pictures = { filename = "mask.png", width = 36, height = 32, variation_count = 3, line_length = 3 } } },
        { { has_empty_slot = true, pictures = { filename = "s2.png", line_length = 4, width = 46, height = 44, variation_count = 4 } } },
      } } },
    } }
    local l = pictures.find_layers(p)
    assert_eq(#l, 4)
    assert_eq(l[1].filename, "bottom.png")
    assert_eq(l[2].filename, "s1.png"); assert_eq(l[2].x, 50)    -- frame 1 = a module
    assert_eq(l[3].filename, "s2.png"); assert_eq(l[3].x, 46)
    assert_eq(l[4].filename, "top.png")                           -- modules sit under the top; always_draw=false skipped
  end,
  beacon_without_module_structure = function()
    local p = { graphics_set = { animation_list = { { animation = { filename = "a.png", width = 4, height = 4 } } } } }
    local l = pictures.find_layers(p)
    assert_eq(#l, 1); assert_eq(l[1].filename, "a.png")
    p.graphics_set.module_visualisations = { { slots = { { { has_empty_slot = true, pictures = { filename = "x.png", width = 4, height = 4, variation_count = 1 } } } } } }
    assert_eq(#pictures.find_layers(p), 1)   -- one variation only: no module frame, skipped silently
  end,
  curved_belt_sprites = function()
    local p = { belt_animation_set = { animation_set = { filename = "b.png", size = 128, frame_count = 16, direction_count = 20 },
      west_to_north_index = 9 } }
    local list = art.curves("belt", p)
    assert_eq(#list, 8)
    local by = {}
    for _, s in ipairs(list) do by[s.name] = s.layers[1] end
    assert_eq(by["fv-e-belt-r5"].y, 4 * 128)      -- default index 5 -> row 4
    assert_eq(by["fv-e-belt-r7"].y, 8 * 128)      -- override: west_to_north at index 9, still named by the default 7
    assert_eq(by["fv-e-belt-r12"].y, 11 * 128)
  end,
  curved_belt_sprites_split_over_files = function()
    -- Factorio HD Age turbo belt (portal crash 2026-11-14, NOiZE): 256 px frames, 64 frames as 2 lines of 32 per
    -- direction, 20 lines per file -> directions 1..10 in -1.png, 11..20 in -2.png. Row 11 used to read y 5120 of -1.png.
    local p = { belt_animation_set = { animation_set = { filenames = { "b-1.png", "b-2.png" }, lines_per_file = 20,
      size = 256, scale = 0.25, frame_count = 64, line_length = 32, direction_count = 20 } } }
    local by = {}
    for _, s in ipairs(art.curves("belt", p)) do by[s.name] = s.layers[1] end
    assert_eq(by["fv-e-belt-r10"].filename, "b-1.png"); assert_eq(by["fv-e-belt-r10"].y, 18 * 256)
    assert_eq(by["fv-e-belt-r11"].filename, "b-2.png"); assert_eq(by["fv-e-belt-r11"].y, 0)
    assert_eq(by["fv-e-belt-r12"].filename, "b-2.png"); assert_eq(by["fv-e-belt-r12"].y, 2 * 256)
  end,
  underground_sprites = function()
    local p = {
      belt_animation_set = { animation_set = { filename = "b.png", size = 128, scale = 0.5, frame_count = 16, direction_count = 20 } },
      structure = {
        direction_in = { sheet = { filename = "s.png", width = 192, height = 192, y = 192, scale = 0.5 } },
        direction_out = { sheet = { filename = "s.png", width = 192, height = 192, scale = 0.5 } } } }
    local list = art.underground("ug", p)
    assert_eq(#list, 8)
    local by = {}
    for _, s in ipairs(list) do by[s.name] = s.layers end
    local ie = by["fv-e-ug-in-east"]               -- belt arrives from the west: west half of the east row, hood frame 1 of the in row
    assert_eq(ie[1].y, 0); assert_eq(ie[1].x, 32); assert_eq(ie[1].width, 32); assert_eq(ie[1].shift[1], -0.25)
    assert_eq(ie[2].x, 192); assert_eq(ie[2].y, 192)
    local oe = by["fv-e-ug-out-east"]              -- belt leaves to the east: east half
    assert_eq(oe[1].x, 64); assert_eq(oe[1].shift[1], 0.25); assert_eq(oe[2].y, 0)
    local sn = by["fv-e-ug-in-south"]              -- south row 4 -> y 384; comes from the north: north half
    assert_eq(sn[1].y, 3 * 128 + 32); assert_eq(sn[1].height, 32); assert_eq(sn[1].shift[2], -0.25)
    assert_eq(sn[2].x, 384)
    for _, l in ipairs(by["fv-e-ug-out-north"]) do assert(l.x + l.width <= 2048 and l.width > 0) end
  end,
  pipe_sprites_cover_all_masks = function()
    local pic = {}
    for _, k in pairs(art.PIPE_KEY) do pic[k] = { filename = k .. ".png", width = 128, height = 128 } end
    local list = art.pipes("pipe", { pictures = pic })
    assert_eq(#list, 16)
    local by = {}
    for _, s in ipairs(list) do by[s.name] = s.layers[1].filename end
    assert_eq(by["fv-e-pipe-m0"], "straight_vertical_single.png")
    assert_eq(by["fv-e-pipe-m5"], "straight_vertical.png")
    assert_eq(by["fv-e-pipe-m3"], "corner_up_right.png")      -- N + E
    assert_eq(by["fv-e-pipe-m11"], "t_up.png")                -- N + E + W
    assert_eq(by["fv-e-pipe-m15"], "cross.png")
  end,
  model_curve_ug_pmask = function()
    local es = {
      ent({name = "transport-belt", type = "transport-belt", x = 1.5, y = 1.5, dir = 0, shape = "left"}),
      ent({name = "transport-belt", type = "transport-belt", x = 2.5, y = 1.5, dir = 12, shape = "right"}),
      ent({name = "transport-belt", type = "transport-belt", x = 3.5, y = 1.5, dir = 4, shape = "straight"}),
      ent({name = "underground-belt", type = "underground-belt", x = 4.5, y = 1.5, dir = 8, ug = "output"}),
      ent({name = "underground-belt", type = "underground-belt", x = 5.5, y = 1.5, dir = 0, ug = "input"}),
      ent({name = "pipe", type = "pipe", x = 6.5, y = 1.5, pmask = 5}),
    }
    local m = snapshot.build_model(tiles(8), es, 1)
    local seen = {}
    for _, e in ipairs(m.ents) do seen[#seen + 1] = e end
    local function at(x) for _, e in ipairs(seen) do if math.abs(e.x - (x - m.centre.x)) < 1e-9 then return e end end end
    assert_eq(at(1.5).row, 7); assert_eq(at(2.5).row, 8); assert_eq(at(3.5).row, nil)
    assert_eq(at(3.5).rot, 0)                                  -- straight belt east: unchanged rotation
    assert_eq(at(4.5).ug, "out"); assert_eq(at(4.5).dir, 8)
    assert_eq(at(5.5).ug, "in"); assert_eq(at(5.5).dir, nil)
    assert_eq(at(6.5).pmask, 5)
  end,
  old_model_input_unchanged = function()   -- no shape fields: no row/ug/pmask, rotation as before
    local es = {
      ent({name = "transport-belt", type = "transport-belt", x = 1.5, y = 1.5, dir = 8}),
      ent({name = "underground-belt", type = "underground-belt", x = 2.5, y = 1.5, dir = 4}),
      ent({name = "pipe", type = "pipe", x = 3.5, y = 1.5}),
      ent({name = "pipe", type = "pipe", x = 4.5, y = 1.5}),
    }
    local m = snapshot.build_model(tiles(8), es, 1)
    for _, e in ipairs(m.ents) do
      assert_eq(e.row, nil); assert_eq(e.ug, nil); assert_eq(e.pmask, nil)
    end
    assert_eq(find(m, "underground-belt").rot, (4 / 16 - 0.25) % 1)
    assert_eq(find(m, "underground-belt").dir, nil)
    assert_eq(find(m, "pipe").rot, 0.25)                       -- horizontal run
  end,
  belt_curve_table_complete = function()
    for _, shape in ipairs({ "left", "right" }) do
      local seen = {}
      for _, d in ipairs({ 0, 4, 8, 12 }) do
        local r = snapshot.BELT_CURVE[shape][d]
        assert(r and r >= 5 and r <= 12 and not seen[r], shape .. " " .. d)
        seen[r] = true
      end
    end
  end,
  -- 0.4.6 beacon module tiers: frame = tier per slot, one sprite per slot-tier combo (<= 2 slots, 16 for 2 slots)
  beacon_sprite_per_slot_tier = function()
    local p = { type = "beacon", module_slots = 2, graphics_set = {
      animation_list = { { render_layer = "object", always_draw = true, animation = { filename = "top.png", width = 96, height = 140 } } },
      module_visualisations = { { slots = {
        { { has_empty_slot = true, pictures = { filename = "s1.png", line_length = 4, width = 50, height = 66, variation_count = 4 } } },
        { { has_empty_slot = true, pictures = { filename = "s2.png", line_length = 4, width = 46, height = 44, variation_count = 4 } } },
      } } } } }
    local list = art.beacons("beacon", p)
    assert_eq(#list, 16)
    local by = {}
    for _, sp in ipairs(list) do by[sp.name] = sp end
    local function slot(name, filename)
      for _, l in ipairs(by[name].layers) do if l.filename == filename then return l end end
    end
    assert_eq(slot("fv-e-beacon-t03", "s1.png").x, 0)    -- slot 1 empty = frame 0
    assert_eq(slot("fv-e-beacon-t03", "s2.png").x, 138)  -- slot 2 tier 3 = frame 3
    assert_eq(slot("fv-e-beacon-t20", "s1.png").x, 100)  -- slot 1 tier 2 = frame 2
    assert_eq(slot("fv-e-beacon-t12", "s2.png").x, 92)
    -- generic (nil tiers) keeps frame 1 in every slot
    assert_eq(pictures.find_layers(p)[1].x, 50); assert_eq(pictures.find_layers(p)[2].x, 46)
  end,
  beacon_many_slots_stay_generic = function()
    assert_eq(#art.beacons("beacon", { module_slots = 3, graphics_set = {} }), 0)
  end,
  inserter_arm_sprite = function()
    local p = { type = "inserter", pickup_position = { 0, -1 },
      hand_base_picture = { filename = "b.png", width = 32, height = 136, scale = 0.25 },
      hand_open_picture = { filename = "o.png", width = 72, height = 164, scale = 0.25 } }
    local sp = art.arm("inserter", p)[1]
    assert_eq(sp.name, "fv-arm-inserter")
    assert_eq(#sp.layers, 2)
    assert_eq(sp.layers[1].filename, "b.png"); assert_eq(sp.layers[2].filename, "o.png")
    -- claw tip ARM_TIP past the pickup: centre = -(1 - ARM_TIP) + height / 2
    assert_near(sp.layers[2].shift[2], -(1 - art.ARM_TIP) + 164 * 0.25 / 32 / 2, 1e-9)
    assert_eq(#art.arm("inserter", { type = "inserter" }), 0)   -- no hand art: no sprite
  end,
  model_keeps_beacon_tiers = function()
    local m = snapshot.build_model(tiles(4), { ent({ name = "beacon", type = "beacon", x = 2, y = 2, w = 3, h = 3, mods = { 3, 0 } }) }, 0)
    assert_eq(#find(m, "beacon").mods, 2); assert_eq(find(m, "beacon").mods[1], 3); assert_eq(find(m, "beacon").mods[2], 0)
  end,
  glows_only_lit_lamps_and_capped = function()
    local ents = {}
    for i = 1, 40 do ents[#ents + 1] = ent({ name = "small-lamp", type = "lamp", x = 0.5 + (i % 8), y = 0.5 + math.floor(i / 8), lit = (i % 2 == 0) or nil }) end
    ents[#ents + 1] = ent({ name = "small-lamp", type = "lamp", x = 7.5, y = 7.5, lit = true, color = { 0.2, 1, 0.3 } })
    local m = snapshot.build_model(tiles(8), ents, 0)
    assert(#m.glows >= 1 and #m.glows <= snapshot.MAX_GLOWS, "glows capped: " .. #m.glows)
    local few = snapshot.build_model(tiles(8), { ent({ name = "small-lamp", type = "lamp", x = 1.5, y = 1.5, lit = true, color = { 0.2, 1, 0.3 } }),
      ent({ name = "small-lamp", type = "lamp", x = 3.5, y = 1.5 }) }, 0)
    assert_eq(#few.glows, 1)   -- the unlit one does not glow
    assert_near(few.glows[1].g, 1, 1e-9); assert_near(few.glows[1].r, 0.2, 1e-9)
    assert_near(few.glows[1].x, 1.5 - few.centre.x, 1e-9)
    assert_eq(#snapshot.build_model(tiles(8), {}, 0).glows, 0)
  end,
}
