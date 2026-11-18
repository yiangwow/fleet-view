# Cargo bay / hub connection art (0.4.5)

Written before coding, corrected after the first in-game comparison (R1 was wrong: tile centres). Each rule: evidence, or marked GUESS. Sources: Factorio 2.1.24 `data/` + `doc-html/types/CargoBayConnections.html`.

## Contents
1. Where the art lives
2. How the engine picks a piece
3. Draw order
4. Hub dome and bay lids (not connections, same symptom)
5. Not done

## 1. Where the art lives
- `cargo-bay` and `space-platform-hub` both set `platform_graphics_set.connections = require("space-age/.../platform-connections")`
  (entities.lua l.250, l.492), which is `base/.../connections.lua` called with prefix `platform-`, heightE 118.
- Table: `tileset` (12 entries, each 1-2 groups of 1-2 variations), `tileset_mapping` (mask -> tileset index or list),
  `bridge_*` (5 pieces). A variation = 4 render-layer sprites (+ shadow/glow on some), all from sheet frame N
  (8 columns, size per layer in connections.lua). Layers: `lower-object-above-shadow` (sheet -0), `lower-object-overlay` (-1),
  `object-under` (-2), `object` (-3).

## 2. How the engine picks a piece
Found by experiment, not from the docs alone: `tools/shot-linux.sh <save> <out> conn` builds 25 small bay layouts on platform-3
(pair, stacked pair, offset 2, offset 1, diagonal, gap 1, gap 2, single, L, plus, 2x2) and shoots the REAL platform and the
Fleet View ship at the same scale; compare `fv-shot-conn-{fleetview,real}-N.png`.
- R1 PIECE GRID = A LATTICE OF TILE CORNERS, not tile centres. A corner point is occupied when all four tiles around it belong to
  a hub or bay, i.e. every footprint is shrunk by half a tile (a lone 4x4 bay = 3x3 points, the 8x8 hub = 7x7).
  Evidence: with pieces on tile centres the wall pieces of a lone bay stuck out about a tile further than the real ones; on the
  corner lattice the lone bay (shot 3, top left) matches the real one piece for piece, corners included. Touching entities
  stay occupied across the seam (lattice is the union, evidence: stacked pair, shot 1 bottom left, matches the real one).
- R2 MASK bits, doc "from the top-left corner going clockwise": TL 1, T 2, TR 4, R 8, BR 16, B 32, BL 64, L 128 over the 8
  neighbouring lattice points (the doc's "right tile has bit 7" is a typo for left). Evidence in `tileset_mapping`: 254 (only TL
  missing) -> 9 = top-left inner corner; 251 (TR) -> 10; 239 (BR) -> 12; 191 (BL) -> 11; 248 (TL, T, TR missing) -> 1 top wall;
  56 (R, BR, B) -> 5 top-left outer corner. The pieces on screen sit where these names say.
- R3 `tileset` order (comments in connections.lua): 1 top wall, 2 right wall, 3 bottom wall, 4 left wall, 5-8 outer corners
  TL/TR/BL/BR, 9-12 inner corners TL/TR/BL/BR; mapping values are 1-based. A mask can list 2-3 entries: all are drawn.
- R4 Mask 255 and masks missing from the mapping draw nothing (doc: "mapped to 0 won't be drawn"). Seen: interior is empty.
- R5 Piece position = the lattice point, frame layers keep their own `shift`. Evidence: R1 match.
- R6 BRIDGES sit on the seam between two entities that share an edge: `bridge_horizontal_*` for entities side by side
  (vertical seam), `bridge_vertical_*` for stacked ones, at the middle of the shared edge; `bridge_crossing` where four
  entities meet at one corner. Evidence: pair/stacked/offset shots show filler exactly there and nowhere for diagonal-only
  or gap-1/gap-2 layouts (no filler at all in the real shots); the 2x2 shot shows a crossing piece in the middle.
- R7 GUESS narrow vs wide: wide when the shared edge is >= 4 tiles (seen: 4 = wide-looking panel, 3 and 2 = thin strip /
  small panel; 1 not tested).
- R8 GUESS variation: tileset entry with two groups = group (x + y) % 2; variation inside a group and the 2-variation bridges are
  picked by a position hash (the engine's "random variation" is not reproducible). Visible effect: which of 2-4 near-twin frames.
- Known difference: in the real shots the seam bridge of a side-by-side pair looks paler / different from ours (same frames,
  maybe the other variant); the glow layers (red lamps) and the shadows are not drawn on purpose (rules).

## 3. Draw order
In game each piece layer sorts into the render layer of its name, with the entity art of the same layer:
hub-0 / bay-0 = `lower-object-above-shadow` (with connection layer 0), hub-1 = `lower-object-overlay` (conn 1),
hub-2 = `object-under` (conn 2), hub-3 / bay-3 = `object` (conn 3). Fleet View has ONE render layer for them, so it draws in
this order: entity art of layer 0, conn 0 of all tiles, entity layer 1, conn 1, entity layer 2, conn 2, entity `object` and
everything else, conn 3. Order inside one render layer between entity and connection is a GUESS (entity first).

## 4. Hub dome, bay lids
- Hub dome (VERIFIED in the shots, closed = frame 0): `hub.cargo_station_parameters.giga_hatch_definitions` = upper + lower giga hatch (frame 0 of a 20-frame, 'forward'
  animation) drawn at `above-inserters` / `cargo-hatch`. The hub picture only has the openings (hub-3 + occluders). Without the
  giga hatches the holes look open. Fix: draw frame 0 back + front of both.
- Bay lids (VERIFIED in the shots, closed = frame 0): `cargo-bay.hatch_definitions[1].hatch_graphics` = `shared-bay-hatch`, offset {-0.32, -1.5} + sprite shift. Not part of `platform_graphics_set.picture`.

## 5. Not done
- Glow layers (lamps), shadows and the hub cockpit animation are not drawn (CLAUDE.md rules: no shadow/glow/light).
- Draw order between a connection layer and entity art of the SAME render layer (R guess, section 3).
- Entities snap to tiles; positions are rounded to tile edges. Landing-pad bays (planet) are not used.
