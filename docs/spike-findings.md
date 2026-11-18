# Fleet View spike findings (Task 1)

Factorio 2.1.23 (headless docker `factoriotools/factorio:2.1.23`; graphical Windows Steam build 2.1.23), save = copy of nn1, full server mod set. All numbers below were measured in this session. Code: `spike/`, `tools/shot.sh`.

## Verdict

| Gate | Result |
|---|---|
| (a) entity anchor off the deck, sprite follows it | PASS |
| (b) a render layer that is over the planet backdrop AND under the deck | PASS (`zero`, also `background-transitions` and `under-tiles`) |
| Screenshot tool (`tools/shot.sh`) | PASS (needs `SteamAppId` env, see below) |
| Cost | measured, see table |

## Step 2: anchor entity (headless)

- `fv-anchor` (simple-entity-with-owner, empty sprite, empty collision mask, flags as in the brief, hidden) loads in the full mod set.
- Platform `platform-2` tiles: 1077 `space-platform-foundation` tiles, deck x range -23..15. Anchor placed at x=75 (15+60), y=0. `get_tile` there = `empty-space`.
- `create_entity` succeeded, `valid=true`.
- Survives 600 ticks (still valid, same position, render object still valid at tick 600).
- Sprite drawn with `target={entity=anchor, offset={3,0}}`. Anchor teleported 10 tiles (y 0 -> 10, `teleport` returned true).
- **API note:** `render_object.target.position` is `nil` for entity targets. Reading `.target` returns `{type="entity", entity=..., offset={3,0}}`; the effective position is `target.entity.position + target.offset`. The headless readback only reads the anchor's own position, so it proves the API shape, not that the sprite moved.
- **Real-renderer evidence (gate a):** `tools/shot.sh <save> <out> follow` draws an `item.iron-plate` sprite on `render_layer="zero"` with `target={entity=anchor, offset={3,0}}` on `platform-2`, screenshots at tick 120, teleports the anchor (+20 x, +10 y) at tick 122, screenshots again at tick 125. The sprite is at a different place in `docs/spike-shots/follow-before.png` and `docs/spike-shots/follow-after.png`, with the same camera. Pass.

## Step 3: screenshot tool

`tools/shot.sh <save> <out-dir> [mode] [timeout]` works: PNGs of the platform surface (`platform-2`) were produced at 1600x1000 and 1200x800.

- It uses its own `--config` and write-data under `%TEMP%\fv-shot` (`C:\Users\computer\AppData\Local\Temp\fv-shot`), copies the mods there, loads a copy of the save, and kills only the PID it started (`taskkill /PID`).
- **First attempt FAILED:** `factorio.exe` printed `Steam requires game restart, restarting...` and exited (no log). The exe is the Steam build and relaunches through Steam when started outside it.
- **Fix:** set env `SteamAppId=427520` and `SteamGameId=427520` for the launched process. Then it starts independently (log shows `Initializing Steam API ... steam, space-age`). Fullscreen is turned off via `[graphics] fullscreen=false` in the private config.
- `game.take_screenshot` is processed after the tick's script has run: a screenshot requested in the same tick as a teleport already shows the post-teleport state. Anything that needs a before/after has to be separated by at least one tick (used 2 ticks).
- **Abort path (added in fix round 1):** shot.sh snapshots the `factorio.exe` PIDs before launch. If the launched process exits without writing the private log, or the log says "Steam requires game restart", it waits 8 s, lists any NEW `factorio.exe` PIDs it did not start (it does not kill them), prints an error and exits 2. It never waits on a Steam-relaunched instance. Verified with `FV_NO_STEAMAPPID=1 tools/shot.sh ...` (test hook that skips the env vars): output `ERROR: process 14332 exited with no private log (or Steam restart requested)`, rc=2, and no stray `factorio.exe` appeared afterwards. The exit trap only kills the tracked PID if it is still alive as `factorio.exe`, then waits for it to die (the first version raced the next run's `rm` of the write-data dir).
- The first attempt (no env vars) printed `Steam requires game restart, restarting...` and the exe exited. No other `factorio.exe` was left running afterwards (checked with `tasklist`).
- Owner's game: PID 28592 was running during the first runs and was untouched. Its disappearance is explained: the owner's own `factorio-current.log` ends with "Quitting: user-quit" at about 2686 s, i.e. the owner quit the game. The Steam environment variables make the spike process initialise the Steam API against the owner's Steam client (Steam may show "in game").

## Step 4: render layers (screenshots)

Test (`tools/shot.sh <save> <out> layers`, image `docs/spike-shots/layers.png`): `draw_sprite` (virtual-signal icons scaled x6) at layers `under-tiles` (red), `zero` (green), `background-transitions` (blue), `decals` (yellow). Left column is over the nauvis planet backdrop and space, right column is over the platform deck.

| layer | over planet backdrop | under the deck |
|---|---|---|
| `zero` | drawn over the planet, fully visible | right-column sprite is completely hidden by the deck |
| `background-transitions` | visible over the planet | hidden by the deck; only the part outside the deck footprint shows (below the solar panels) |
| `under-tiles` | visible (over space) | hidden by the deck; only a sliver in a gap shows |
| `decals` | visible | drawn over/outside; not hidden (partly over deck only at the bottom edge, not conclusive) |

- **Chosen layer: `zero`**: lowest numeric layer, over the planet backdrop, under the deck. `background-transitions` and `under-tiles` also satisfy both and are available if ordering between fleet objects is needed (0 < 1 < 2).
- **Rectangle gotcha (reproduced):** `tools/shot.sh <save> <out> rect`, image `docs/spike-shots/rect-vs-sprite.png`. Both a `draw_rectangle` (red, opaque) and a `draw_sprite` (green icon) use `render_layer="zero"`, one pair over the deck and one pair over the planet. Over the planet both show. Over the deck the red rectangle is drawn ABOVE the deck entities while the green sprite is hidden under the deck (it does not appear at all). So `draw_rectangle` ignores the layer ordering; use sprites for fleet drawing.

## Step 5: cost (headless `--benchmark`, 620 ticks, nn1 copy, full mod set)

Per-tick data from `--benchmark-verbose all` (`wholeUpdate` and `scriptUpdate` columns), first 10 ticks excluded (setup happens at tick 5). Three runs each, mean ms/tick:

| scenario | wholeUpdate ms/tick (run1 / run2 / run3) | scriptUpdate ms/tick (run1 / run2 / run3) |
|---|---|---|
| (i) no spike | 1.477 / 1.596 / 1.494 (median; mean 4.42 with outlier) | 0.052 / 0.061 / 0.055 |
| (ii) 6 anchors x 600 objects, each anchor teleported every tick | 1.768 / 1.819 / 1.942 | 0.179 / 0.200 / 0.275 |
| (iii) 3600 objects, each retargeted individually every tick | 5.790 / 5.667 / 5.664 | 3.353 / 3.334 / 3.345 |

Note (i) run 3: one tick took 1762 ms (outlier, mean 4.42); its median was 1.494 ms and script 0.055 ms.

- Marginal cost over (i) (whole update, run N minus no-spike run N, using 1.477/1.596/1.494): (ii) +0.29 / +0.22 / +0.45 ms/tick; (iii) +4.31 / +4.07 / +4.17 ms/tick.
- Script time: (iii) 3.33 to 3.35 ms/tick vs (ii) 0.18 to 0.28 ms/tick, i.e. about 12x to 19x.
- **Limit of these numbers:** headless has no renderer, so they are script/simulation cost only. They do not include GPU or draw cost of 3600 sprites in a graphical client.
- (ii) objects are fixed offsets on an anchor; anchors were moved +-1 tile on alternating ticks. (iii) each object `target = {x,y}` re-assigned every tick with a +-1 tile alternating shift.

## Release 1 (Task 7): fleet-view on the real save

Measured with `make bench` (`tests/bench/bench.sh`): headless `--benchmark 1800` ticks, docker 2.1.23, copy of nn1, server mod set, `--benchmark-verbose all`, first 10 ticks excluded, same columns as the Task 1 table. (A) without fleet-view; (B) fleet-view zip + `tests/bench/fleet-view-bench` (not shipped): holyskib on `platform-2`, depth on, drawn via the remote interface at tick 5, then teleported +-1 tile EVERY tick (anchor-teleport path runs every tick; the driver also calls `stats` at ticks 600/1200). At start B had 2 anchors, 992 render objects (2 other platforms). `make headless` also passes (`fleet-view checks: all passed`).

| scenario | wholeUpdate mean ms/tick (run1 / run2 / run3) | wholeUpdate median | scriptUpdate mean ms/tick (run1 / run2 / run3) | scriptUpdate median |
|---|---|---|---|---|
| (A) no fleet-view | 1.530 / 2.651 (one 2020 ms outlier tick) / 1.551 | 1.489 / 1.478 / 1.502 | 0.050 / 0.049 / 0.049 | 0.049 / 0.047 / 0.048 |
| (B) fleet-view, viewer moving, depth on | 1.659 / 1.669 / 1.690 | 1.584 / 1.599 / 1.614 | 0.123 / 0.129 / 0.131 | 0.096 / 0.101 / 0.105 |

- Added script cost (B minus A mean): about +0.07 to +0.08 ms/tick. That includes the bench driver's own per-tick `teleport` call, so it slightly overstates fleet-view. Task 1's anchor approach (6 anchors x 600 objects): script 0.18 to 0.28 ms. Fleet-view is below that range (but only 2 anchors / 992 objects here, so not the same load).
- Added whole-update: about +0.11 to +0.19 ms/tick on means (medians +0.10 to +0.11).
- B shows one tick of about 20 ms in each run (script max 19.8 to 20.2 ms; A max 0.1 to 0.2 ms). Not investigated in this task; it moves the B means by about 0.01 ms.
- Same limit as before: headless has no renderer; GPU/draw cost of the sprites is not measured.

### Release 1: fix round 1 (depth evidence, attribution of the ~20 ms tick)

**1. The depth path ran.** Log from a B run (`FV-BENCH tN` lines; player and the two anchors' positions from `stats`, one anchor per other platform):

```
start: anchors=2 objects=992 surface=platform-2
t6 player=1,4  anchors=[81.137,-41.969  -99.281,-63.703]
t7 player=-1,4 anchors=[81.738,-41.969  -98.680,-63.703]
t8 player=1,4  anchors=[80.535,-41.969  -99.883,-63.703]
t9 player=-1,4 anchors=[81.738,-41.969  -98.680,-63.703]
```
The player moves by 2 tiles (x = 1 / -1); the anchors move by 0.6 x 2 = 1.2 tiles in x (e.g. 81.738 -> 80.535, -98.680 -> -99.883), y unchanged (the player moves only in x). They alternate every tick, and the same positions are logged at t600/t1200 (80.535 / -99.883), so teleports ran for the whole run.

**2. The ~20 ms tick.** It was the bench driver's own `stats` call (it runs `count_entities_filtered` on every surface plus `rendering.get_all_objects`), not fleet-view. Evidence: with the stats logging off (`STATS_EVERY=0`), the max script tick other than tick 5 is 0.3 to 1.6 ms, 3 runs. Per-tick peaks: with stats at ticks 6 to 9 the ~20 ms ticks sit at those ticks, and the t600/t1200 ticks show 20 to 40 ms. The only other large tick is the **initial show** (draw of 992 objects, 2 ships): 78 to 81 ms script at tick 5; with `SHOW_TICK=300` the peak moved to tick 300 (80.3 ms script, 93 ms whole). The earlier table skipped the first 10 ticks, so it excluded that one-time draw.

**Clean B numbers (no stats calls; tick 5 = initial show included in the mean's run but first 10 ticks skipped), `STATS_EVERY=0`, 3 runs:** wholeUpdate mean 1.648 / 1.681 / 1.663; scriptUpdate mean 0.109 / 0.104 / 0.106 (median 0.104 / 0.098 / 0.099). Versus A script mean 0.049 to 0.050: fleet-view + the driver's per-tick teleport add about +0.055 ms/tick, replacing the +0.07 to +0.08 quoted above (that figure contained the stats calls). One-time costs: initial show about 80 ms in one tick.

### Release 1: Task 7b, staged drawing

Drawing is spread over ticks: anchors are created at once; each (viewer, ship) is a `storage.draw_queue` entry worked off by `on_tick` at most `FV_DRAW_BUDGET = 150` render objects per tick (all viewers together), and at most one platform model gather per tick. Measured with `make bench` (now `SHOW_TICK=300 STATS_EVERY=0`, so the show tick is inside the stats; the driver no longer calls `stats` at show), script ms in the 12 ticks from the show tick, 3 runs:

- Before (same bench, unstaged): show tick 55.7 / 53.6 / 55.0 ms script max, everything else < 2 ms.
- After: 16.0 16.1 21.6 | 15.8 18.1 21.9 | 16.3 16.9 24.0 ms for the first three ticks (one model gather each: viewer's own at show, then the two other platforms), then 0.5 to 1.2 ms for the ~4 ticks that create the 992 objects (150 per tick), then ~0.1.
- Script max over the run: 21.6 / 21.9 / 24.0 ms (was 57.1 / 53.6 / 55.0 in this bench; ~80 ms in the Task 7 table). Script mean: 0.135 / 0.133 / 0.135 (A: 0.050 / 0.050 / 0.048).
- Finding: creating the 992 objects costs about 5 ms in total; most of the old show spike was `snapshot.gather` (find_tiles/find_entities), which is why the model gathers are queued too. What is left is one gather (about 16 to 22 ms) per tick for up to three ticks after a show with cold models; models are cached for 10 minutes.
- Whole-update max 25 to 27 ms. (One run of A has a 2 s outlier tick unrelated to the mod, as before.)

### Release 1: Task 7b fix round 1 (event-driven rebuild, all gathers queued)

- Removed the blind 10-minute drop+redraw. Build/mine/die/tile events mark a platform's model dirty; a once-a-minute check rebuilds dirty models older than 36000 ticks (only if some view shows them, else the model is dropped and gathered fresh at the next show). A rebuild is gather (queued) then a swap: a second object set is built on the same anchor under the 150/tick budget, the old set is destroyed in the tick the new one completes, so a ship never has 0 objects.
- The viewer's own platform model (for `centre`) is now gathered by the queue too (`show` waits in the queue); fill, show and rebuild entries share one "gathered this tick" flag. `view` positions use the centre at show time, so building on your own platform does not shift the ships.
- Where a gather spends its time (`helpers.create_profiler`, three platforms of nn1 in a `SHOW_TICK=300` B run, 1077/1134/1508 tiles, 380/308/566 entities): find_tiles 0.9 to 1.9 ms, find_entities 0.1 to 0.2 ms, tile and entity Lua loops 1.2 to 4.0 and 0.6 to 1.1 ms, **build_model (pure Lua) 10.9 / 11.6 / 15.5 ms**. So the cost is `build_model`, not the engine searches; splitting the searches by area would not help. The largest single gather is about 22 ms (with profiler overhead), at the ~20 ms line, so I did not split it; a cheaper `build_model` (string-keyed `set`) would be the next lever.
- `make bench` after the fix (SHOW_TICK=300, 3 runs B): script max 22.0 / 24.7 / 22.3 ms, script mean 0.136 / 0.136 / 0.133 ms (A mean 0.050). Script ms at show tick+0..+4: 0.7-0.8, 15.5, 17-18, 22-25, then 0.5-0.9 while the objects are created, then 0.1. One gather per tick on three consecutive ticks, none stacked. B run 1 whole-update max 2096 ms is the machine's known outlier tick (also seen in A), script max in that run is 22.0.
- Headless checks added: dirty marking by a built event, rebuild without any tick at 0 objects (min over 320 ticks = N), new object visible, removal visible after the next rebuild, one rebuild only inside the throttle window (200 ticks via `set_rebuild_ticks`), no doubles; a config change gathers twice on two different ticks (max 1 per tick). Only one viewer is available headless (save players are offline), so the "two viewers on two platforms" case is covered by the per-tick gather counter, not by two real viewers.

