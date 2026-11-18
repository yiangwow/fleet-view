# Fleet View — Release 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Factorio 2.1 mod that draws your other platforms parked at the same space location in the background of the platform you're on, with depth and matching light.

**Architecture:** Pure-Lua modules (tile merging, slot layout, parallax, shading) are unit-tested outside the game. Data stage makes one sprite per entity. Runtime snapshots each platform into a cached model, draws it per viewer with `rendering.draw_sprite`, every object targeting one invisible anchor entity per (viewer, ship) so the depth effect costs one `teleport` per anchor.

**Tech Stack:** Factorio 2.1.23 Lua API (Lua 5.2), `lua5.2` for unit tests, headless `factoriotools/factorio:2.1.23` in Docker for integration, Windows `factorio.exe` for screenshots.

**Spec:** `docs/superpowers/specs/2026-10-23-fleet-view-design.md` (read it first). Reference look: `docs/stills/ships-mid.png`.

## Contents

- Global Constraints
- Review Focus
- Task 1: Spike (throwaway) — anchor, layer, screenshots, cost
- Task 2: Mod skeleton, settings, unit-test runner
- Task 3: Pure modules — tiles, slots, parallax, shade
- Task 4: Entity sprites (data stage)
- Task 5: Snapshot + draw + depth (runtime)
- Task 6: Arrive / leave
- Task 7: Integration test + UPS measurement on the real save
- Task 8: Visual check with the owner
- Task 9: Publish + install on server

## Global Constraints

- `info.json`: `"name": "fleet-view"`, `"title": "Fleet View"`, `"author": "holyskib"`, `"factorio_version": "2.1"`, dependencies `["base >= 2.1", "space-age >= 2.1"]`. Licence MIT.
- Mid distance: distant ships drawn at **4/30 ≈ 0.133** of real scale (spec §3: ~4 px/tile vs deck ~30 px/tile).
- Light: from the location's `platform_backdrop.light_direction`; Nauvis `{-0.42, 0.23, 0.67}`. No backdrop → `{-0.5, -0.5, 0.7}` neutral white (spec §7).
- Never drawn over the viewer's deck; behind deck, in front of planet backdrop.
- Removing the mod leaves the save clean: anchors are the only entities the mod creates, and `on_configuration_changed`/removal must not leave anything visible. Anchors must be non-colliding, non-selectable, invisible, not minable, not blueprintable.
- Deterministic: no `math.random`; per-player visuals via `players = {player}`.
- Per-player settings (runtime-per-user, bool, default true): `fleet-view-depth`, `fleet-view-detail`. Shadow setting is release 2.
- Project rules: author = the repo's local git identity, no Co-Authored-By lines; repo gets a `CLAUDE.md` (layout, how to test, how to publish) in the first commit that adds code.

## Review Focus

1. **Viewer changes surface mid-draw** (walks onto a rocket, opens remote view of another planet): every object drawn for them must go, none linger on the old platform. → test in Task 5.
2. **A platform is deleted or renamed while drawn** (`on_space_platform_deleted`/surface deleted): its pictures vanish for every viewer, no errors. → Task 5.
3. **Only one platform at the location** (nothing else parked): nothing drawn, no anchors created. → Task 5.
4. **Modded entities with no usable graphic** (Maraxsis, PlanetsLib content, anything with only `icons`): fall back to icon, never crash data stage. → Task 4.
5. **Player toggles a setting while on a platform**: redraw immediately, no doubled objects. → Task 5.

---

### Task 1: Spike (throwaway) — anchor, layer, screenshots, cost

Everything here lives in `spike/` and is never shipped. Output is `docs/spike-findings.md`. **Gate:** if (a) or (b) fails, stop and report to the owner before Task 5; the fallback is retargeting objects at a reduced cadence, which changes what the depth setting costs.

**Files:** Create `spike/fv-spike/{info.json,data.lua,control.lua}`, `spike/run-headless.sh`, `tools/shot.sh`, `docs/spike-findings.md`.

- [ ] **Step 1:** Spike mod defines `simple-entity-with-owner` `fv-anchor` (no picture: `Sprite` with `filename="__core__/graphics/empty.png"`, size 1; `collision_mask = {layers={}}`, `selectable_in_game=false`, flags `{"not-on-map","not-blueprintable","not-deconstructable","placeable-off-grid","no-automated-item-removal","no-automated-item-insertion"}`, `hidden=true`).
- [ ] **Step 2:** `/sc` on a copy of nn1 (`/home/tt/factorio/saves/nn1.zip`) in headless 2.1.23: create `fv-anchor` on `platform-2` at a position with **no tile** (60 tiles off the deck edge). Record: did `create_entity` succeed? Does it survive 600 ticks? Draw 1 sprite with `target={entity=anchor, offset={3,0}}`, teleport the anchor 10 tiles, read back `render_object.target.position`. Pass = it moved.
- [ ] **Step 3:** `tools/shot.sh <save> <out.png>`: launch Windows `factorio.exe` from WSL with its own `--config` (separate write-data dir under `%TEMP%\fv-shot`, so it never touches the owner's profile or a running game), `--mod-directory` pointing at the test mods, `--load-game <save>`; a hook in the spike mod calls `game.take_screenshot{...}` at tick 120 into `script-output`; the script waits for the file then `taskkill`s the process. Pass = a PNG of the platform surface exists.
- [ ] **Step 4:** With the shot tool: draw a test sprite on `render_layer="under-tiles"` and one on `"zero"`, both partly over deck tiles and partly over space. Record which layer shows over the planet backdrop **and** under the deck. Pass = one does both.
- [ ] **Step 5:** Cost: headless `--benchmark` 600 ticks on the nn1 copy with (i) no spike, (ii) 6 anchors each with 600 objects teleported every tick, (iii) same 3600 objects retargeted individually every tick. Record avg ms/tick for each. These are the numbers the owner gets; nothing else in this project quotes a cost figure.
- [ ] **Step 6:** Write `docs/spike-findings.md` (each result, pass/fail, the chosen layer, the three timings). Commit `spike/`, `tools/shot.sh`, findings.

### Task 2: Mod skeleton, settings, unit-test runner

**Files:** Create `fleet-view/info.json`, `fleet-view/settings.lua`, `fleet-view/locale/en/fleet-view.cfg`, `fleet-view/changelog.txt`, `tests/run.lua`, `tests/test_smoke.lua`, `Makefile`, `CLAUDE.md`, `README.md`.

**Interfaces — Produces:** `make test` runs every `tests/test_*.lua` with `lua5.2`; a test file returns a table `{ name = function() ... end }` and uses `assert`/`assert_eq(a, b)`/`assert_near(a, b, eps)` from `tests/run.lua`. `make zip` builds `dist/fleet-view_<version>.zip` with folder `fleet-view_<version>/`. `make headless SAVE=...` runs Task 7's check.

- [ ] **Step 1:** `sudo apt-get install -y lua5.2`. Write `tests/test_smoke.lua` asserting `assert_eq(1+1, 2)`; run `make test` → expect FAIL (no runner).
- [ ] **Step 2:** Write `tests/run.lua` + `Makefile`; `make test` → PASS, prints `1 passed`.
- [ ] **Step 3:** `info.json` per Global Constraints, version `0.1.0`; settings `fleet-view-depth`, `fleet-view-detail` with locale names "Depth effect" / "Building detail" and descriptions from spec §6.
- [ ] **Step 4:** `make zip` then headless load (`--create /tmp/t.zip` with the zip in a mod dir) → log contains `Loading mod fleet-view 0.1.0` and no `Error`.
- [ ] **Step 5:** `CLAUDE.md` (layout, `make test|zip|headless`, `tools/shot.sh`, publish steps placeholder filled in Task 9). Commit.

### Task 3: Pure modules — tiles, slots, parallax, shade

**Files:** Create `fleet-view/scripts/geom.lua`; Test `tests/test_geom.lua`.

**Interfaces — Produces** (module `geom`, no game globals):
- `geom.merge_tiles(tiles: {{x:int,y:int}}) -> {{x:int,y:int,w:int,h:int}}` — rectangles covering exactly the tile set, no overlaps.
- `geom.slot(viewer_id: int, other_id: int, count: int, index: int) -> {x:number, y:number}` — offset in tiles from the viewer platform's centre.
- `geom.parallax(base: {x,y}, player_pos: {x,y}, factor: number) -> {x,y}` — returns `base + player_pos * factor`.
- `geom.shade(light_dir: {x,y,z}, nx: number, ny: number) -> number` — brightness multiplier in [0.35, 1.0] for a point at normalised ship coords (nx, ny ∈ [-1,1]).
- Constants: `geom.SCALE = 4/30`, `geom.DEPTH = 0.6` (fraction of the viewer's movement the distant ships follow; deck = 1.0, planet ≈ 0.05 since its `parallax_strength` is 0.95 toward the starfield).

- [ ] **Step 1:** Tests: `merge_tiles` on an L-shape of 5 tiles → total area 5, no two rects overlap, every input tile covered; on 1134 random-walk tiles → rect count < 300 and area == 1134. `slot` → same inputs give same output; for count 2, the two slots are ≥ 40 tiles apart; never within 30 tiles of (0,0). `parallax({0,0},{10,0},0.6)` → `{6,0}`. `shade` with Nauvis light: (-1,-1) > (1,1); all results within [0.35, 1.0].
- [ ] **Step 2:** `make test` → those fail.
- [ ] **Step 3:** Implement. `merge_tiles`: greedy row runs merged downward. `slot`: angle from a fixed integer hash of `(viewer_id, other_id)` (no RNG), radius 70 + 25·index tiles, angles pushed apart when count > 1, upper half of the screen preferred (planet sits lower-left).
- [ ] **Step 4:** `make test` → PASS. Commit.

### Task 4: Entity sprites (data stage)

**Files:** Create `fleet-view/data-final-fixes.lua`, `fleet-view/prototypes/pictures.lua`; Test `tests/test_pictures.lua`.

**Interfaces — Produces:** for every entity prototype that can be built on a platform, a `sprite` prototype named `fv-e-<entity-name>`; `pictures.find_layer(proto) -> SpriteDef|nil` (pure, unit-tested with fake prototype tables). Runtime uses `helpers.is_valid_sprite_path("fv-e-"..name)` and falls back to `"entity/"..name` (icon).

- [ ] **Step 1:** Tests with fake prototypes: an `assembling-machine` with `graphics_set.animation.layers[1]` → returns layer 1 frame 0 (x=0,y=0, `width`, `height`, `scale`, `shift`); a `solar-panel` with `picture.layers` → first non-shadow layer (`draw_as_shadow ~= true`); a prototype with only `icons` → nil; a 4-direction `animation.north` → north.
- [ ] **Step 2:** `make test` → fail. Implement `find_layer` (walk `picture`, `pictures`, `animation`, `graphics_set.animation`, `graphics_set.idle_animation`, `integration_patch`, `structure`; skip shadow layers; take frame 0; keep `filename`, `width`, `height`, `x=0`, `y=0`, `scale`, `shift`). `make test` → PASS.
- [ ] **Step 3:** `data-final-fixes.lua` creates the sprites; wrap each in `pcall` so one odd prototype is skipped, and `log()` the count made vs skipped.
- [ ] **Step 4:** Headless load with the server's full 2.1 mod set (copy of `/home/tt/factorio/mods` + `fleet-view` zip) → no `Error`, log shows `fleet-view: N sprites, M skipped`. Commit.

### Task 5: Snapshot + draw + depth (runtime)

**Files:** Create `fleet-view/control.lua`, `fleet-view/scripts/snapshot.lua`, `fleet-view/scripts/draw.lua`, `fleet-view/data.lua` (the `fv-anchor` prototype from Task 1, as validated there); Test `tests/test_snapshot.lua` (pure parts).

**Interfaces:**
- Consumes: `geom.*` (Task 3), sprite names `fv-e-*` (Task 4), anchor prototype + render layer chosen in `docs/spike-findings.md`.
- Produces: `storage.models[platform_index] = {rects, ents={{name,x,y,w,h}}, lights={{x,y}}, centre={x,y}, tick}`; `storage.views[player_index] = {surface_index, ships = {[platform_index] = {anchor=LuaEntity, objects={LuaRenderObject}, base={x,y}}}}`; `draw.show(player, platform)` / `draw.clear(player_index)` / `draw.refresh(player_index)`.

- [ ] **Step 1:** Unit tests for the pure part of `snapshot` (`snapshot.build_model(tiles, entities)` → centre is the tile-set centroid; belts/walls/pipes become coloured rects, others become sprite entries; 14 lights max, chosen deterministically from tile list order). Fail → implement → pass.
- [ ] **Step 2:** `control.lua`: rebuild a platform's model every 36000 ticks (10 min) or on first need. On `on_player_changed_surface`, `on_space_platform_changed_state`, `on_runtime_mod_setting_changed`, `on_player_left_game`, `on_surface_deleted`: `draw.refresh` for affected players. Visible set = other platforms of the player's force with the same `space_location` as the player's current platform.
- [ ] **Step 3:** `draw.show`: one anchor per (player, ship) at `parallax(base, player.position, DEPTH)`; all objects target `{entity=anchor, offset=...}` scaled by `geom.SCALE`, tinted by `geom.shade`, `players={player}`, render layer from the spike. Detail off → rects + lights only. Depth off → anchor placed once, never moved.
- [ ] **Step 4:** Depth: `on_tick`, for each viewer with depth on whose `player.position` changed since last tick, teleport their anchors. Nothing else runs per tick.
- [ ] **Step 5:** Headless scripted checks (in `tests/headless/check.lua`, run via `make headless`): put holyskib's character on `platform-2` → objects exist for `platform-1` and `platform-3`, none for `platform-2`; move character → anchor positions change by 0.6× the move; Review Focus 1–3 and 5 each as a scripted case with `assert`. Expected output ends `fleet-view checks: all passed`.
- [ ] **Step 6:** Commit.

### Task 6: Arrive / leave

**Files:** Modify `fleet-view/scripts/draw.lua`, `fleet-view/control.lua`; extend `tests/headless/check.lua`.

- [ ] **Step 1:** Check: set `platform-3` schedule to leave → within 300 ticks its objects for a viewer on `platform-2` are gone and no anchor remains; set it back to arrive → objects appear. Fail first.
- [ ] **Step 2:** On leaving: over 180 ticks, move the anchor away along the platform's travel direction and scale `x_scale/y_scale` from 1 → 0.3 and tint alpha → 0, then destroy. Arriving: reverse. Per-object updates are allowed only during these 180 ticks.
- [ ] **Step 3:** Check passes. Commit.

### Task 7: Integration test + UPS measurement on the real save

- [ ] **Step 1:** `make headless SAVE=<copy of nn1>` → `fleet-view checks: all passed`.
- [ ] **Step 2:** `--benchmark 1800` ticks on the nn1 copy, server's mod set, with and without fleet-view, viewer on `platform-2`, depth on. Record both avg ms/tick in `docs/spike-findings.md` under "Release 1". If the difference is above what Task 1 measured for the anchor approach, stop and report.

### Task 8: Visual check with the owner

- [ ] **Step 1:** `tools/shot.sh` on the nn1 copy: viewer on Chonky at Nauvis, three shots (depth/detail on; detail off; after moving 20 tiles). Copy to `Downloads\fleet-view-shots\`.
- [ ] **Step 2:** Show the owner next to `docs/stills/ships-mid.png`. Changes they ask for are new requests through the normal loop.

### Task 9: Publish + install on server

- [ ] **Step 1:** Owner supplies a fresh mod-portal API key (scope "ModPortal: Upload Mods"). Never written to disk or memory. Publish `0.1.0` via API v2 `init_publish` (new mod) with the summary "See your other ships parked at the same planet, in the background of your platform."
- [ ] **Step 2:** Verify the portal's sha1 equals `sha1sum dist/fleet-view_0.1.0.zip`.
- [ ] **Step 3:** Server: when `/players online` is 0 — `docker stop factorio`, write the zip into `/home/tt/factorio/mods` via `docker run --rm -v /home/tt/factorio:/f alpine`, `docker start factorio`, confirm `script.active_mods["fleet-view"] == "0.1.0"` via rcon.
- [ ] **Step 4:** Fill the publish section of `CLAUDE.md`. Commit, tag `v0.1.0`. Remind the owner to revoke the key.
