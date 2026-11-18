local geom = require("scripts.geom")
local transfer = require("scripts.transfer")

return {
  min_zoom_is_threshold_over_biggest_scale = function()
    assert_near(transfer.min_zoom(), transfer.THRESHOLD / (geom.SCALE * geom.SCALE_MAX), 1e-12)
    -- the smallest ship (k 0.85) needs more zoom than the biggest
    assert(transfer.THRESHOLD / transfer.ship_scale(geom.SCALE_MIN) > transfer.min_zoom())
  end,

  trigger_condition = function()
    local S = transfer.ship_scale(1) -- 0.16
    assert(not transfer.triggered(2.4, S)) -- 0.384
    assert(transfer.triggered(transfer.THRESHOLD / S, S)) -- exactly the threshold
    assert(transfer.triggered(3, S)) -- the engine's closest zoom reaches it for every ship size
    assert(not transfer.triggered(transfer.THRESHOLD / S - 0.01, S))
    assert(transfer.triggered(3, transfer.ship_scale(geom.SCALE_MIN)), "closest zoom must reach the smallest ship")
  end,

  ship_point_inverse_of_drawing = function()
    -- drawing: world = anchor + (model - 0) * S, model unit = tile relative to the centroid; here with centroid c
    local c, anchor, S = {x = 10.5, y = -3.25}, {x = 40.2, y = 7.9}, 0.16 * 1.07
    for _, m in ipairs{{0, 0}, {5, -2}, {-7.5, 4.25}} do
      local world = {x = anchor.x + m[1] * S, y = anchor.y + m[2] * S}
      local x, y = transfer.ship_point(world, anchor, c, S)
      assert_near(x, c.x + m[1], 1e-9, "x")
      assert_near(y, c.y + m[2], 1e-9, "y")
    end
    -- the anchor itself is the centroid
    local x, y = transfer.ship_point(anchor, anchor, c, S)
    assert_near(x, c.x, 1e-12); assert_near(y, c.y, 1e-12)
  end,

  offsets_move_the_anchor_not_the_mapping = function()
    -- idle float / parallax move the anchor; the same world point maps to a point shifted by -shift / S
    local c, S = {x = 0, y = 0}, 0.16
    local cam = {x = 100, y = 100}
    local x0, y0 = transfer.ship_point(cam, {x = 100, y = 100}, c, S)
    local x1, y1 = transfer.ship_point(cam, {x = 100.4, y = 99.8}, c, S)
    assert_near(x1 - x0, -0.4 / S, 1e-9); assert_near(y1 - y0, 0.2 / S, 1e-9)
  end,

  bbox_and_inside = function()
    assert_eq(transfer.bbox({}), nil)
    local bb = transfer.bbox({{x = -3, y = -2, w = 4, h = 2}, {x = 0, y = 0, w = 5, h = 6}})
    assert_eq(bb.x0, -3); assert_eq(bb.y0, -2); assert_eq(bb.x1, 5); assert_eq(bb.y1, 6)
    assert(transfer.inside(0, 0, bb)); assert(transfer.inside(5, 6, bb))
    assert(not transfer.inside(5.01, 0, bb)); assert(not transfer.inside(0, -2.5, bb))
  end,

  scale_keeps_picture = function()
    -- zoom after = zoom * S: a tile of the real platform is drawn as big as a tile of the ship was
    local z, S = 3.4, 0.16 * 0.9
    assert_near((z * S) / 1, z * S, 1e-12)
    assert(transfer.triggered(z, S) == (z * S >= transfer.THRESHOLD))
  end,
}
