-- Zoom transfer (0.4.6): zoom into a parked background ship until it is about as big as a real platform and the
-- player is switched to remote view of THAT platform at the matching spot, zoom scaled so the picture barely changes.
-- Pure math at the top (no game globals, unit tested); the live part reads storage.views / models only.
local geom = require("scripts.geom")

local transfer = {}

-- zoom * ship scale at which the transfer fires = how big a real platform would be drawn at the zoom after the switch.
-- 0.4, not 0.5: the engine's closest zoom is 3 (measured: zoom_limits.closest = 3, writes above it are clamped), and
-- 3 * 0.16 = 0.48, so 0.5 would never fire for ships with a size factor k < 1.04.
transfer.THRESHOLD = 0.4
transfer.PERIOD = 10 -- ticks between checks (control.lua on_nth_tick)

-- Smallest player zoom at which ANY ship can trigger (biggest possible ship scale): below it nothing is looked at.
function transfer.min_zoom() return transfer.THRESHOLD / (geom.SCALE * geom.SCALE_MAX) end

-- A ship's total drawing scale: base SCALE times its size factor k.
function transfer.ship_scale(k) return geom.SCALE * (k or 1) end

function transfer.triggered(zoom, S) return zoom * S >= transfer.THRESHOLD end

-- Ship-space point under world point `cam`: the anchor sits at the model centre (model units = tiles of the real
-- platform, relative to its tile centroid) and every sprite offset is model * S, so the inverse is
-- (cam - anchor position) / S + centroid. `anchor` is where the ship is drawn NOW (idle float and camera parallax
-- are already in it: they are teleports of the anchor). `centre` = the platform's tile centroid ({x, y}).
function transfer.ship_point(cam, anchor, centre, S)
  return centre.x + (cam.x - anchor.x) / S, centre.y + (cam.y - anchor.y) / S
end

-- Model-unit bounding box {x0, y0, x1, y1} of a model's floor rects (relative to the model centre), or nil.
function transfer.bbox(rects)
  local x0, y0, x1, y1
  for _, r in ipairs(rects or {}) do
    if not x0 or r.x < x0 then x0 = r.x end
    if not y0 or r.y < y0 then y0 = r.y end
    if not x1 or r.x + r.w > x1 then x1 = r.x + r.w end
    if not y1 or r.y + r.h > y1 then y1 = r.y + r.h end
  end
  return x0 and {x0 = x0, y0 = y0, x1 = x1, y1 = y1} or nil
end

-- Is the model-unit offset (dx, dy) from the centroid inside the box?
function transfer.inside(dx, dy, bb) return dx >= bb.x0 and dx <= bb.x1 and dy >= bb.y0 and dy <= bb.y1 end

-- The ship under the camera: view = storage.views[pi]; cam = {x, y}; zoom. Returns idx, ship, point {x, y}, S or nil.
-- Parked and fully drawn only (no animation, no pending fill), valid anchor, model known.
function transfer.pick(view, cam, zoom)
  for idx, ship in pairs(view.ships) do
    local S = transfer.ship_scale(ship.k)
    if not ship.anim and not ship.entry and ship.anchor and ship.anchor.valid and transfer.triggered(zoom, S) then
      local m = storage.models[idx]
      if m and m.centre then
        if not (ship.bb and ship.bb_tick == m.tick) then ship.bb = transfer.bbox(m.rects); ship.bb_tick = m.tick end
        if ship.bb then
          local px, py = transfer.ship_point(cam, ship.anchor.position, {x = 0, y = 0}, S)
          if transfer.inside(px, py, ship.bb) then
            return idx, ship, {x = m.centre.x + px, y = m.centre.y + py}, S
          end
        end
      end
    end
  end
end

local function wanted(player)
  local s = settings.get_player_settings(player)["fleet-view-zoom-transfer"]
  return s == nil or s.value
end

-- render_mode: chart (the zoomed-out map) is skipped; game (1, headless) and chart_zoomed_in (3: measured in a GUI run
-- for a remote-view player at zoom 3, the real world is drawn) are fine.
-- Checks every viewer; returns the number of transfers made. Nothing but a table lookup unless somebody has a view,
-- and one `zoom` read per viewer until the zoom is above min_zoom(). The switches happen after the scan: they raise
-- surface events that redraw (and so change storage.views).
function transfer.run()
  -- Multiplayer OK since 0.4.7: player.zoom is synced game state (local MP test 2026-11-12, owner zoomed in/out and transferred
  -- repeatedly: no desync; a client-only value would have made server and client disagree on the switch).
  if next(storage.views) == nil then return 0 end
  -- Settled zoom only (0.4.8, portal report Maxorio 2026-11-14: "switches to high zoom on second viewing"): the zoom must
  -- equal the one seen at the previous check. Further Zoom's smooth scroll glides player.zoom every tick and drops its
  -- glide only on on_player_controller_changed, which a remote -> remote surface switch does not raise (headless probe
  -- 2026-11-14: only on_player_changed_surface fires), so a switch mid-glide was zoomed straight back in on the new
  -- platform. Also keeps the rest of a fast vanilla scroll burst from landing on the new platform.
  local seen = storage.zoom_seen
  if not seen then seen = {}; storage.zoom_seen = seen end
  local floor, todo = transfer.min_zoom(), nil
  for pi, view in pairs(storage.views) do
    local player = game.get_player(pi)
    local zoom = player and player.valid and player.zoom
    local settled = false
    if zoom and zoom >= floor then
      settled = seen[pi] == zoom
      seen[pi] = zoom
    else
      seen[pi] = nil
    end
    if settled and player.surface.index == view.surface_index
      and player.render_mode ~= defines.render_mode.chart and wanted(player) then
      local idx, _, pos, S = transfer.pick(view, player.position, zoom)
      local platform = idx and player.force.platforms[idx]
      local surface = platform and platform.valid and platform.surface
      if surface and surface.valid then
        todo = todo or {}
        todo[#todo + 1] = {player = player, surface = surface, pos = pos, zoom = zoom * S}
      end
    end
  end
  if not todo then return 0 end
  for _, t in ipairs(todo) do
    t.player.set_controller{type = defines.controllers.remote, surface = t.surface, position = t.pos}
    t.player.zoom = t.zoom
    seen[t.player.index] = nil
  end
  return #todo
end

return transfer
