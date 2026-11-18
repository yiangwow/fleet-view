# Fleet View — design

Date: 2026-10-23. Status: draft, awaiting owner approval.

## Contents

1. Intent
2. Goals, non-goals, anti-goals
3. Feature A — ships in the background (main)
4. Feature B — the rare shadow (extra)
5. Constraints
6. Decided by the owner
7. My calls (owner to check)
8. Left to the builder

## 1. Intent

A Factorio 2.1 Space Age mod for the owner's multiplayer server (nn1, two players:
holyskib and Sky--Wolf). Today, standing on a parked platform you see the planet
behind you (vanilla 2.1 backdrop) and nothing else. The owner wants the fleet to feel
present: your other platforms parked at the same planet should be visible out in
space, and very rarely, down on the planet, one of them should pass overhead as a
shadow. The feeling is "my other ships are out there", not a feature to manage.

## 2. Goals, non-goals, anti-goals

**Goals**
- On a platform, see the other platforms parked at the same space location in the
  background, recognisable as *those* ships.
- Watch them arrive and leave.
- On a planet, very rarely, a shared moment where a parked ship's shadow crosses the
  ground.

**Non-goals**
- Ships parked at other locations, or ships in transit (other than leaving/arriving
  at your location).
- Animated belts, moving items, working-machine animations on the distant ships.
- Interacting with the distant ships (clicking, opening, remote view).

**Anti-goals** (failure even if it works)
- The shadow being annoying. The owner said plainly it could be "annoying af". Once
  per hour, short, soft. If in doubt, rarer and softer.
- Distant ships that look pasted on: wrong lighting, moving 1:1 with the deck, or
  sitting on top of the deck.
- A noticeable UPS drop on the server or clients.
- Anything that can damage or desync the save.

## 3. Feature A — ships in the background (main)

Reference image: `docs/stills/ships-mid.png` (owner picked "mid"). Rough mock: real
platform layouts from the live save, buildings drawn from item icons, Nauvis from the
game's own textures.

- **Who is shown:** every platform of the viewer's force that is parked at the same
  space location as the platform the viewer is standing on, except the viewer's own.
- **Size:** about 4 px per tile at default zoom, while the viewer's deck is ~30 px per
  tile — i.e. the distant ships read as roughly 1/7 to 1/8 scale. Small enough to be
  scenery, big enough to recognise the shape and spot belts and solar arrays.
- **Look:** the real layout: foundation tiles + each entity drawn as a still picture
  in its footprint. No animation. Small warm running lights on the dark side.
- **Lighting:** match the planet backdrop. Read the location's
  `platform_backdrop.light_direction` / `light_color` (data stage) and shade each
  ship so the side facing the light is brighter. Nauvis: `light_direction =
  {-0.42, 0.23, 0.67}` (lit from upper-left).
- **Depth:** (superseded, see §6: ships are now fixed in space, no depth effect.) Originally parallax. The vanilla planet uses `parallax_strength = {0.95, 0.95}`
  (almost tracks the starfield). Distant ships sit between the deck and the planet:
  they move noticeably less than the deck when the camera pans, more than the planet.
- **Layering:** behind the viewer's deck and its entities, in front of the planet
  backdrop and stars. Never drawn over the deck.
- **Placement:** each other ship gets a stable spot in the sky (stable across reloads
  and the same for every viewer of that platform), spread so ships don't overlap each
  other or the planet's disc where avoidable.
- **Arrive / leave:** when a platform starts leaving the location, its picture
  shrinks and fades over a few seconds, drifting away along its travel direction.
  When one arrives, the reverse: it fades in small and grows to its slot. Modelled on
  the backdrop's `flight_approach_speed` feel. **Revised 2026-10-25 (0.4.0): ships
  always travel forward, up the screen, the way a platform flies** (details in §6). A
  leaving ship flies on ahead (up) from its spot while it shrinks and fades out; an
  arriving one comes up from behind, starting 40 tiles below its spot, while it fades
  in and grows, and ends exactly on the spot. Eased: departures speed up, arrivals brake
  into the spot.
- **Updates:** if a distant ship is rebuilt (entities added/removed), its picture
  catches up eventually. Real-time accuracy is not needed; minutes of lag is fine.

## 4. Feature B — the rare shadow (extra)

Reference: `factorio-ship-shadow-still.png` (owner's Downloads): a blurred, dark
footprint of PakaTube! over the base. Owner's verdict: fun, but must be rare.

- **When:** about once per hour of play, randomised (not on a fixed clock). Only on a
  planet surface where at least one of the force's platforms is parked above.
- **Shared:** one event for everyone. All players on that planet see the same shadow
  at the same moment, crossing the same ground.
- **What:** the footprint of one parked platform (random pick), scaled up, heavily
  blurred, semi-transparent dark, sliding across the ground in one direction and
  gone. Optional faint lights. No sound.
- **Where:** passes over the area where players are, so it is actually seen.
- **Not:** no gameplay effect (no solar dip, no darkness for biters, nothing).

## 5. Constraints

- Factorio **2.1.23** (server pinned, is-infra PR #18). Space Age on.
- Multiplayer and deterministic: no desyncs. Per-player visuals use the rendering
  API's per-player filters; any randomness via the game's RNG, not Lua `math.random`.
- Must work with the server's mod set (25 mods incl. Maraxsis 1.40, PlanetsLib).
- Published on the mod portal so the second player auto-downloads it.
- The 2.1 runtime API cannot render one surface into a picture on another
  (`LuaRendering` draws only shapes, sprites, text, lights; cameras are GUI-only), and
  the vanilla `PlatformBackdrop` is fixed per location at data stage. So distant ships
  must be redrawn from their layout by the mod.
- Removing the mod must leave the save clean (render objects only; no entities, no
  tiles added to any surface).

## 6. Decided by the owner

- Main feature: other platforms parked at the same location, visible from your
  platform, including arriving and leaving.
- Distance: "mid" (see §3), then revised twice after real screenshots (2026-10-23): layout F (screen-relative,
  follow 0.85) felt odd, so the owner decided (**2026-10-23**): **ships are fixed in space like normal objects**,
  above the viewer's deck. Placed once at draw time, never moved for viewer movement (no parallax, no follow).
  Placement is relative to the viewer's platform. **Revised 2026-10-23 (0.3.0): random spot per arrival around the
  deck, random size +-15%.** The row above the deck looked too static. When a ship becomes visible at a location
  (first draw, or each new arrival) a spot is rolled ONCE: any side of the deck (angle uniform around the deck's
  bounding-box centre), the ship's scaled box fully outside the deck's tile bounding box with a random gap of 3-12
  tiles, >= 4 tiles from other ships (up to 24 rolls, then pushed outward). Scale = 0.16 x random 0.85-1.15.
  Stored per viewer platform + ship (every viewer on the platform sees the same spot; survives save/load) until the
  ship leaves; a new arrival re-rolls. Random numbers come from a LuaRandomGenerator kept in storage (never
  math.random). Leaving ships shrink/fade/drift away from the deck centre along their spot's direction; arriving
  ones reverse into their spot (superseded by the next revision).
  **Revised 2026-10-25 (0.4.0): ships always travel forward, up the screen, eased.** Mod-portal feedback ("fade in and
  out from behind and in front instead of on the side"): drifting along the line from the deck centre to the spot looked
  sideways for ships left or right of the deck. The API gives a platform's route only as a space connection, no 2D
  heading, so "forward" is the platform's own up = screen up, the way a platform flies. A leaving ship flies on ahead
  (up) from its spot while it shrinks and fades out (shrink and fade as before); an arriving one comes up from behind,
  starting 40 tiles below its spot, fading in and growing, and ends exactly on the spot. The screen-y offset from the spot
  is side x 40 x f^2 (f = 0 parked .. 1 gone; side -1 ahead = leaving, +1 behind = arriving), so departures speed up and
  arrivals brake into the spot; x never changes, and shrink and fade stay linear in f. A ship that reverses mid-trip (a
  leave cancelled into an arrival, or the other way) keeps its side and retraces its path, so its position never jumps.
- Same light as the planet, arrival/departure like the planet approach, lights on the dark side. No depth effect.
- Shadow on the planet: about once per hour, shared by all players.
- **Player settings, each on/off:** building detail (off =
  floor shape + lights only), shadow. If something is too slow, each player turns off
  what they can live without. Builder should still use the cheap approach: one
  anchor per ship per viewer that all its pictures follow, floor tiles merged into
  few shapes. Whether an anchor can live in empty space beside a platform is the
  first thing to test.
- **Order:** Feature A (fleet view) is built and published on its own first, as
  release 1. Feature B (shadow) comes after as an extra, with a setting so players
  can switch it off.
- Not doing: Visible Planets (removed; vanilla 2.1 shows the planet), CleanFloor-style
  extras.

## 7. My calls (owner to check)

- Name "Fleet View", repo `~/fleet-view`.
- The shadow works over any planet where ships are parked, not only Nauvis.
- One shadow pass lasts about 20 seconds.
- Per-player mod settings to switch off each feature; a map setting for the shadow
  interval (default 60 min).
- Published on the mod portal under holyskib, MIT licence.
- **"Parked"** = the platform has a `space_location` (stopped there), whatever its
  schedule says. Leaving/arriving animations trigger on that changing.
- **"Standing on"** = the surface the player is currently looking at (character on
  the deck or remote view of the platform).
- **Spots** are relative to the viewer's platform (see §6, 2026-10-23): rolled once per ship arrival from a stored
  random generator, stored per viewer platform, so the same for every viewer on it. Superseded the hash-of-pair slots. Locations with no `platform_backdrop` get a neutral
  white light from the upper left.
- **Shadow target (release 2):** fires only if at least one player is on that planet;
  aims at one of them picked at random (game RNG). Not on surfaces without open sky:
  Maraxsis (underwater) is excluded; other modded enclosed surfaces are skipped via a
  small blacklist.

## 8. Left to the builder

- How entity pictures are obtained (data-stage sprites copied from entity graphics
  vs. item icons as fallback), and what to do for modded entities.
- How to keep the per-tick cost low (render-object count, update cadence for
  parallax, caching per ship).
- Exact render layer, exact parallax factor, light tinting math, slot layout.
- Arrival/departure timing (the path and curve were decided by the owner 2026-10-25 for 0.4.0: forward, up the
  screen, from/to 40 tiles, side x 40 x f^2; see §6).
- Shadow blur technique (stacked translucent shapes, pre-made blurred sprites, etc.).
- Test approach (headless load + benchmark on the real save; in-game look checked by
  screenshots).
