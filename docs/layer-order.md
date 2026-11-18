# Draw order on the low render layers (GUI tests 2026-11-15)

Contents: Measured (1-11) · The fix (0.4.10) · Before the fix

Why: portal report Qazerowl "Rendering on top of edges" (2026-11-15): background ships draw over the hanging
underside art of the viewer's own deck. Tool: `tools/shot-linux.sh <save> <out> order|order2|order3|order4`
(`order*_step` in `tests/shot/fleet-view-shot/control.lua`, shifted test sprites in its `data.lua`; `FV_VP=1` for
the Visible Planets parts). Factorio 2.1.24, native Linux. Evidence PNGs: `~/Downloads/fleet-view-layer-order/`.

## Measured
1. Layers 0, 1, 2 and `arrow` sort script sprites by the y of the sprite CENTRE (lower on screen = on top).
   Not the top or bottom edge (`order2` + `order4` tall-vs-short pairs). An entity target's offset counts.
   Creation order, creation tick, `bring_to_front` and `move_to_back` change nothing there.
2. Layer 10 (`decals`) uses creation order (later = on top). It draws over bare deck floor (0.4.3 deck mode).
3. The deck's hanging underside is in layer 1's y-sort, keyed at about the first empty row under the deck
   (edge + 0.5), its art hanging below that. Layer 0 is under it; layer 1 deeper than the edge row and all of
   layer 2 draw over it. The older note "underside between layers 1 and 2" came from depth-0.5 markers (a tie).
4. Prototype `shift` (sprite prototype, data stage) moves the picture but NOT the sort key: the key stays at the
   target. A shifted red drawn 1.5 / 3 tiles below the edge with its target 10 tiles higher went UNDER the
   underside (`order3` U2), and under a blue it visually overlaps from below (K1). The shift is multiplied by
   the runtime `x_scale`/`y_scale` (K2) and turns with `orientation` (R: shift (0, 7) at orientation 0.25 drew
   at (-7, 0)).
5. `oriented_offset` (with `orientation_target`) moves the picture AND the key (K3, K4, U3, U4: no use for
   ordering). Its offset does not turn with `orientation`.
6. No culling seen: pictures 10 and 40 tiles from an off-screen target still drew (zoom 2 screenshot; the live
   game view was not checked).
7. Visible Planets (`order4` sweep, planet target y 13.0, oriented_offset y -4.3): layer-0 reds above y ~8.7
   (the planet's centre including its parallax offset) are hidden under the planet, the ones below are on top;
   layer-1 blues are on top everywhere. This is the 0.4.3 bug: our floor on layer 0 went under the planet
   wherever it sat above the planet's centre line.
8. Everything on layer 1 without shifts (the rejected 0.4.3 try, rerun): floor pieces lower on screen cover
   the bottom half of each building (rule 1).

9. A prototype shift above about 256 tiles is not drawn at all (`order5`: 20/100/150/200 drawn, 280 missing, for
   simple and layered sprites, prototype scale 1 and 0.5, any runtime scale).
10. Culling ignores the shift. A sprite is drawn only while its TARGET lies within the view grown by about half the
    FIRST layer's pixel size x the runtime scale (`order6`/`order7`: fitted margins 32 for a 64 px sprite, 64 for
    128 px, ~95 for the 214 px assembler; the prototype scale does not count). The size that counts is after the loader
    trims transparent borders (the mostly empty 64x512 platform edge frames lost their top-edge pieces). A shifted
    sprite near the top of the screen has its target above the view, so small ones vanished when zoomed in.
11. A second layer does not widen that margin; a FIRST layer does, if it cannot be trimmed: a 256 px picture with
    alpha 1/255 in its four corner pixels, drawn at 1/64 scale, in front of a 64 px floor piece kept it drawn at
    zoom 1-6 with its picture at the very top edge (`order8`, column c1). A fully transparent pad did nothing.
    The loader stores that pad once: atlas sizes unchanged with it on 1066 sprites.

## The fix (0.4.10, `scripts/sortkey.lua`)
- Every fleet-view sprite gets a downward prototype shift (data-final-fixes); draw.lua moves its target up by the
  same amount (shift x runtime scale, turned by `orientation`), so the picture is unchanged and the sort key sits
  above it: buildings, belts, lights 50 model tiles (6.8-9.2 screen tiles parked), floor 66, edge art 66 + 3.5
  (keyed at its tile row, like the game's own underside). All ship sprites on layer 1: over any layer-0 planet,
  under the viewer's hanging edges, floor under buildings.
- Floor, edge and dot sprites carry their size in the prototype scale and are drawn at runtime scale S, so every
  shift stays <= 85 (MAX_SHIFT, asserted at load).
- Sprites drawn with `orientation` (belts, undergrounds, splitters, pipes, walls, inserter arms) get turned copies
  `-fvq1..3` whose shift is pre-turned, so it points down after rotation.
- Every shifted sprite gets the corner-pixel pad (`graphics/pad.png`) as its first layer.
- GUI check `tools/shot-linux.sh <save> <out> under` (EXPECT=3): a strip of deck laid above a parked ship; 0.4.9
  draws the ship over the strip's hanging edge, 0.4.10 under it, also at zoom 4 with the ship at the top edge.
  `art`/`edges` ship pictures match 0.4.9 by eye (pixel diffs 0.5-6 of 255 mean; likely sub-pixel rounding of the moved targets, not checked further); `vp` unchanged.
- Stress bench (STRESS=10, 2 runs each, whole-script ms/tick mean, WoW running on the same PC for all runs): arrive
  0.4.9 13.87/14.53 vs 0.4.10 13.92/14.27, parked 11.75/11.91 vs 10.89/11.58, leave 19.99/19.79 vs 18.89/17.75: no
  increase. Render cost of the pad layer (FPS) not measured.
- Not handled: entity icons (no fleet-view sprite) are not shifted and still sort at their picture. While a ship
  travels at its smallest (0.53) the key offset shrinks too (3.6 screen tiles for the smallest ships).

## Before the fix
- Qazerowl: every ship sprite below the edge row sorted after the underside, so the whole ship drew over it.
