-- Scripted checks for Fleet View (headless --benchmark; no connected players, so everything is
-- driven through the `fleet-view` remote interface). Logs "fleet-view checks: all passed" or the failures.
local failures = {}
local geom = require("__fleet-view__.scripts.geom")
-- objects one iron chest adds to a ship: its sprite plus its shadow sprite (0.4.7) when the prototype has one
local function chest_objects()
  return 1 + (helpers.is_valid_sprite_path("fv-e-iron-chest-sh") and 1 or 0)
end
local function check(cond, msg) if not cond then failures[#failures + 1] = msg; log("FV-CHECK FAIL: " .. msg) end end
local function fv() return remote.call("fleet-view", "stats") end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function ship_objects(stats, pi, platform_index)
  local v = stats.views[pi]; return v and v.ships[platform_index] and v.ships[platform_index].objects or 0
end

local P  -- player
local transfer_step
local plat = {}  -- by surface name


-- Arrive / leave. Platforms are moved by writing platform.space_location (the fixture platforms have no
-- fuel, so a real departure is impossible); the mod is told through the `platforms_changed` remote, which
-- runs the same handler as on_space_platform_changed_state.
local function ship(pi, idx) local v = fv().views[pi]; return v and v.ships[idx] end
local function move3(loc)
  plat["platform-3"].space_location = loc
  local pl = plat["platform-3"]
  log("FV-CHECK move3 " .. loc .. " -> loc=" .. (pl.space_location and pl.space_location.name or "nil") .. " state=" .. tostring(pl.state))
  remote.call("fleet-view", "platforms_changed")
end
local function move1(loc)
  plat["platform-1"].space_location = loc
  remote.call("fleet-view", "platforms_changed")
end
local function move2(loc) -- the VIEWER's platform
  plat["platform-2"].space_location = loc
  remote.call("fleet-view", "platforms_changed")
end
local function kof(idx) local L = fv().layouts[plat["platform-2"].index]; return L and L.ships[idx] and L.ships[idx].k end
local function none_animating(msg) check(fv().animating == 0, msg .. ": no ship left animating (" .. fv().animating .. ")") end

-- Travel checks. Ships fly forward = up the screen: side -1 = ahead of the spot (leaving), 1 = behind it (arriving),
-- screen-y offset = side * 150 * p * (n / 180)^2 (p = 1 + 2 * (k - 1): parallax by the ship's size factor k; 150 = DRIFT tiles, 180 = ANIM_TICKS, eased with f^2), x never changes.
-- The expected values are computed HERE on purpose, not through the mod's geom (that would check the mod against
-- itself). Entity positions are fixed-point (1/256 tile), hence the tolerance. `sh` = a ship record from stats()
-- (anchor = its current position, base = its spot = where it sits when parked, anim = {n, dir, side} or nil).
local TOL = 0.01
local function check_curve(sh, side, msg)
  if not (sh and sh.anim and sh.anchor and sh.base and sh.k) then check(false, msg .. ": ship, anim, anchor, spot and size factor exist"); return end
  local dx, dy, want = sh.anchor.x - sh.base.x, sh.anchor.y - sh.base.y, side * 150 * (1 + 2 * (sh.k - 1)) * (sh.anim.n / 180) ^ 2
  check(math.abs(dx) < TOL, msg .. ": x unchanged vs the spot (dx " .. dx .. ")")
  check(math.abs(dy - want) < TOL, msg .. ": y on the eased curve (n=" .. sh.anim.n .. " dy " .. dy .. " want " .. want .. ")")
end
local function check_on_spot(sh, msg)
  if not (sh and sh.anchor and sh.base) then check(false, msg .. ": ship, anchor and spot exist"); return end
  local dx, dy = sh.anchor.x - sh.base.x, sh.anchor.y - sh.base.y
  check(math.abs(dx) < TOL and math.abs(dy) < TOL, msg .. ": anchor exactly on its spot (dx " .. dx .. " dy " .. dy .. ")")
end
-- Fade and scale stay LINEAR in f = n / 180 (only the travel is eased): scale = parked * (1 - 0.47 f) (0.47 = 1 - MIN_SCALE),
-- alpha = parked * min(1, (1 - f) / 0.1) (no fade until the last tenth). Hard-coded here like in check_curve. `xs0` / `a0` = the parked x_scale / alpha of the ship's
-- first object (a floor piece); n and the object come from the same stats() record, so they are the same frame. A looser
-- bound would let an eased fade (smoothstep, ease-out) through.
local FRAME_TOL = 1e-4
local function check_frame(sh, xs0, a0, msg)
  if not (sh and sh.anim and sh.first) then check(false, msg .. ": ship, anim and first object exist"); return end
  local f = sh.anim.n / 180
  local want_xs, want_a = xs0 * (1 - 0.47 * f), a0 * math.min(1, (1 - f) / 0.1)
  local dxs, da = sh.first.x_scale - want_xs, sh.first.a - want_a
  log("FV-CHECK frame " .. msg .. ": n=" .. sh.anim.n .. " scale err " .. dxs / xs0 .. " (relative) alpha err " .. da)
  check(math.abs(dxs) < FRAME_TOL * xs0, msg .. ": scale linear in f (n=" .. sh.anim.n .. " got " .. sh.first.x_scale .. " want " .. want_xs .. ")")
  check(math.abs(da) < FRAME_TOL, msg .. ": alpha full until the last tenth, then linear (n=" .. sh.anim.n .. " got " .. sh.first.a .. " want " .. want_a .. ")")
end

-- Continuous tracker for platform-3's ship over the leave / arrive / reversed arrival / flip / deferred windows (ticks
-- 29..704, until the viewer-leaves section). Every tick the ship record exists its anchor and anim are remembered.
-- Between two consecutive ticks the anchor must not jump (|dx| < 0.01, |dy| <= 2.2: the fastest eased step is 2*150*1.3*f/180,
-- about 2.17 tiles per tick) and must move the way its side and direction say (dy has the sign of side*dir; none while
-- parked). The record is missing while the ship is gone, which resets the tracker (a new arrival rolls a new spot, so no
-- pair spans it). The step that ends at a tick belongs to that tick's anim (a flip lands in anim_steps, after the sample),
-- or to the previous tick's when the animation just ended. One failure per rule, naming its worst tick.
local TRACK_FROM, TRACK_TO = 29, 704
local function track3(tick)
  local T = storage.trk
  if not T then T = {compared = 0, moved = 0, max_dx = 0, max_dy = 0}; storage.trk = T end
  local sh = ship(P.index, storage.idx[3])
  if not (sh and sh.anchor) then T.prev = nil; return end
  local cur, prev = {x = sh.anchor.x, y = sh.anchor.y, anim = sh.anim}, T.prev
  T.prev = cur
  if not prev then return end
  local dx, dy = cur.x - prev.x, cur.y - prev.y
  T.compared = T.compared + 1
  if dy ~= 0 then T.moved = T.moved + 1 end
  T.max_dx, T.max_dy = math.max(T.max_dx, math.abs(dx)), math.max(T.max_dy, math.abs(dy))
  -- rule 1: no jump
  local jump = math.max(math.abs(dx) / 0.01, math.abs(dy) / 2.2)
  if (math.abs(dx) >= 0.01 or math.abs(dy) > 2.2) and (not T.jump or jump > T.jump.v) then
    T.jump = {v = jump, tick = tick, dx = dx, dy = dy}
  end
  -- rule 2: direction (a parked ship does not move at all)
  local a = cur.anim or prev.anim
  local bad = a and -(a.side * a.dir * dy) or math.abs(dy)
  if bad > 1e-6 and (not T.dir or bad > T.dir.v) then
    T.dir = {v = bad, tick = tick, dy = dy, side = a and a.side, dir = a and a.dir}
  end
end
local function track3_report()
  local T = storage.trk or {compared = 0, moved = 0, max_dx = 0, max_dy = 0}
  log("FV-CHECK tracker: " .. T.compared .. " tick pairs compared, " .. T.moved .. " with movement, max step dx "
    .. T.max_dx .. " dy " .. T.max_dy)
  check(T.compared > 600, "tracker: ran over enough tick pairs (" .. T.compared .. ")")
  check(T.moved > 300, "tracker: the ship was seen moving on enough tick pairs (" .. T.moved .. ")")
  check(not T.jump, T.jump and ("tracker: the anchor jumped between consecutive ticks, worst at tick " .. T.jump.tick
    .. " (dx " .. T.jump.dx .. " dy " .. T.jump.dy .. ")") or "")
  check(not T.dir, T.dir and ("tracker: the anchor moved against its side/dir (or while parked), worst at tick " .. T.dir.tick
    .. " (dy " .. T.dir.dy .. " side " .. tostring(T.dir.side) .. " dir " .. tostring(T.dir.dir) .. ")") or "")
end

local anim_steps = {
  [29] = function()
    storage.full3 = ship_objects(fv(), P.index, storage.idx[3])
    storage.full_all = fv().objects
    storage.a3_slot = ship(P.index, storage.idx[3]).anchor
    move3("vulcanus")
  end,
  [33] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.objects == storage.full3, "leave: ship still drawn mid-animation")
    check(sh and sh.anim and sh.anim.dir == 1, "leave: animating outward")
    check(sh and sh.first and sh.first.x_scale < storage.base_xs3, "leave: probe present")
    check(fv().animating == 1, "leave: exactly one ship animating")
  end,
  [100] = function()
    local sh = ship(P.index, storage.idx[3])
    local a0 = storage.a3_slot
    check(sh and sh.anim and sh.anim.n > 50 and sh.anim.n < 80, "leave: halfway (n=" .. tostring(sh and sh.anim and sh.anim.n) .. ")")
    if sh then
      -- forward = up the screen: the spot is where it was parked, x stays, y rises above the spot along the eased curve
      check(sh.base and math.abs(sh.base.x - a0.x) < TOL and math.abs(sh.base.y - a0.y) < TOL, "leave: the spot is where the ship was parked")
      check(sh.anim and sh.anim.side == -1, "leave: flies on ahead (side -1)")
      check(sh.base and math.abs(sh.anchor.x - sh.base.x) < TOL, "leave: x unchanged vs the spot")
      check(sh.base and sh.anchor.y < sh.base.y - 1, "leave: y above the spot, smaller (" .. (sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
      check_curve(sh, -1, "leave")
      check(sh.first.x_scale < storage.base_xs3 * 0.9 and sh.first.x_scale > storage.base_xs3 * 0.53, "leave: scale shrinking")
      check(sh.first.a == storage.base_a3, "leave: still fully visible mid-trip, no fade (" .. sh.first.a .. ")")
      check_frame(sh, storage.base_xs3, storage.base_a3, "leave")
    end
    check(ship_objects(fv(), P.index, storage.idx[1]) > 0, "leave: other ship untouched")
  end,
  [220] = function()
    local s = fv()
    check(ship_objects(s, P.index, storage.idx[3]) == 0, "left: no objects for platform-3 after 190 ticks")
    check(s.anchors == 1, "left: no anchor remains for platform-3 (anchors=" .. s.anchors .. ")")
    check(s.views[P.index] and s.views[P.index].ships[storage.idx[3]] == nil, "left: ship record gone")
    none_animating("left")
    check(s.objects < storage.full_all and s.objects > 0, "left: objects only from platform-1")
  end,
  [225] = function() move3("nauvis") end,
  [229] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.objects == storage.full3, "arrive: all objects created")
    check(sh and sh.anim and sh.anim.dir == -1, "arrive: animating inward")
    check(sh and sh.first.a < 0.2, "arrive: starts faint")
    check(fv().anchors == 2, "arrive: anchor created")
    -- comes up from behind: x on the NEW spot, y well below it, on the eased curve
    check(sh and sh.anim and sh.anim.side == 1, "arrive: comes up from behind (side 1)")
    check(sh and sh.base and sh.anchor.y > sh.base.y + 30, "arrive: starts well below its spot (" .. (sh and sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
    check_curve(sh, 1, "arrive start")
  end,
  [300] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim and sh.anim.n > 90 and sh.anim.n < 130, "arrive: halfway (n=" .. tostring(sh and sh.anim and sh.anim.n) .. ")")
    check_curve(sh, 1, "arrive halfway")
    -- the arrival rolled a new size factor, so the parked scale is the first draw's scaled by the new factor
    check_frame(sh, storage.base_xs3 / storage.k3_first * kof(storage.idx[3]), storage.base_a3, "arrive halfway")
    -- the platform leaves again while its arrival is under way (arriving -> leaving, the other direction of the flip, and
    -- the production path begin_anim(..., 1) on a ship whose dir is -1)
    move3("vulcanus")
  end,
  [302] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim and sh.anim.dir == 1, "arrive reversed: leaving again (n=" .. tostring(sh and sh.anim and sh.anim.n) .. ")")
    -- it was arriving, so it keeps its side (behind, 1) and retraces its path: still below the spot, on the same curve
    check(sh and sh.anim and sh.anim.side == 1, "arrive reversed: keeps its side (still behind, 1)")
    check(sh and sh.base and sh.anchor.y > sh.base.y + 1, "arrive reversed: the anchor is still below the spot (" .. (sh and sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
    check_curve(sh, 1, "arrive reversed")
    check_frame(sh, storage.base_xs3 / storage.k3_first * kof(storage.idx[3]), storage.base_a3, "arrive reversed")
    move3("nauvis") -- and back in: the arrival finishes on the same spot, before [420]
  end,
  [420] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim == nil, "arrived: animation finished")
    local k3 = kof(storage.idx[3])
    check(k3 and k3 >= 0.85 and k3 <= 1.15, "arrived: scale factor in range")
    check(sh and k3 and math.abs(sh.first.x_scale / k3 - storage.base_xs3 / storage.k3_first) < 1e-6 and sh.first.a == storage.base_a3, "arrived: scale (per its new factor) and alpha back to base")
    local a0, a1 = storage.a3_slot, sh and sh.anchor
    check(a1 and math.abs(a1.x - a0.x) + math.abs(a1.y - a0.y) > 0.05, "arrived: a new arrival re-rolled its spot (moved " .. (a1 and (math.abs(a1.x - a0.x) + math.abs(a1.y - a0.y)) or -1) .. ")")
    check(fv().objects == storage.full_all and fv().anchors == 2, "arrived: same counts as before")
    check_on_spot(sh, "arrived")
    none_animating("arrived")
  end,
  -- state flips mid-animation: leave, then come back after 60 ticks
  [425] = function() move3("vulcanus") end,
  [485] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim and sh.anim.dir == 1 and sh.anim.n > 50, "flip: leaving at n>50")
    move3("nauvis")
  end,
  [487] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim and sh.anim.dir == -1 and sh.anim.n > 50, "flip: reversed from where it was (n=" .. tostring(sh and sh.anim and sh.anim.n) .. ")")
    check(fv().anchors == 2, "flip: still exactly 2 anchors")
    -- it was leaving, so it keeps its side (ahead, -1) and retraces its path: still above the spot, on the same curve
    check(sh and sh.anim and sh.anim.side == -1, "flip: keeps its side (still ahead, -1)")
    check(sh and sh.base and sh.anchor.y < sh.base.y - 1, "flip: the anchor is still above the spot (" .. (sh and sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
    check_curve(sh, -1, "flip")
    check_frame(sh, storage.base_xs3 / storage.k3_first * kof(storage.idx[3]), storage.base_a3, "flip")
  end,
  [680] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim == nil and fv().objects == storage.full_all and fv().anchors == 2, "flip: ended fully arrived, no doubles")
    check_on_spot(sh, "flip end")
    none_animating("flip")
  end,
  -- Event before the change takes effect: the state handler runs while the platform still looks the old
  -- way, and the change lands afterwards with no event (platform.hidden stands in; writing space_location
  -- raises the real event itself, with the new location already set). The one deferred reconcile catches up.
  [681] = function()
    remote.call("fleet-view", "platforms_changed")
    plat["platform-3"].hidden = true
    check(fv().animating == 0, "deferred: nothing animating right after the event")
    check(fv().pending ~= nil, "deferred: one reconcile is scheduled")
  end,
  [688] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim and sh.anim.dir == 1, "deferred: reconcile ran later and the ship animates out")
    check(fv().pending == nil, "deferred: pending cleared after it ran")
  end,
  [689] = function()
    remote.call("fleet-view", "platforms_changed")
    plat["platform-3"].hidden = false
  end,
  [704] = function()
    local sh = ship(P.index, storage.idx[3])
    check(sh and sh.anim == nil and fv().objects == storage.full_all and fv().anchors == 2, "deferred: came back and ended arrived")
    check_on_spot(sh, "deferred end")
    none_animating("deferred")
    check(fv().pending == nil, "deferred: nothing pending when idle")
  end,
  -- viewer leaves the surface mid-animation
  [705] = function() move3("vulcanus") end,
  [745] = function()
    check(fv().animating == 1, "viewer-leaves: animating before leaving")
    P.teleport({0, 0}, game.surfaces["nauvis"])
  end,
  [748] = function()
    local s = fv()
    check(s.objects == 0 and s.anchors == 0 and count(s.views) == 0, "viewer-leaves mid-animation: 0 objects, 0 anchors, no view")
    none_animating("viewer-leaves")
  end,
  [750] = function()
    -- platform-3 comes back while nobody watches; the viewer returns: instant full draw
    plat["platform-3"].space_location = "nauvis"
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)
  end,
  [753] = function()
    check(fv().objects == storage.full_all and fv().anchors == 2, "viewer returned: both ships drawn")
  end,
  -- slots: platform-1 leaves and comes back while platform-3 stays; no overlap, same slot as before
  [760] = function()
    storage.a1_slot = ship(P.index, storage.idx[1]).anchor
    storage.a3_slot = ship(P.index, storage.idx[3]).anchor
    check(math.abs(storage.a1_slot.x - storage.a3_slot.x) + math.abs(storage.a1_slot.y - storage.a3_slot.y) > 4, "slots: two ships start apart")
    move1("vulcanus")
  end,
  [945] = function()
    local s = fv()
    check(ship_objects(s, P.index, storage.idx[1]) == 0 and s.anchors == 1, "slots: platform-1 gone, platform-3 stays (anchors=" .. s.anchors .. ")")
    local a3 = ship(P.index, storage.idx[3]).anchor
    check(a3.x == storage.a3_slot.x and a3.y == storage.a3_slot.y, "slots: stayer did not move")
    move1("nauvis")
  end,
  [950] = function()
    -- the arrival is still travelling (its anchor is far below its spot): the spots are what keep their distance
    local a1, a3 = ship(P.index, storage.idx[1]).base, ship(P.index, storage.idx[3]).base
    local d = math.sqrt((a1.x - a3.x) ^ 2 + (a1.y - a3.y) ^ 2)
    check(d > 4, "slots: arrival keeps its distance from the stayer (" .. d .. ")")
  end,
  [1140] = function()
    local a1 = ship(P.index, storage.idx[1]).anchor
    check(math.abs(a1.x - storage.a1_slot.x) + math.abs(a1.y - storage.a1_slot.y) > 0.05, "slots: arrival re-rolled its spot")
    check(fv().objects == storage.full_all and fv().anchors == 2 and fv().animating == 0, "slots: all arrived")
    check_on_spot(ship(P.index, storage.idx[1]), "slots: arrived")
    move3("vulcanus")
  end,
  -- platform deleted mid-animation
  [1180] = function()
    check(fv().animating == 1, "delete: animating before delete")
    game.delete_surface(game.surfaces["platform-3"])
  end,
  [1185] = function()
    local s = fv()
    check(ship_objects(s, P.index, storage.idx[3]) == 0 and s.anchors == 1, "deleted mid-animation: no objects, 1 anchor left (" .. s.anchors .. ")")
    none_animating("deleted")
  end,
  -- The VIEWER's platform moves (portal feedback 2026-10-25): parked ships fall behind (down the screen, side 1) when
  -- it leaves, like the planet, and come in from ahead (above, side -1) when it arrives.
  [2030] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "viewer-moves: platform-1 parked before the viewer leaves")
    move2("vulcanus")
  end,
  [2035] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim and sh.anim.dir == 1, "viewer departs: the parked ship animates out")
    check(sh and sh.anim and sh.anim.side == 1, "viewer departs: the parked ship falls behind (side 1)")
  end,
  [2110] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.base and sh.anchor.y > sh.base.y + 1, "viewer departs: the ship is below its spot (" .. (sh and sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
    check_curve(sh, 1, "viewer departs")
  end,
  [2220] = function()
    check(fv().anchors == 0 and fv().animating == 0, "viewer departed: ship gone")
    move2("nauvis")
  end,
  [2225] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim and sh.anim.dir == -1, "viewer arrives: the parked ship animates in")
    check(sh and sh.anim and sh.anim.side == -1, "viewer arrives: the ship comes in from ahead (side -1)")
    check(sh and sh.base and sh.anchor.y < sh.base.y - 30, "viewer arrives: starts well above its spot (" .. (sh and sh.base and (sh.anchor.y - sh.base.y) or "?") .. ")")
    check_curve(sh, -1, "viewer arrives")
  end,
  [2420] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "viewer arrived: animation finished")
    check_on_spot(sh, "viewer arrived")
    -- another ship leaving is unchanged by all this: it still flies on ahead
    move1("vulcanus")
  end,
  [2425] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim and sh.anim.side == -1, "after the viewer moved: another ship leaving still flies ahead (side -1)")
    move1("nauvis")
  end,
  -- Pace (2026-10-25: measured planet curve, offset = 2.875e-5 * km^2 tiles): anim.n per tick = the moving platform's
  -- speed (km/tick) * 180 / sqrt(150 / 2.875e-5), clamped to 0.375..0.6 (5-8 s). Expected values computed here, not via the mod.
  [2620] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "pace: platform-1 parked before the pace checks")
    remote.call("fleet-view", "set_min_step", nil)
    move1("vulcanus") -- teleported, speed 0: the slowest pace
  end,
  [2622] = function() storage.pace_n0 = ship(P.index, storage.idx[1]).anim.n end,
  [2632] = function()
    local sh = ship(P.index, storage.idx[1])
    local d = sh and sh.anim and (sh.anim.n - storage.pace_n0)
    check(d and math.abs(d - 3.75) < 1e-9, "pace: a ship at speed 0 moves at the slowest pace, 0.375/tick (10 ticks: " .. tostring(d) .. ")")
    check(sh and sh.anim and sh.anim.mover == storage.idx[1], "pace: the leaving ship is its own mover")
    move1("nauvis") -- straight back: the flip retraces at the same pace
  end,
  [2660] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "pace: flipped back and parked")
    check_on_spot(sh, "pace: flip end")
    -- the VIEWER's platform really travels (schedule + held speed): the parked ship falls behind at the planet's pace
    local p2 = plat["platform-2"]
    p2.schedule = {current = 1, records = {{station = "vulcanus", wait_conditions = {}}}}
    p2.paused = false
    storage.hold = 3 -- 3 km/tick -> 0.458/tick, inside the clamp
    storage.pace = {err = 0, n = 0}
  end,
  [3000] = function()
    local pc = storage.pace
    log("FV-CHECK pace: " .. pc.n .. " steps compared, worst error " .. pc.err .. ", clamped-max steps " .. (pc.top or 0))
    check(pc.n > 40, "pace: enough steps compared (" .. pc.n .. ")")
    check(pc.err < 1e-6, "pace: each step = the mover's speed * 180 / sqrt(150 / 2.875e-5), clamped (worst error " .. pc.err .. ")")
    check((pc.top or 0) > 5, "pace: a fast mover is clamped to 0.6/tick (" .. tostring(pc.top) .. ")")
    check(fv().anchors == 0 and fv().animating == 0, "pace: the ship has left")
    storage.hold, storage.pace = nil, nil
    plat["platform-2"].schedule = nil
    move2("nauvis")
  end,
  [3005] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim and sh.anim.dir == -1 and sh.anim.side == -1, "pace: the viewer arrived, the ship comes in from ahead")
    check(sh and sh.anim and sh.anim.mover == plat["platform-2"].index, "pace: the arriving viewer is the mover")
  end,
  [3010] = function() storage.arr_n0 = ship(P.index, storage.idx[1]).anim.n end,
  [3020] = function()
    -- arrivals ignore the speed (the platform came in at 50 km/tick): always 0.3/tick = 10 s
    local sh = ship(P.index, storage.idx[1])
    local d = sh and sh.anim and (storage.arr_n0 - sh.anim.n)
    check(d and math.abs(d - 3) < 1e-9, "pace: an arrival moves 0.3/tick whatever the speed (10 ticks: " .. tostring(d) .. ")")
  end,
  [3620] = function()
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "pace: arrival done within 10 s")
    check_on_spot(sh, "pace: arrived")
  end,
}

-- Per tick while the viewer's platform travels: hold its speed (3 km/tick, then 50 from tick 2720) and compare each
-- step of platform-1's ship with the expected pace. Fleet View's on_tick runs before this mod's, after the engine
-- moved the platform, so both read the same speed; it is re-set after the read.
local PACE_KM = math.sqrt(150 / 2.875e-5)
local function pace_tick(tick)
  local pc, p2 = storage.pace, plat["platform-2"]
  if not (pc and p2 and p2.valid) then return end
  local sh = ship(P.index, storage.idx[1])
  local n = sh and sh.anim and sh.anim.dir == 1 and sh.anim.n
  if n and pc.last_n and n > pc.last_n then
    local want = math.max(0.375, math.min(0.6, math.abs(p2.speed) * 180 / PACE_KM))
    local e = math.abs((n - pc.last_n) - want)
    if e > pc.err then pc.err = e end
    pc.n = pc.n + 1
    if want == 0.6 then pc.top = (pc.top or 0) + 1 end
  end
  pc.last_n = n or nil
  if tick == 2720 then storage.hold = 50 end
  if not p2.space_location then p2.speed = storage.hold end
end

-- Per tick while the viewer's platform flies in: hold 20 km/tick and compare platform-1's ship with the planet curve
-- for the remaining distance. Runs after Fleet View's on_tick in the same tick, so both read the same distance.
local APPR_KM = math.sqrt(150 / 2.875e-5)
local function appr_tick(tick)
  local A, p2 = storage.appr, plat["platform-2"]
  if p2.space_location then
    if not A.arrived then A.arrived = tick end
    return
  end
  local c = p2.space_connection
  local km = c and p2.distance * c.length
  local sh = ship(P.index, storage.idx[1])
  if km and km >= APPR_KM and sh then A.early = A.early + 1 end
  if km and sh and sh.anim and sh.anim.approach and sh.objects == storage.n1 then
    local want_n = 180 * km / APPR_KM
    A.err = math.max(A.err, math.abs(sh.anim.n - want_n))
    local want_dy = -150 * (1 + 2 * (sh.k - 1)) * (km / APPR_KM) ^ 2
    A.cerr = math.max(A.cerr, math.abs((sh.anchor.y - sh.base.y) - want_dy), math.abs(sh.anchor.x - sh.base.x))
    if sh.anim.side ~= -1 then A.side = A.side + 1 end
    A.n = A.n + 1
  end
  p2.speed = 20
end

-- Zoom transfer (0.4.6): the viewer is put into remote view over platform-1's parked ship (platform-1 is the only other
-- platform at nauvis here). Zoom * S = 0.6 triggers (0.5 is the threshold); the checks run through the real on_nth_tick(10)
-- handler. Expected values are computed here, not through the mod: new position = platform-1's tile centroid +
-- (camera - ship anchor) / S (S = 0.16 * k, the anchor is where the ship is drawn; idle float and parallax are off here),
-- new zoom = zoom * S.
local function centroid(surface)
  local names = {}
  for n, pr in pairs(prototypes.tile) do if pr.is_foundation then names[#names + 1] = n end end
  local sx, sy, c = 0, 0, 0
  for _, t in ipairs(surface.find_tiles_filtered{name = names}) do
    sx = sx + math.floor(t.position.x) + 0.5; sy = sy + math.floor(t.position.y) + 0.5; c = c + 1
  end
  return sx / c, sy / c
end
local function remote_view(surface, pos, zoom)
  P.set_controller{type = defines.controllers.remote, surface = surface, position = pos}
  P.zoom = zoom
end
local function char_view() -- the fixture viewer has no character: remote view of platform-2 again (a surface change)
  remote_view(plat["platform-2"].surface, {x = storage.tr.a.x + 20, y = storage.tr.a.y + 20}, 0.3 / storage.tr.S)
end
transfer_step = function(tick)
  local T = storage.tr
  local p1, p2 = plat["platform-1"], plat["platform-2"]
  if tick == 4176 then
    check(settings.get_player_settings(P)["fleet-view-zoom-transfer"].value == false, "transfer: setting is off by default")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-zoom-transfer", true)   -- opt-in since 0.4.7
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil and sh.anchor, "transfer: platform-1's ship is parked in the viewer's view")
    if not (sh and sh.anchor) then return end
    T = {S = 0.16 * sh.k, a = sh.anchor, k = sh.k, char = P.character, ctrl = P.controller_type}; storage.tr = T
    log("FV-CHECK transfer: viewer controller before = " .. tostring(T.ctrl) .. " char=" .. tostring(T.char ~= nil))
    -- A: zoom * S = 0.3 (< 0.4), camera over the ship
    remote_view(p2.surface, {x = T.a.x + 0.3, y = T.a.y + 0.2}, 0.3 / T.S)
    log(string.format("FV-CHECK transfer: ctrl=%s surface=%s pos=%.3f,%.3f (want %.3f,%.3f) zoom=%.4f render_mode=%s S=%.4f",
      tostring(P.controller_type), P.surface.name, P.position.x, P.position.y, T.a.x + 0.3, T.a.y + 0.2, P.zoom, tostring(P.render_mode), T.S))
    log("FV-CHECK transfer: zoom_limits " .. serpent.line(P.zoom_limits))
    check(P.controller_type == defines.controllers.remote, "transfer: viewer is in remote view")
    check(math.abs(P.position.x - (T.a.x + 0.3)) < 0.01, "transfer: remote position readable (the camera)")
    check(math.abs(P.zoom - 0.3 / T.S) < 1e-3, "transfer: zoom readable/settable in remote view (" .. P.zoom .. ")")
    check(fv().views[P.index].surface_index == p2.surface.index, "transfer: view is on platform-2")
  elseif tick == 4192 then
    check(P.surface.name == "platform-2" and math.abs(P.zoom - 0.3 / T.S) < 1e-3, "transfer: zoom * S 0.3 < threshold: no transfer (" .. P.surface.name .. ")")
    -- B: zoom * S 0.42, camera 60 tiles away from every ship
    remote_view(p2.surface, {x = T.a.x + 60, y = T.a.y + 60}, 0.42 / T.S)
  elseif tick == 4208 then
    check(P.surface.name == "platform-2" and math.abs(P.zoom - 0.42 / T.S) < 1e-3, "transfer: camera not inside a ship: no transfer (" .. P.surface.name .. ")")
    -- C: over the ship, but the setting is off
    remote_view(p2.surface, {x = T.a.x + 0.3, y = T.a.y + 0.2}, 0.42 / T.S)
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-zoom-transfer", false)
  elseif tick == 4224 then
    check(P.surface.name == "platform-2" and math.abs(P.zoom - 0.42 / T.S) < 1e-3, "transfer: setting off: no transfer (" .. P.surface.name .. ")")
    check(fv().views[P.index].surface_index == p2.surface.index, "transfer: setting off: view unchanged")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-zoom-transfer", true)
    T.before = fv().objects
  elseif tick == 4240 then
    -- D: setting on, zoom * S 0.42, camera inside the ship: transferred during the 16 ticks
    local cx, cy = centroid(p1.surface)
    check(P.surface.name == "platform-1", "transfer: now on platform-1 (" .. P.surface.name .. ")")
    check(P.controller_type == defines.controllers.remote, "transfer: still remote view")
    check(math.abs(P.zoom - 0.42) < 1e-3, "transfer: zoom = zoom * S = 0.42 (" .. P.zoom .. ")")
    local wx, wy = cx + 0.3 / T.S, cy + 0.2 / T.S
    log(string.format("FV-CHECK transfer: pos %.3f,%.3f want %.3f,%.3f (centroid %.3f,%.3f)", P.position.x, P.position.y, wx, wy, cx, cy))
    check(math.abs(P.position.x - wx) < 0.02 and math.abs(P.position.y - wy) < 0.02, "transfer: position = centroid + offset / S")
    remote.call("fleet-view", "flush")
    local s = fv()
    local v = s.views[P.index]
    check(v and v.surface_index == p1.surface.index, "transfer: view rebuilt for platform-1")
    local sum, n = 0, 0
    if v then for _, sh in pairs(v.ships) do sum = sum + sh.objects; n = n + 1 end end
    check(n >= 1 and s.anchors == n, "transfer: one anchor per ship, no doubles (" .. s.anchors .. " vs " .. n .. ")")
    check(s.objects == sum, "transfer: no orphan or doubled objects (" .. s.objects .. " vs " .. sum .. ")")
    check(#p2.surface.find_entities_filtered{name = "fv-anchor"} == 0, "transfer: no anchors left on platform-2")
    check(v and v.ships[storage.idx[2]] ~= nil, "transfer: platform-2 is now a ship in the view")
    -- E: back to the character on platform-2
    char_view()
  elseif tick == 4244 then
    check(P.surface.name == "platform-2", "transfer: back on platform-2 (" .. P.surface.name .. ")")
    remote.call("fleet-view", "flush")
    local v = fv().views[P.index]
    check(v and v.surface_index == p2.surface.index and fv().anchors == count(v.ships), "transfer: view back on platform-2, anchors match")
    -- G: camera parallax ON: the ship follows the camera, the camera is re-aimed at its anchor every tick for 40 ticks
    remote.call("fleet-view", "set_no_parallax", nil)
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-parallax", "medium")   -- default is off since 2026-11-12
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-zoom-transfer", false)
  elseif tick > 4244 and tick < 4286 then
    local sh = ship(P.index, storage.idx[1])
    if sh and sh.anchor then remote_view(p2.surface, {x = sh.anchor.x + 0.3, y = sh.anchor.y + 0.2}, 0.42 / T.S) end
  elseif tick == 4286 then
    local sh = ship(P.index, storage.idx[1])
    local cam = {x = sh.anchor.x + 0.3, y = sh.anchor.y + 0.2}
    remote_view(p2.surface, cam, 0.42 / T.S)
    local moved = math.sqrt((sh.anchor.x - sh.base.x) ^ 2 + (sh.anchor.y - sh.base.y) ^ 2)
    log(string.format("FV-CHECK transfer parallax: anchor %.3f,%.3f spot %.3f,%.3f (moved %.3f) camera now %.3f,%.3f", sh.anchor.x, sh.anchor.y, sh.base.x, sh.base.y, moved, P.position.x, P.position.y))
    check(moved > 0.5, "transfer parallax: the ship follows the camera (moved " .. moved .. " tiles)")
    T.cam, T.anc = {x = P.position.x, y = P.position.y}, {x = sh.anchor.x, y = sh.anchor.y}
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-zoom-transfer", true)
    -- 0.4.8: only a settled zoom transfers. A zoom that changed since the last check (a smooth-zoom glide, Further Zoom)
    -- waits; the same zoom at the next check goes. 0.41, not higher: 0.43 / S could clamp at the closest zoom 3.
    P.zoom = 0.41 / T.S
    local n0 = remote.call("fleet-view", "transfer_run")
    check(n0 == 0, "transfer: a zoom that just changed does not transfer yet (" .. tostring(n0) .. ")")
    local n = remote.call("fleet-view", "transfer_run")
    check(n == 1, "transfer parallax: transferred once the zoom held (" .. tostring(n) .. ")")
  elseif tick == 4288 then
    local cx, cy = centroid(p1.surface)
    -- the camera was read back from the player: remote view may clamp a far position, so the mapping uses what it really was
    local wx, wy = cx + (T.cam.x - T.anc.x) / T.S, cy + (T.cam.y - T.anc.y) / T.S
    log(string.format("FV-CHECK transfer parallax: pos %.3f,%.3f want %.3f,%.3f", P.position.x, P.position.y, wx, wy))
    check(P.surface.name == "platform-1", "transfer parallax: now on platform-1 (" .. P.surface.name .. ")")
    check(math.abs(P.position.x - wx) < 0.03 and math.abs(P.position.y - wy) < 0.03, "transfer parallax: position includes the parallax offset")
    remote.call("fleet-view", "set_no_parallax", true)
    char_view()
  elseif tick == 4300 then
    remote.call("fleet-view", "flush")
    check(P.surface.name == "platform-2", "transfer: back on platform-2 again")
    -- F: the ship is mid-animation (leaving): no transfer
    move1("vulcanus")
  elseif tick == 4306 then
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim ~= nil, "transfer: platform-1's ship is animating")
    if sh and sh.anchor then
      remote_view(p2.surface, {x = sh.anchor.x, y = sh.anchor.y}, 0.42 / T.S)
      check(remote.call("fleet-view", "transfer_run") == 0, "transfer: mid-animation ship: nothing to transfer")
    end
  elseif tick == 4322 then
    check(P.surface.name == "platform-2" and math.abs(P.zoom - 0.42 / T.S) < 1e-3, "transfer: mid-animation: no transfer (" .. P.surface.name .. ")")
    char_view()
    move1("nauvis")
  end
end

local function step(tick)
  if storage.track2 and tick >= 1441 then
    local n = ship_objects(fv(), P.index, storage.idx[1])
    if n < storage.track2.min then storage.track2.min = n end
  end
  if storage.track and tick > 1200 and tick < 1215 then storage.track[#storage.track + 1] = fv().objects end
  -- Before the dedicated staging checks (tick 1200+) drawing is completed at once so the older checks keep
  -- their meaning; a few ticks of real staging happen between flushes only where an event just fired.
  if tick < 1200 then remote.call("fleet-view", "flush") end
  -- the tracker samples before anim_steps (which move the ship); its verdict comes the tick after the window
  if tick >= TRACK_FROM and tick <= TRACK_TO then track3(tick) elseif tick == TRACK_TO + 1 then track3_report() end
  if storage.hold then pace_tick(tick) end
  if storage.appr then appr_tick(tick) end
  if anim_steps[tick] then anim_steps[tick]() end
  if tick == 10 then
    -- the fixture platforms move by teleport (speed 0): pin the pace to 1/tick so the older checks keep the
    -- 180-tick timing; the pace section (2620+) restores the real minimum
    remote.call("fleet-view", "set_min_step", 1)
    remote.call("fleet-view", "set_no_idle", true) -- the older checks expect parked ships to sit exactly on their spot
    remote.call("fleet-view", "set_no_parallax", true) -- and the viewer's walking not to move them (parallax check at 3662)
    P = game.get_player("holyskib")
    check(P ~= nil, "player holyskib exists")
    for _, n in ipairs{"platform-1", "platform-2", "platform-3"} do
      local s = game.surfaces[n]; check(s and s.platform, n .. " has a platform"); plat[n] = s and s.platform
    end
    log("FV-CHECK locations: " .. plat["platform-1"].space_location.name .. " " .. plat["platform-2"].space_location.name
      .. " " .. plat["platform-3"].space_location.name .. " player connected=" .. tostring(P.connected)
      .. " char=" .. tostring(P.character ~= nil) .. " surface=" .. P.surface.name)
    local names = {}
    for _, pl in pairs(game.players) do names[#names + 1] = pl.name end
    log("FV-CHECK players: " .. table.concat(names, ","))
    local s0 = fv(); check(s0.anchors == 0 and s0.objects == 0, "nothing drawn before first show")

    -- put the viewer on platform-2
    local hub = plat["platform-2"].hub
    P.teleport({hub.position.x, hub.position.y + 4}, plat["platform-2"].surface)
    check(P.surface.name == "platform-2", "viewer is on platform-2 (" .. P.surface.name .. ")")
    remote.call("fleet-view", "show", P.index)
    remote.call("fleet-view", "flush")
    local s = fv()
    local i1, i2, i3 = plat["platform-1"].index, plat["platform-2"].index, plat["platform-3"].index
    storage.idx = {i1, i2, i3}
    check(ship_objects(s, P.index, i1) > 0, "objects exist for platform-1")
    check(ship_objects(s, P.index, i3) > 0, "objects exist for platform-3")
    check(ship_objects(s, P.index, i2) == 0, "no objects for platform-2 (own)")
    check(s.anchors == 2, "exactly 2 anchors (got " .. s.anchors .. ")")
    storage.objects_after_show = s.objects
    local f3 = s.views[P.index].ships[i3].first
    storage.base_xs3, storage.base_a3 = f3.x_scale, f3.a
    storage.k3_first = kof(i3)
    log("FV-CHECK objects after show: " .. s.objects)
    check(s.objects > 0, "render objects exist")
    -- anchors sit on the viewer's surface
    check(#plat["platform-2"].surface.find_entities_filtered{name = "fv-anchor"} == 2, "anchors are on platform-2's surface")
    check(#plat["platform-1"].surface.find_entities_filtered{name = "fv-anchor"} == 0, "no anchors on other platforms")

    -- Review focus 5 (real setting path): detail off, next tick check
    for _ = 1, 3 do remote.call("fleet-view", "show", P.index) end
    remote.call("fleet-view", "flush")
    local s2 = fv()
    check(s2.objects == s.objects, "refresh x3: object count unchanged (" .. s2.objects .. " vs " .. s.objects .. ")")
    check(s2.anchors == 2, "refresh x3: still 2 anchors")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-detail", false)

  elseif tick == 11 then
    local n, full = fv().objects, storage.objects_after_show
    check(n > 0 and n < full, "detail off via real setting event: fewer objects (" .. n .. " < " .. full .. ")")
    check(fv().anchors == 2, "detail off: 2 anchors")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-detail", true)

  elseif tick == 12 then
    check(fv().objects == storage.objects_after_show, "detail on again: same count as first draw, no doubles")
    check(fv().anchors == 2, "settings toggled: still 2 anchors")
    local v = fv().views[P.index].ships
    storage.fixed = {[storage.idx[1]] = v[storage.idx[1]].anchor, [storage.idx[3]] = v[storage.idx[3]].anchor}
    storage.p0 = {x = P.position.x, y = P.position.y}
    P.teleport({P.position.x + 7, P.position.y + 3}, P.surface)

  elseif tick == 14 then
    local v = fv().views[P.index].ships
    for idx, a0 in pairs(storage.fixed) do
      local a = v[idx].anchor
      check(a.x == a0.x and a.y == a0.y, string.format("fixed: anchor of %d did not move when the viewer moved 7,3 (%.3f,%.3f)", idx, a.x - a0.x, a.y - a0.y))
    end
    P.teleport({P.position.x + 10, P.position.y - 5}, P.surface)

  elseif tick == 17 then
    local v = fv().views[P.index].ships
    for idx, a0 in pairs(storage.fixed) do
      local a = v[idx].anchor
      check(a.x == a0.x and a.y == a0.y, "fixed: anchor of " .. idx .. " still unmoved after the viewer moved another 10,-5")
    end
    check(math.abs(P.position.x - storage.p0.x) > 10, "fixed: the viewer really moved")
    check(fv().objects == storage.objects_after_show, "moving does not change object count")
    -- layout: ships sit outside the deck's tile bounding box (gap 3..12), >= 4 tiles apart, scale 0.85..1.15, shared per viewer platform
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    for _, t in pairs(plat["platform-2"].surface.find_tiles_filtered{name = "space-platform-foundation"}) do
      minx = math.min(minx, t.position.x); maxx = math.max(maxx, t.position.x)
      miny = math.min(miny, t.position.y); maxy = math.max(maxy, t.position.y)
    end
    local dcx, dcy, dhw, dhh = (minx + maxx + 1) / 2, (miny + maxy + 1) / 2, (maxx - minx + 1) / 2, (maxy - miny + 1) / 2
    local L = fv().layouts[plat["platform-2"].index]
    check(L and L.ships[storage.idx[1]] and L.ships[storage.idx[3]], "layout: stored per viewer platform")
    if L then
      for _, idx in ipairs{storage.idx[1], storage.idx[3]} do
        local b = L.ships[idx]
        local gap = math.max(math.abs(b.x - dcx) - (dhw + b.hw), math.abs(b.y - dcy) - (dhh + b.hh))
        check(gap >= 3 - 1e-6 and gap <= 12 + 1e-6, string.format("layout: ship %d gap to the deck box in 3..12 (%.2f)", idx, gap))
        check(b.k >= 0.85 and b.k <= 1.15, "layout: scale factor in range (" .. b.k .. ")")
      end
      local b1, b3 = L.ships[storage.idx[1]], L.ships[storage.idx[3]]
      check(math.abs(b1.x - b3.x) >= b1.hw + b3.hw + 4 - 1e-6 or math.abs(b1.y - b3.y) >= b1.hh + b3.hh + 4 - 1e-6, "layout: ships >= 4 tiles apart")
      check(L.deck and math.abs(L.deck.x - dcx) < 1e-6 and math.abs(L.deck.y - dcy) < 1e-6, "layout: deck centre stored")
      storage.layout_json = serpent.line(L.ships)
    end
    -- history independence (stands in for a second viewer on the platform): a fresh clear + show reproduces the same anchors
    remote.call("fleet-view", "clear", P.index)
    remote.call("fleet-view", "show", P.index)
    local v2 = fv().views[P.index].ships
    for idx, a0 in pairs(storage.fixed) do
      check(v2[idx].anchor.x == a0.x and v2[idx].anchor.y == a0.y, "layout: same anchor after clear + show (" .. idx .. ")")
    end
    check(serpent.line(fv().layouts[plat["platform-2"].index].ships) == storage.layout_json, "layout: spots (incl. scale) persist across a re-draw")
    remote.call("fleet-view", "flush")
    -- two viewers on the same platform (the save has a second player): standing elsewhere on the deck, same anchors
    local Q = game.get_player("Sky--Wolf")
    if Q then
      local hub2 = plat["platform-2"].hub
      Q.teleport({hub2.position.x + 3, hub2.position.y - 2}, plat["platform-2"].surface)
      remote.call("fleet-view", "show", Q.index)
      remote.call("fleet-view", "flush")
      local sq = fv().views[Q.index]
      check(sq and sq.ships[storage.idx[1]] and sq.ships[storage.idx[3]], "two viewers: second viewer sees both ships")
      for idx, a0 in pairs(storage.fixed) do
        local a = sq and sq.ships[idx] and sq.ships[idx].anchor
        check(a and a.x == a0.x and a.y == a0.y, "two viewers: same anchor position for ship " .. idx)
      end
      Q.teleport({0, 0}, game.surfaces["nauvis"])
      remote.call("fleet-view", "clear", Q.index)
      check(fv().views[P.index] ~= nil and fv().anchors == 2, "two viewers: first viewer's ships unaffected by the second leaving")
    else
      check(false, "two viewers: second player Sky--Wolf missing from the save")
    end

  elseif tick == 20 then
    -- Review focus 1: viewer changes surface -> everything goes (on_player_changed_surface)
    P.teleport({0, 0}, game.surfaces["nauvis"])
    check(P.surface.name == "nauvis", "viewer now on nauvis (" .. P.surface.name .. ")")

  elseif tick == 22 then
    local s = fv()
    check(s.objects == 0 and s.anchors == 0 and count(s.views) == 0,
      "after leaving the platform: 0 objects, 0 anchors, no view (objects=" .. s.objects .. " anchors=" .. s.anchors .. ")")
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)

  elseif tick == 24 then
    local s = fv()
    local i1, i3 = storage.idx[1], storage.idx[3]
    check(ship_objects(s, P.index, i1) > 0 and ship_objects(s, P.index, i3) > 0, "arrival noticed by event: ships drawn")
    local hub1 = plat["platform-1"].hub
    P.teleport({hub1.position.x, hub1.position.y + 4}, plat["platform-1"].surface)

  elseif tick == 26 then
    local s = fv()
    local i1, i2, i3 = storage.idx[1], storage.idx[2], storage.idx[3]
    check(ship_objects(s, P.index, i1) == 0, "moved to platform-1: its own ship not drawn")
    check(ship_objects(s, P.index, i2) > 0 and ship_objects(s, P.index, i3) > 0, "moved to platform-1: 2 and 3 drawn")
    check(#plat["platform-2"].surface.find_entities_filtered{name = "fv-anchor"} == 0, "old surface has no anchors left")
    check(s.anchors == 2, "anchors are 2 after switching platforms (" .. s.anchors .. ")")
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)

  elseif tick == 28 then
    check(fv().anchors == 2, "back on platform-2: 2 anchors")
    -- migration from 0.1.0: storage looks like the old version's (depth/follow/slots/last_pos), handler must rebuild cleanly
    remote.call("fleet-view", "simulate_old_storage")
    check(fv().legacy > 0, "migration: old-style storage in place (legacy=" .. fv().legacy .. ")")
    remote.call("fleet-view", "configuration_changed")
    check(fv().objects == 0, "migration: old pictures cleared at once (new ones are staged)")
    remote.call("fleet-view", "flush")
    check(fv().legacy == 0, "migration: no legacy fields left (legacy=" .. fv().legacy .. ")")
    local moved = 0
    for idx, a0 in pairs(storage.fixed) do
      local a = fv().views[P.index].ships[idx].anchor
      if a.x ~= a0.x or a.y ~= a0.y then moved = moved + 1 end
      check(kof(idx) ~= nil, "migration: new spot rolled with a scale factor (" .. idx .. ")")
    end
    check(moved == 2, "migration: spots re-rolled cleanly (" .. moved .. " of 2 ships moved)")
    check(fv().rng, "migration: random generator exists")
    -- mod update: views dropped (as after a version bump), handler must redraw
    remote.call("fleet-view", "clear", P.index)
    check(fv().objects == 0, "cleared")
    remote.call("fleet-view", "configuration_changed")
    remote.call("fleet-view", "flush")
    local s = fv()
    check(s.objects == storage.objects_after_show and s.anchors == 2,
      "configuration_changed redraws (objects=" .. s.objects .. " anchors=" .. s.anchors .. ")")
    -- the migration re-rolled every spot and scale: later checks compare against the new base values
    local f3 = ship(P.index, storage.idx[3]).first
    storage.base_xs3, storage.base_a3, storage.k3_first = f3.x_scale, f3.a, kof(storage.idx[3])

  elseif tick == 1190 then
    -- Review focus 2: platform deleted while drawn (done mid-animation at tick 775)
    check(game.surfaces["platform-3"] == nil, "platform-3 was deleted at tick 1180")

  elseif tick == 1195 then
    local i1, i3 = storage.idx[1], storage.idx[3]
    local s = fv()
    check(game.surfaces["platform-3"] == nil, "platform-3 surface is gone")
    check(ship_objects(s, P.index, i3) == 0, "deleted platform-3: no objects")
    check(ship_objects(s, P.index, i1) > 0, "platform-1 still drawn")
    check(s.anchors == 1, "one anchor left after delete (" .. s.anchors .. ")")

  elseif tick == 1200 then
    -- Staged drawing: a fresh show creates at most 150 objects per tick and completes in ceil(N/150)+2 ticks
    local N = fv().objects
    storage.stage_n = N
    storage.base_xs1 = ship(P.index, storage.idx[1]).first.x_scale
    storage.k1 = kof(storage.idx[1])
    check(N > 300, "staging: ship is big enough to need several ticks (N=" .. N .. ")")
    remote.call("fleet-view", "clear", P.index)
    check(fv().objects == 0 and fv().queued == 0, "staging: cleared")
    remote.call("fleet-view", "show", P.index)
    local s = fv()
    check(s.anchors == 1, "staging: anchor exists right after show (" .. s.anchors .. ")")
    check(s.objects <= 150 and s.queued == 1, "staging: show queues the work (objects=" .. s.objects .. " queued=" .. s.queued .. ")")
    storage.track = {s.objects}

  elseif tick == 1215 then
    local tr, N = storage.track, storage.stage_n
    local prev, maxd, done = 0, 0, nil
    for i, n in ipairs(tr) do
      if n - prev > maxd then maxd = n - prev end
      if n == N and not done then done = i - 1 end
      prev = n
    end
    log("FV-CHECK staging: N=" .. N .. " maxdelta=" .. maxd .. " completed after " .. tostring(done) .. " ticks")
    check(maxd <= 150, "staging: never more than 150 objects per tick (max " .. maxd .. ")")
    check(done and done <= math.ceil(N / 150) + 2, "staging: complete within ceil(N/150)+2 ticks (" .. tostring(done) .. ")")
    check(tr[#tr] == N and fv().queued == 0 and fv().anchors == 1, "staging: finished with same count as instant draw, queue empty")

  elseif tick == 1216 then
    remote.call("fleet-view", "show", P.index)

  elseif tick == 1218 then
    local s = fv()
    check(s.objects > 0 and s.objects < storage.stage_n and s.queued == 1, "cancel: mid-staging (objects=" .. s.objects .. " queued=" .. s.queued .. ")")
    P.teleport({0, 0}, game.surfaces["nauvis"])

  elseif tick == 1221 then
    local s = fv()
    check(s.objects == 0 and s.anchors == 0 and s.queued == 0 and count(s.views) == 0,
      "cancel: viewer left mid-staging: 0 objects, 0 anchors, queue empty (objects=" .. s.objects .. " queued=" .. s.queued .. ")")
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)

  elseif tick == 1230 then
    check(fv().objects == storage.stage_n and fv().anchors == 1 and fv().queued == 0, "cancel: viewer back, ship complete again, no doubles")
    -- arrival that has to be staged: ship hidden while the viewer is away, viewer back, ship appears
    plat["platform-1"].hidden = true
    P.teleport({0, 0}, game.surfaces["nauvis"])

  elseif tick == 1232 then
    check(fv().objects == 0 and fv().anchors == 0, "arrive-staged: nothing drawn while away")
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)

  elseif tick == 1234 then
    check(fv().objects == 0 and fv().anchors == 0, "arrive-staged: viewer back, nothing else parked")
    plat["platform-1"].hidden = false
    remote.call("fleet-view", "platforms_changed")
    local s = fv()
    check(s.anchors == 1 and s.queued == 1 and s.animating == 0, "arrive-staged: anchor now, queued, not animating yet")

  elseif tick == 1236 then
    local s = fv()
    local sh = ship(P.index, storage.idx[1])
    check(s.objects > 0 and s.objects < storage.stage_n and s.queued == 1, "arrive-staged: filling (objects=" .. s.objects .. ")")
    check(sh and sh.anim and sh.anim.dir == -1 and sh.anim.n == 180 and sh.first and sh.first.a == 0, "arrive-staged: invisible, first frame")
    check(s.animating == 0, "arrive-staged: not animating while filling")
    -- n == 180, so it waits one full drift (150 tiles) behind its spot, x on the spot
    check(sh and sh.anim and sh.anim.side == 1, "arrive-staged: waits behind its spot (side 1)")
    check(sh and sh.base and math.abs(sh.anchor.x - sh.base.x) < TOL and math.abs(sh.anchor.y - (sh.base.y + 150 * (1 + 2 * (sh.k - 1)))) < TOL,
      "arrive-staged: first frame at spot.y + 150 * parallax, x on the spot (dx " .. tostring(sh and sh.base and sh.anchor.x - sh.base.x)
      .. " dy " .. tostring(sh and sh.base and sh.anchor.y - sh.base.y) .. ")")

  elseif tick == 1242 then
    local s = fv()
    local sh = ship(P.index, storage.idx[1])
    check(s.objects == storage.stage_n and s.queued == 0 and s.animating == 1 and s.anchors == 1, "arrive-staged: complete, now animating, no doubles")
    check(sh and sh.anim and sh.anim.dir == -1 and sh.anim.n < 180, "arrive-staged: animation running")

  elseif tick == 1440 then
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil and fv().objects == storage.stage_n and fv().animating == 0, "arrive-staged: arrived fully")
    check(sh and sh.first.a == 1 and math.abs(sh.first.x_scale / kof(storage.idx[1]) - storage.base_xs1 / storage.k1) < 1e-6, "arrive-staged: alpha and scale back to base (per its factor)")
    check_on_spot(sh, "arrive-staged end")
    -- dirty tracking: build on platform-1 -> dirty -> lazy rebuild -> swap without a blink (throttle 200 ticks)
    remote.call("fleet-view", "set_rebuild_ticks", 200)
    remote.call("fleet-view", "reset_gather_stats")
    storage.n1 = ship_objects(fv(), P.index, storage.idx[1])
    local pl1 = plat["platform-1"]
    local pos = pl1.surface.find_non_colliding_position("iron-chest", pl1.hub.position, 30, 1)
    check(pos ~= nil, "dirty: found a free spot on platform-1")
    storage.chest = pl1.surface.create_entity{name = "iron-chest", position = pos, force = pl1.force, raise_built = true}
    check(storage.chest and storage.chest.valid, "dirty: chest built on platform-1")
    check(fv().dirty == 1, "dirty: platform-1 marked dirty by the built event (dirty=" .. fv().dirty .. ")")
    storage.track2 = {min = 1e9, max = 0}

  elseif tick == 1560 then
    local t, s = storage.track2, fv()
    log("FV-CHECK dirty rebuild #1: n1=" .. storage.n1 .. " now=" .. ship_objects(s, P.index, storage.idx[1]) .. " min=" .. t.min .. " gathers=" .. s.gathers.total .. " rebuilds=" .. s.gathers.rebuilds)
    check(t.min > 0, "dirty: platform-1 never had 0 objects while rebuilding (min " .. t.min .. ")")
    check(ship_objects(s, P.index, storage.idx[1]) == storage.n1 + chest_objects(), "dirty: new object (chest) drawn after the lazy rebuild")
    check(s.gathers.rebuilds == 1 and s.dirty == 0 and s.queued == 0, "dirty: exactly one rebuild, no longer dirty, queue empty")
    check(s.objects == storage.n1 + chest_objects() and s.anchors == 1, "dirty: no doubled objects after the swap (" .. s.objects .. ")")
    -- three more changes inside the throttle window: removal of the chest plus a build/destroy pair
    local pl1 = plat["platform-1"]
    storage.chest.destroy{raise_destroy = true}
    local pos = pl1.surface.find_non_colliding_position("iron-chest", pl1.hub.position, 30, 1)
    local c2 = pl1.surface.create_entity{name = "iron-chest", position = pos, force = pl1.force, raise_built = true}
    c2.destroy{raise_destroy = true}
    check(fv().dirty == 1, "throttle: changes mark dirty again")

  elseif tick == 1600 then
    local s = fv()
    check(s.gathers.rebuilds == 1 and s.dirty == 1, "throttle: no second rebuild inside the window (rebuilds=" .. s.gathers.rebuilds .. ")")
    check(ship_objects(s, P.index, storage.idx[1]) == storage.n1 + chest_objects(), "throttle: picture unchanged until the rebuild")

  elseif tick == 1780 then
    local t, s = storage.track2, fv()
    log("FV-CHECK dirty rebuild #2: min=" .. t.min .. " rebuilds=" .. s.gathers.rebuilds)
    check(s.gathers.rebuilds == 2 and s.dirty == 0, "throttle: exactly one more rebuild after the window (rebuilds=" .. s.gathers.rebuilds .. ")")
    check(ship_objects(s, P.index, storage.idx[1]) == storage.n1, "dirty: removal visible after the rebuild")
    check(t.min > 0, "dirty: no blink over both rebuilds (min " .. t.min .. ")")
    check(s.objects == storage.n1 and s.anchors == 1 and s.queued == 0, "dirty: no doubles at the end")
    storage.track2 = nil

  elseif tick == 1800 then
    -- every gather goes through the one-per-tick queue: config change drops all models; only the OTHER ship is
    -- gathered (layout F never needs the viewer's own platform), in one gather
    remote.call("fleet-view", "reset_gather_stats")
    remote.call("fleet-view", "configuration_changed")
    local s = fv()
    check(s.gathers.total == 0 and s.objects == 0, "gather-queue: nothing gathered or drawn synchronously (gathers=" .. s.gathers.total .. ")")

  elseif tick == 1815 then
    local s = fv()
    check(s.gathers.total == 1 and s.gathers.max == 1, "gather-queue: 1 gather, never more than 1 in a tick (total=" .. s.gathers.total .. " max=" .. s.gathers.max .. ")")
    check(s.models == 1, "gather-queue: only the other ship has a model (models=" .. s.models .. ")")
    check(s.objects == storage.n1 and s.queued == 0 and s.anchors == 1, "gather-queue: ship drawn completely afterwards")

  elseif tick == 1816 then
    P.teleport({0, 0}, game.surfaces["nauvis"])

  elseif tick == 1817 then
    -- boarding with no cached models: the viewer's own platform must not be gathered
    remote.call("fleet-view", "configuration_changed")
    remote.call("fleet-view", "reset_gather_stats")
    local hub2 = plat["platform-2"].hub
    P.teleport({hub2.position.x, hub2.position.y + 4}, plat["platform-2"].surface)

  elseif tick == 1830 then
    local s = fv()
    check(s.gathers.total == 1 and s.models == 1 and s.objects == storage.n1 and s.anchors == 1 and s.queued == 0,
      "boarding: no gather of the viewer's own platform (gathers=" .. s.gathers.total .. " models=" .. s.models .. ")")

  elseif tick == 1831 then
    -- an anchor destroyed behind the mod's back, then its ship leaves: no error, ship removed, no orphans
    local anchors = plat["platform-2"].surface.find_entities_filtered{name = "fv-anchor"}
    check(#anchors == 1, "dead-anchor: one anchor to destroy")
    anchors[1].destroy()

  elseif tick == 1832 then
    move1("vulcanus")

  elseif tick == 1835 then
    local s = fv()
    check(s.objects == 0 and s.anchors == 0 and s.animating == 0 and s.queued == 0 and count(s.views) == 0,
      "dead-anchor: ship dropped cleanly on leaving (objects=" .. s.objects .. " anchors=" .. s.anchors .. " animating=" .. s.animating .. ")")
    move1("nauvis")

  elseif tick == 1838 then
    local s = fv()
    check(s.anchors == 1, "dead-anchor: ship comes back normally afterwards")

  elseif tick == 3625 then
    -- idle float: a parked ship floats around its spot, never further than 0.5 * parallax per axis, no jumps
    remote.call("fleet-view", "set_no_idle", nil)
    storage.float = {moved = 0, far = 0, jump = 0}
  elseif tick > 3625 and tick < 3638 then
    -- 0.4.8: the anchor moves only in steps of 1/32 tile per axis (moving it costs time per render object), so it is
    -- checked against the float curve 0.5 * p * sin(2 pi t / period + phase), p = 1 + 2 * (k - 1): never more than one
    -- step (+ the 1/256 position grid) behind it
    local sh, fl = ship(P.index, storage.idx[1]), storage.float
    if sh and sh.anim == nil and sh.anchor and sh.base and sh.k and sh.idle then
      local p = 1 + 2 * (sh.k - 1)
      local lim = 0.5 * p + 0.01
      if math.abs(sh.anchor.x - sh.base.x) > lim or math.abs(sh.anchor.y - sh.base.y) > lim then fl.far = fl.far + 1 end
      local t, w = game.tick, sh.idle
      local ex = sh.base.x + 0.5 * p * math.sin(2 * math.pi * t / w.px + w.fx)
      local ey = sh.base.y + 0.5 * p * math.sin(2 * math.pi * t / w.py + w.fy)
      local off = math.max(math.abs(sh.anchor.x - ex), math.abs(sh.anchor.y - ey))
      fl.off = math.max(fl.off or 0, off)
      if off > 1 / 32 + 1 / 256 + 1e-6 then fl.lag = (fl.lag or 0) + 1 end
      if fl.last then
        local d = math.abs(sh.anchor.x - fl.last.x) + math.abs(sh.anchor.y - fl.last.y)
        if d > 0 then fl.moved = fl.moved + 1 end
        if d > 2 * (1 / 32 + 0.01) then fl.jump = fl.jump + 1 end
      elseif math.abs(sh.anchor.x - sh.base.x) + math.abs(sh.anchor.y - sh.base.y) > 0 then
        fl.moved = fl.moved + 1 -- the first float step leaves the spot
      end
      fl.last = {x = sh.anchor.x, y = sh.anchor.y}
    end
  elseif tick == 3638 then
    local fl = storage.float
    log("FV-CHECK idle float: moved " .. fl.moved .. " far " .. fl.far .. " jump " .. fl.jump .. " max off curve " .. tostring(fl.off) .. " lag " .. tostring(fl.lag))
    check(fl.moved >= 1, "idle: a parked ship floats (moved on " .. fl.moved .. " of 12 ticks)")
    check(fl.far == 0, "idle: stays within 0.5 * parallax of its spot per axis")
    check(fl.jump == 0, "idle: no jump bigger than one float step")
    check(fl.off ~= nil and (fl.lag or 0) == 0, "idle: never more than one 1/32 step off the float curve (max " .. tostring(fl.off) .. ")")
    -- 0.4.9 float smoothness: the view carries the step; the setting is applied live (no redraw, same anchors)
    check(fv().views[P.index].step == 0, "float smoothness: default smooth = 0 (0.5.0; " .. tostring(fv().views[P.index].step) .. ")")
    storage.smooth = {anchors = fv().anchors, moved = 0}
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-smoothness", "balanced")
  elseif tick == 3639 then
    check(fv().views[P.index].step == 1 / 32, "float smoothness: balanced applied live = 1/32 (" .. tostring(fv().views[P.index].step) .. ")")
    check(fv().anchors == storage.smooth.anchors, "float smoothness: no redraw on change")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-smoothness", "smooth")
  elseif tick > 3639 and tick < 3648 then
    -- smooth = the anchor is teleported every tick (it shows as a change on most ticks: 1/256 tile grid, ~0.003 tiles/tick)
    local sh, sm = ship(P.index, storage.idx[1]), storage.smooth
    if sh and sh.anchor then
      if sm.last and (sh.anchor.x ~= sm.last.x or sh.anchor.y ~= sm.last.y) then sm.moved = sm.moved + 1 end
      sm.last = {x = sh.anchor.x, y = sh.anchor.y}
    end
  elseif tick == 3648 then
    log("FV-CHECK float smoothness smooth: anchor changed on " .. storage.smooth.moved .. " of 7 ticks")
    check(fv().views[P.index].step == 0, "float smoothness: smooth applied live = 0 (" .. tostring(fv().views[P.index].step) .. ")")
    check(storage.smooth.moved >= 4, "float smoothness: smooth moves the anchor on most ticks (" .. storage.smooth.moved .. " of 7)")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-smoothness", "light")
  elseif tick == 3649 then
    check(fv().views[P.index].step == 1 / 8, "float smoothness: light applied live = 1/8 (" .. tostring(fv().views[P.index].step) .. ")")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-smoothness", "balanced")
    -- the per-user setting turns the float off (the real setting path: the view is redrawn without it)
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-float", false)
  elseif tick == 3650 then
    local sh = ship(P.index, storage.idx[1])
    storage.still = sh and sh.anchor and {x = sh.anchor.x, y = sh.anchor.y}
    check_on_spot(sh, "float off: parked exactly on its spot")
  elseif tick == 3660 then
    local sh = ship(P.index, storage.idx[1])
    check(sh and storage.still and sh.anchor.x == storage.still.x and sh.anchor.y == storage.still.y, "float off: the ship does not move")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-float", true)
    remote.call("fleet-view", "set_no_idle", true)
  elseif tick == 3662 then
    -- camera parallax: ON, viewer walks 12/8 tiles; the anchor eases to base + (cam - deck) * 0.125 / p (p = 1 + 2 * (k - 1))
    remote.call("fleet-view", "set_no_parallax", nil)
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-parallax", "medium")   -- default is off since 2026-11-12
    local s0 = ship(P.index, storage.idx[1])
    storage.par = {max = 0, start = {x = s0.anchor.x, y = s0.anchor.y}}
    P.teleport({P.position.x + 12, P.position.y + 8}, P.surface)
  elseif tick > 3662 and tick < 3699 and storage.par then
    local sh = ship(P.index, storage.idx[1])
    local pr = storage.par
    if sh and sh.anchor then
      if pr.last then pr.max = math.max(pr.max, math.abs(sh.anchor.x - pr.last.x) + math.abs(sh.anchor.y - pr.last.y)) end
      pr.last = {x = sh.anchor.x, y = sh.anchor.y}
    end
    if tick == 3694 then
      local deck = fv().layouts[P.surface.platform.index].deck
      local p = 1 + 2 * (sh.k - 1)
      local ex, ey = sh.base.x + (P.position.x - deck.x) * 0.125 / p, sh.base.y + (P.position.y - deck.y) * 0.125 / p
      log(string.format("FV-CHECK parallax: anchor %.4f,%.4f want %.4f,%.4f max step %.3f", sh.anchor.x, sh.anchor.y, ex, ey, pr.max))
      local po = fv().views[P.index].po
      check(math.abs(po.x - (P.position.x - deck.x) * 0.125) < 1e-4 and math.abs(po.y - (P.position.y - deck.y) * 0.125) < 1e-4,
        "parallax: view offset = (cam - deck) * 0.125 within 1e-4 (" .. po.x .. "," .. po.y .. ")")
      -- the anchor is stored in 1/256 tiles
      check(math.abs(sh.anchor.x - ex) < 0.005 and math.abs(sh.anchor.y - ey) < 0.005, "parallax: anchor = base + (cam - deck) * 0.125 / p")
      local total = math.abs(sh.anchor.x - pr.start.x) + math.abs(sh.anchor.y - pr.start.y)
      check(pr.max < 0.45 * total, "parallax: eases, no jump on a 14-tile camera move (max step " .. pr.max .. " of " .. total .. ")")
      check(math.abs(sh.anchor.x - sh.base.x) + math.abs(sh.anchor.y - sh.base.y) > 0.5, "parallax: the ship really moved off its spot")
      -- off via the real setting: eases back to the spot without a redraw
      remote.call("fleet-view", "set_setting", P.index, "fleet-view-parallax", "off")
      pr.at = {x = sh.anchor.x, y = sh.anchor.y}
      pr.max = 0
    end
  elseif tick == 3699 then
    local sh = ship(P.index, storage.idx[1])
    local d0 = math.abs(storage.par.at.x - sh.base.x) + math.abs(storage.par.at.y - sh.base.y)
    local d1 = math.abs(sh.anchor.x - sh.base.x) + math.abs(sh.anchor.y - sh.base.y)
    check(d1 < d0 * 0.5, "parallax: setting off eases back to the spot (" .. d0 .. " -> " .. d1 .. ")")
    check(storage.par.max < 0.45 * d0, "parallax: setting off, no jump (max step " .. storage.par.max .. " of " .. d0 .. ")")
    remote.call("fleet-view", "set_setting", P.index, "fleet-view-parallax", "medium")
    remote.call("fleet-view", "set_no_parallax", true)
    storage.par = nil
  elseif tick == 3700 then
    -- APPROACH: the viewer's platform flies in for real; the ships at its destination come in during the approach,
    -- set by the remaining distance like the planet (offset 2.875e-5 * km^2 tiles, i.e. n = 180 * km / sqrt(150 / 2.875e-5))
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "approach: platform-1 parked before the viewer leaves")
    remote.call("fleet-view", "set_min_step", 1)
    move2("vulcanus")
  elseif tick == 3900 then
    check(fv().anchors == 0, "approach: the ship left while the viewer was away")
    remote.call("fleet-view", "set_min_step", nil)
    local p2 = plat["platform-2"]
    p2.schedule = {current = 1, records = {{station = "nauvis", wait_conditions = {}}}}
    p2.paused = false
    p2.space_connection = "nauvis-vulcanus"
    p2.distance = 0.3 -- 4500 km from nauvis (the `from` end: distance falls towards it)
    storage.appr = {early = 0, n = 0, err = 0, cerr = 0, side = 0}
  elseif tick == 4160 then
    local A, p2 = storage.appr, plat["platform-2"]
    log("FV-CHECK approach: compared " .. A.n .. " early " .. A.early .. " n err " .. A.err .. " curve err " .. A.cerr .. " wrong side " .. A.side
      .. " arrived at " .. tostring(A.arrived))
    check(A.early == 0, "approach: no ship before the platform is within sqrt(150/2.875e-5) km")
    check(A.n > 50, "approach: the ship came in during the approach (" .. A.n .. " ticks compared)")
    check(A.err < 1e-6, "approach: n = 180 * remaining km / sqrt(150/2.875e-5) every tick (worst " .. A.err .. ")")
    check(A.cerr < TOL, "approach: on the planet curve above its spot every tick (worst " .. A.cerr .. ")")
    check(A.side == 0, "approach: comes in from ahead (side -1) as an approach")
    check(A.arrived ~= nil, "approach: the viewer's platform arrived at nauvis")
    local sh = ship(P.index, storage.idx[1])
    check(sh and sh.anim == nil, "approach: settled after arriving")
    check_on_spot(sh, "approach: arrived")
    storage.appr = nil
    p2.schedule = nil
  elseif tick == 4162 then
    -- joined pipes: an L of three pipes on platform-1 (found by scanning for room), masks N 1 / E 2 / S 4 / W 8
    local p1 = plat["platform-1"]
    local surf, force = p1.surface, p1.force
    local function room(x, y)
      return surf.can_place_entity{name = "pipe", position = {x, y}, force = force}
    end
    storage.pipes = nil
    for y = -24, 24 do
      for x = -24, 24 do
        if not storage.pipes and room(x + 0.5, y + 0.5) and room(x + 1.5, y + 0.5) and room(x + 1.5, y + 1.5) then
          storage.pipes = {x + 0.5, y + 0.5}
        end
      end
    end
    check(storage.pipes ~= nil, "pipe probe: found room for 3 pipes on platform-1")
    if storage.pipes then
      local x, y = storage.pipes[1], storage.pipes[2]
      for _, o in ipairs({{0, 0}, {1, 0}, {1, 1}}) do
        local e = surf.create_entity{name = "pipe", position = {x + o[1], y + o[2]}, force = force}
        check(e ~= nil, "pipe probe: pipe placed")
      end
    end
  elseif tick == 4163 then
    if storage.pipes then
      local x, y = storage.pipes[1], storage.pipes[2]
      local got = {}
      for _, p in ipairs(remote.call("fleet-view", "pipe_probe", plat["platform-1"].index)) do
        got[math.floor(p.x * 2 + 0.5) .. "," .. math.floor(p.y * 2 + 0.5)] = p.pmask
      end
      local function at(dx, dy) return got[math.floor((x + dx) * 2 + 0.5) .. "," .. math.floor((y + dy) * 2 + 0.5)] end
      log("FV-CHECK pipe masks: " .. tostring(at(0, 0)) .. " " .. tostring(at(1, 0)) .. " " .. tostring(at(1, 1)))
      check(at(0, 0) == 2, "pipe probe: end of the L joins east only (mask 2, got " .. tostring(at(0, 0)) .. ")")
      check(at(1, 0) == 12, "pipe probe: corner joins south + west (mask 12, got " .. tostring(at(1, 0)) .. ")")
      check(at(1, 1) == 1, "pipe probe: other end joins north only (mask 1, got " .. tostring(at(1, 1)) .. ")")
    end
  elseif tick == 4166 then
    -- live gather of beacons (module tier per slot) and lamps (glow only when lit): build some on platform-1
    local sf = plat["platform-1"].surface
    local force = plat["platform-1"].force
    local c = plat["platform-1"].hub.position
    local function put(name, extra)
      -- first free spot on the deck (a platform only builds on foundation tiles: the non-colliding search would pick space)
      for r = 2, 40 do
        for dx = -r, r do
          for _, dy in ipairs{-r, r} do
            local pos = {x = math.floor(c.x) + dx + 0.5, y = math.floor(c.y) + dy + 0.5}
            if sf.can_place_entity{name = name, position = pos, force = force} then
              local spec = {name = name, position = pos, force = force}
              for k, v in pairs(extra or {}) do spec[k] = v end
              local e = sf.create_entity(spec)
              if e then return e end
            end
          end
        end
      end
      check(false, "could not place " .. name)
      return nil
    end
    local b1, b2 = put("beacon"), put("beacon")
    if b1 then b1.get_module_inventory().insert{name = "speed-module-3", count = 1} end
    if b2 then local inv = b2.get_module_inventory(); inv[2].set_stack{name = "efficiency-module-2", count = 1} end
    local src = put("electric-energy-interface")
    if src then src.power_production = 1e6 / 60; src.electric_buffer_size = 1e8; src.energy = 1e8 end
    put("small-electric-pole")
    for _ = 1, 3 do
      local l = put("small-lamp")
      if l then l.always_on = true end
    end
    log("FV-CHECK live gather setup: beacons on surface " .. #sf.find_entities_filtered{name = "beacon"} .. " b1 " .. tostring(b1 and b1.valid) .. " lamps " .. #sf.find_entities_filtered{name = "small-lamp"} .. " surface " .. sf.name)
    put("small-lamp")   -- not always_on: platform surfaces are always day, so this one stays off
  elseif tick == 4167 then
    local r = remote.call("fleet-view", "gather_probe", plat["platform-1"].index)
    log("FV-CHECK live gather: beacons " .. serpent.line(r.beacons) .. " glows " .. r.glows .. " ents " .. r.n)
    local seen = {}
    for _, m in ipairs(r.beacons) do seen[table.concat(m)] = true end
    check(seen["30"], "live gather: beacon with speed-module-3 in slot 1 stores {3,0}")
    check(seen["02"], "live gather: beacon with efficiency-module-2 in slot 2 stores {0,2}")
    check(r.glows <= 12, "live gather: glows capped")
    check(r.glows == 0 or r.glows == 3, "live gather: only the always_on lamps glow (" .. r.glows .. ")")
    log("FV-CHECK live gather glows=" .. r.glows .. " (3 = powered always_on lamps lit; 0 = power did not reach)")
  elseif tick == 4165 then
    -- Platform art: the gathered models carry curve / underground / pipe-mask info wherever such entities exist, and the
    -- sprite names the draw tries are valid sprite paths (data stage made them).
    local tot = {belts = 0, curved = 0, ugs = 0, ug_typed = 0, pipes = 0, pipes_masked = 0,
      inserters = 0, arms = 0, beacons = 0, beacon_mods = 0, glows = 0, max_glows = 0}
    local nmodels, bad, nedges = 0, 0, 0
    for idx, r in pairs(remote.call("fleet-view", "shape_stats")) do
      nmodels = nmodels + 1
      nedges = nedges + r.edges
      check(r.edges > 0, "edge art: model " .. idx .. " has edge pieces")
      for k in pairs(tot) do if r[k] then tot[k] = tot[k] + r[k] end end
      tot.max_glows = math.max(tot.max_glows, r.glows)
      for name in pairs(r.names) do
        if not helpers.is_valid_sprite_path(name) then bad = bad + 1; log("FV-CHECK invalid shape sprite " .. name) end
      end
    end
    log("FV-CHECK shape art: models=" .. nmodels .. " belts=" .. tot.belts .. " curved=" .. tot.curved .. " ugs=" .. tot.ugs
      .. " ug typed=" .. tot.ug_typed .. " pipes=" .. tot.pipes .. " pipes with mask=" .. tot.pipes_masked)
    log("FV-CHECK edge art: pieces over " .. nmodels .. " models = " .. nedges)
    check(nmodels > 0, "shape art: at least one gathered model to look at")
    check(bad == 0, "shape art: every shape sprite name is a valid sprite path (" .. bad .. " invalid)")
    check(tot.ug_typed == tot.ugs, "shape art: every underground belt has in/out (" .. tot.ug_typed .. "/" .. tot.ugs .. ")")
    check(tot.pipes_masked == tot.pipes, "shape art: every pipe has a mask (" .. tot.pipes_masked .. "/" .. tot.pipes .. ")")
    check(tot.curved <= tot.belts, "shape art: curved belts are a subset of the belts")
    log("FV-CHECK arms/modules/glows: inserters=" .. tot.inserters .. " arms=" .. tot.arms .. " beacons=" .. tot.beacons
      .. " beacons with mods=" .. tot.beacon_mods .. " max glows on a ship=" .. tot.max_glows)
    check(tot.arms == tot.inserters, "arms: every inserter has an arm sprite (" .. tot.arms .. "/" .. tot.inserters .. ")")
    check(tot.beacon_mods == tot.beacons, "beacon modules: every beacon stores its module tiers (" .. tot.beacon_mods .. "/" .. tot.beacons .. ")")
    check(tot.max_glows <= 12, "glows: at most 12 per ship (" .. tot.max_glows .. ")")
    check(helpers.is_valid_sprite_path("fv-glow") and helpers.is_valid_sprite_path("fv-arm-inserter")
      and helpers.is_valid_sprite_path("fv-e-beacon-t00") and helpers.is_valid_sprite_path("fv-e-beacon-t33"), "arms/modules/glows: data sprites exist")
    for _, n in ipairs({"fv-e-inserter-east", "fv-e-beacon", "fv-e-pipe-m0", "fv-e-pipe-m15", "fv-e-transport-belt-r5",
      "fv-e-transport-belt-r12", "fv-e-underground-belt-in-north", "fv-e-underground-belt-out-west",
      -- 0.4.8: pipe-to-ground is drawn with its own picture per direction, not the north one turned
      "fv-e-pipe-to-ground", "fv-e-pipe-to-ground-east", "fv-e-pipe-to-ground-south", "fv-e-pipe-to-ground-west"}) do
      check(helpers.is_valid_sprite_path(n), "shape art: sprite " .. n .. " exists")
    end
  elseif tick >= 4176 and tick <= 4322 then
    transfer_step(tick)

  elseif tick == 4400 then
    -- Review focus 3: only one other platform, then none
    local ok = pcall(function() game.delete_surface(game.surfaces["platform-1"]) end)
    check(ok, "delete_surface(platform-1) ok")

  elseif tick == 4405 then
    local s = fv()
    check(s.objects == 0, "all other platforms gone: 0 objects (" .. s.objects .. ")")
    check(s.anchors == 0, "all other platforms gone: 0 anchors (" .. s.anchors .. ")")
    check(count(s.views) == 0, "no view recorded when nothing else is parked")
    remote.call("fleet-view", "show", P.index)
    s = fv()
    check(s.anchors == 0 and s.objects == 0, "show() with a lone platform: nothing drawn, no anchors")
    remote.call("fleet-view", "clear", P.index)
    -- 0.4.9: a huge cross-shaped viewer platform (arms 200 wide, 2000 across); the other platforms are parked at its planet
    local home = plat["platform-2"].space_location.name
    storage.cross = {home = home}
    local cp = game.forces.player.create_space_platform{name = "fv-cross", planet = home, starter_pack = "space-platform-starter-pack"}
    cp.apply_starter_pack()
    storage.cross.platform = cp
    local tiles = {}
    for x = -1000, 999 do for y = -100, 99 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
    cp.surface.set_tiles(tiles, true, false, true, true)
    tiles = {}
    for x = -100, 99 do for y = -1000, 999 do if y < -100 or y >= 100 then tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end end
    cp.surface.set_tiles(tiles, true, false, true, true)
  elseif tick == 4410 then
    local cp = storage.cross.platform
    check(cp and cp.valid, "cross: platform built")
    local hub = cp.hub
    P.teleport({hub.position.x, hub.position.y + 4}, cp.surface)
    remote.call("fleet-view", "show", P.index)
    remote.call("fleet-view", "flush")
  elseif tick == 4414 then
    local cp = storage.cross.platform
    local sf = cp.surface
    local function has_deck(b, g)
      return sf.count_tiles_filtered{area = {{b.x - b.hw - g, b.y - b.hh - g}, {b.x + b.hw + g, b.y + b.hh + g}}, name = "space-platform-foundation", limit = 1} > 0
    end
    local L = fv().layouts[cp.index]
    local n, near = 0, 0
    for _, b in pairs(L and L.ships or {}) do
      n = n + 1
      check(not has_deck(b, 0), "cross: ship " .. n .. " sits over no deck tile (" .. b.x .. "," .. b.y .. ")")
      if math.max(math.abs(b.x), math.abs(b.y)) < 600 then near = near + 1 end
      log("FV-CHECK cross ship at " .. string.format("%.1f,%.1f", b.x, b.y))
    end
    check(n >= 1, "cross: ships were placed (" .. n .. ")")
    -- every ship in a corner is near the arms, none out at the bounding box edge (1000) unless it rolled along an arm
    check(near >= 1, "cross: at least one ship in a corner, much nearer than the bounding box edge (" .. near .. " of " .. n .. ")")
    -- time of one geom.spot on this cross (real surface predicate), spots are rolled once per arrival
    local deck = {cx = 0, cy = 0, hw = 1000, hh = 1000}
    local function blocked(tx1, ty1, tx2, ty2)
      return sf.count_tiles_filtered{area = {{tx1, ty1}, {tx2 + 1, ty2 + 1}}, name = "space-platform-foundation", limit = 1} > 0
    end
    local gen = game.create_random_generator(77)
    local calls = 0
    local counted = function(...) calls = calls + 1; return blocked(...) end
    local pr = helpers.create_profiler()
    for _ = 1, 20 do geom.spot(deck, {}, 20, 30, function() return gen() end, counted) end
    pr.stop()
    log({"", "FV-PROF cross 20x geom.spot total ", pr, " predicate calls ", calls})
    -- the corners of a big platform are ungenerated chunks: "out-of-map", not "empty-space" (why the deck test counts foundation)
    local ct = sf.get_tile(600, 600).name
    log("FV-CHECK cross corner tile name " .. ct .. "; (205,205) " .. sf.get_tile(205, 205).name .. "; empty-space proto " .. tostring(prototypes.tile["empty-space"] ~= nil))
    check(ct ~= "space-platform-foundation", "cross: the corner is not deck (" .. ct .. ")")
  elseif tick == 4430 then
    if #failures == 0 then log("fleet-view checks: all passed")
    else log("fleet-view checks: FAILED " .. #failures .. ": " .. table.concat(failures, " | ")) end
  end
end

script.on_event(defines.events.on_tick, function(e)
  storage.t0 = storage.t0 or e.tick
  local ok, err = pcall(step, e.tick - storage.t0)
  if not ok then log("FV-CHECK FAIL: script error " .. tostring(err)); failures[#failures + 1] = "script error" end
end)
script.on_init(function() storage.t0 = nil end)
