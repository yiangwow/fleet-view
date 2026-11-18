local pictures = require("prototypes.pictures")

return {
  -- Carna 0.3.27 algite-knowledge-chamber: size = {276,208} next to a stale width = 278. Factorio uses size; reading
  -- width made a sprite rectangle wider than the image and crashed the game at load.
  size_wins_over_width_height = function()
    local p = { type = "assembling-machine", name = "am", graphics_set = { idle_animation = { layers = {
      { filename = "b.png", size = { 276, 208 }, width = 278, height = 210, repeat_count = 47 },
    } } } }
    local s = pictures.find_layer(p)
    assert_eq(s.width, 276); assert_eq(s.height, 208)
    p.graphics_set.idle_animation.layers[1].size = 64
    s = pictures.find_layer(p)
    assert_eq(s.width, 64); assert_eq(s.height, 64)
  end,
  assembling_machine_layer1_frame0 = function()
    local p = { type = "assembling-machine", name = "am", graphics_set = { animation = { layers = {
      { filename = "a.png", width = 100, height = 120, scale = 0.5, shift = { 0, -1 }, frame_count = 32, line_length = 8 },
      { filename = "a-sh.png", width = 100, height = 120, draw_as_shadow = true },
    } } } }
    local s = pictures.find_layer(p)
    assert_eq(s.filename, "a.png")
    assert_eq(s.width, 100); assert_eq(s.height, 120)
    assert_eq(s.x, 0); assert_eq(s.y, 0); assert_eq(s.scale, 0.5)
    assert_eq(s.shift[2], -1)
    assert_eq(s.frame_count, nil)
  end,
  shadow_and_glow_layers_are_found_separately = function()
    local p = { type = "assembling-machine", name = "am", graphics_set = { animation = { layers = {
      { filename = "a.png", width = 10, height = 10 },
      { filename = "a-sh.png", width = 12, height = 10, shift = { 1, 0 }, draw_as_shadow = true },
      { filename = "a-gl.png", width = 10, height = 10, draw_as_glow = true },
      { filename = "a-li.png", width = 10, height = 10, draw_as_light = true },
    } } } }
    assert_eq(#pictures.find_layers(p), 1)
    assert_eq(pictures.find_layers(p)[1].filename, "a.png")
    local sh = pictures.find_layers(p, "north", "shadow")
    assert_eq(#sh, 1); assert_eq(sh[1].filename, "a-sh.png"); assert_eq(sh[1].shift[1], 1)
    local gl = pictures.find_layers(p, "north", "glow")
    assert_eq(#gl, 2); assert_eq(gl[1].filename, "a-gl.png"); assert_eq(gl[2].filename, "a-li.png")
    assert_eq(#pictures.find_layers(p), 1)   -- the kind does not leak into the next call
  end,
  entity_without_shadow_has_none = function()
    local p = { type = "solar-panel", name = "sp", picture = { layers = { { filename = "sp.png", width = 2, height = 3 } } } }
    assert_eq(#pictures.find_layers(p, "north", "shadow"), 0)
    assert_eq(#pictures.find_layers(p, "north", "glow"), 0)
  end,
  clean_plain_drops_flags = function()
    local l = { { filename = "g.png", width = 1, height = 1, draw_as_glow = true, rl = "object" },
                { filename = "s.png", width = 1, height = 1, draw_as_shadow = true } }
    local c = pictures.clean(l, true)
    assert_eq(c[1].draw_as_glow, nil); assert_eq(c[1].rl, nil)
    assert_eq(c[2].draw_as_shadow, nil)
    assert_eq(pictures.clean(l)[1].draw_as_glow, true)   -- default keeps the flags
  end,
  shadow_per_direction = function()
    local function gset(d) return { animation = { layers = {
      { filename = d .. "-base.png", width = 4, height = 4 },
      { filename = d .. "-sh.png", width = 4, height = 4, draw_as_shadow = true },
    } } } end
    local p = { type = "fusion-generator", name = "fg", graphics_set = {
      north_graphics_set = gset("n"), east_graphics_set = gset("e"), south_graphics_set = gset("s"), west_graphics_set = gset("w") } }
    assert_eq(pictures.find_layers(p, "east", "shadow")[1].filename, "e-sh.png")
    assert_eq(pictures.find_layers(p, "north", "shadow")[1].filename, "n-sh.png")
  end,
  solar_panel_skips_shadow = function()
    local p = { type = "solar-panel", name = "sp", picture = { layers = {
      { filename = "sh.png", width = 1, height = 1, draw_as_shadow = true },
      { filename = "sp.png", width = 2, height = 3 },
    } } }
    assert_eq(pictures.find_layer(p).filename, "sp.png")
    local all = pictures.find_layers(p)
    assert_eq(#all, 1)
  end,
  icons_only_is_nil = function()
    assert_eq(pictures.find_layer({ type = "x", name = "i", icons = { { icon = "i.png" } } }), nil)
  end,
  four_direction_picks_north = function()
    local p = { type = "t", name = "t", animation = {
      east = { filename = "e.png", width = 1, height = 1 },
      north = { filename = "n.png", width = 1, height = 1 },
    } }
    assert_eq(pictures.find_layer(p).filename, "n.png")
  end,
  four_direction_picks_each_dir = function()
    local p = { type = "t", name = "t", animation = {
      east = { filename = "e.png", width = 1, height = 1 },
      north = { filename = "n.png", width = 1, height = 1 },
    } }
    assert_eq(pictures.find_layers(p, "east")[1].filename, "e.png")
    assert_eq(pictures.find_layers(p, "north")[1].filename, "n.png")
    assert_eq(pictures.find_layers(p)[1].filename, "n.png")
    assert_eq(pictures.find_layers(p, "west")[1].filename, "n.png")   -- missing direction = north
  end,
  fusion_like_graphics_sets_per_direction = function()
    local function gset(d) return { animation = { layers = {
      { filename = d .. "-base.png", width = 4, height = 4 },
      { filename = d .. "-sh.png", width = 4, height = 4, draw_as_shadow = true },
    } }, working_light = { filename = "l.png", width = 1, height = 1 } } end
    local p = { type = "fusion-generator", name = "fg", graphics_set = { glow_color = { 1, 0, 0, 1 },
      north_graphics_set = gset("n"), east_graphics_set = gset("e"),
      south_graphics_set = gset("s"), west_graphics_set = gset("w") } }
    for _, d in ipairs({ "north", "east", "south", "west" }) do
      local l = pictures.find_layers(p, d)
      assert_eq(#l, 1)
      assert_eq(l[1].filename, d:sub(1, 1) .. "-base.png")
    end
    assert_eq(pictures.find_layers(p)[1].filename, "n-base.png")
  end,
  north_only_prototype_has_same_layers_in_every_dir = function()
    local p = { type = "solar-panel", name = "sp", picture = { layers = { { filename = "sp.png", width = 2, height = 3 } } } }
    local n = pictures.find_layers(p)
    for _, d in ipairs({ "east", "south", "west" }) do
      assert(pictures.same_layers(n, pictures.find_layers(p, d)), d)
    end
  end,
  same_layers_compares_filename_and_offset = function()
    local a = { { filename = "a.png", x = 0, y = 0 } }
    assert(pictures.same_layers(a, { { filename = "a.png", x = 0, y = 0 } }))
    assert(not pictures.same_layers(a, { { filename = "a.png", x = 64, y = 0 } }))
    assert(not pictures.same_layers(a, { { filename = "b.png", x = 0, y = 0 } }))
    assert(not pictures.same_layers(a, {}))
  end,
  platform_graphics_set_wins_over_graphics_set = function()
    local p = { type = "cargo-bay", name = "cb",
      graphics_set = { picture = { filename = "planet.png", width = 4, height = 4 } },
      platform_graphics_set = { picture = { filename = "space.png", width = 4, height = 4 } } }
    assert_eq(pictures.find_layers(p)[1].filename, "space.png")
    p.platform_graphics_set = nil
    assert_eq(pictures.find_layers(p)[1].filename, "planet.png")
  end,
  stripes_and_filenames_take_first = function()
    local a = pictures.find_layer({ picture = { stripes = { { filename = "s1.png", width_in_frames = 4, height_in_frames = 1, x = 0, y = 0 }, { filename = "s2.png" } }, width = 10, height = 10 } })
    assert_eq(a.filename, "s1.png")
    local b = pictures.find_layer({ animation = { filenames = { "f1.png", "f2.png" }, width = 10, height = 10, slice = 4 } })
    assert_eq(b.filename, "f1.png")
  end,
  array_takes_first = function()
    local p = { pictures = { { filename = "p1.png", width = 1, height = 1 }, { filename = "p2.png", width = 1, height = 1 } } }
    assert_eq(pictures.find_layer(p).filename, "p1.png")
  end,
  render_layer_groups_are_merged = function()
    -- mirrors space-platform-hub: graphics_set.picture = array of { render_layer, layers = { util.sprite_load output } }
    local function sl(name, extra)
      local t = { filename = "__sa__/" .. name .. ".png", width = 10, height = 12, shift = { 0, -1 }, scale = 0.5,
                  line_length = 1, frames = { { x = 0, y = 0 } } }
      for k, v in pairs(extra or {}) do t[k] = v end
      return t
    end
    local p = { type = "space-platform-hub", name = "hub", graphics_set = { picture = {
      { render_layer = "lower-object-above-shadow", layers = { sl("0-A"), sl("0-B") } },
      { render_layer = "lower-object-overlay", layers = { sl("1-A") } },
      { render_layer = "object", layers = { sl("3"), sl("shadow", { draw_as_shadow = true }),
          sl("emission", { draw_as_glow = true, blend_mode = "additive" }) } },
      { render_layer = "cargo-hatch", layers = { sl("lower-hatch") } },
    } } }
    local all = pictures.find_layers(p)
    local names = {}
    for i, l in ipairs(all) do names[i] = l.filename:match("([^/]+)%.png$") end
    assert_eq(table.concat(names, ","), "0-A,0-B,1-A,3,lower-hatch")
    assert_eq(all[1].scale, 0.5)
  end,
  glow_and_light_skipped = function()
    local p = { picture = { layers = { { filename = "g.png", width = 1, height = 1, draw_as_glow = true }, { filename = "l.png", width = 1, height = 1, draw_as_light = true } } } }
    assert_eq(pictures.find_layer(p), nil)
  end,
  nested_graphics_set_idle = function()
    local p = { graphics_set = { idle_animation = { layers = { { filename = "i.png", width = 4, height = 4 } } } } }
    assert_eq(pictures.find_layer(p).filename, "i.png")
  end,
  garbage_does_not_crash = function()
    assert_eq(pictures.find_layer({ picture = "oops" }), nil)
    assert_eq(pictures.find_layer({ picture = { filename = 5 } }), nil)
    assert_eq(pictures.find_layer({}), nil)
  end,
}
