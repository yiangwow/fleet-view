# Shadows and glows on background ships (0.4.7)

## Contents
- Engine findings
- Light direction
- Implementation
- Cost
- Open points

## Engine findings (tested in game, Factorio 2.1.24 native, nn1 save, `tools/shot-linux.sh dirs`)
- A `sprite` prototype WITH `draw_as_shadow` / `draw_as_glow` layers loads fine, but `rendering.draw_sprite` ignores
  those flags: the layer is drawn as an ordinary sprite. A shadow shows as a hard opaque black box, a glow layer
  (black background, colour in the lamps) as a black box with red dots (try1, `docs/shots` not kept; owner shots in
  ~/Downloads/fleet-view-shadows/try1).
- The shadow pngs have a real alpha silhouette (palette png with tRNS). Without the flag the alpha works: a
  flagless copy drawn with tint alpha 0.4 gives a soft shadow cast to the right, like the real platform (try2).
- Glow pngs have no useful alpha (black = nothing, additive in the engine's glow pass). Every variant tried still
  drew black boxes with red dots: flagless alpha blend, `blend_mode = "additive"` on the sprite layer, `draw_sprite`
  `light_mode` = "light" and = "glow". Glow therefore NOT shipped.
- LuaRendering::draw_sprite has `light_mode` ("occluder" default / "light" / "glow"); draw_light takes a sprite as a gradient.

## Light direction
Vanilla platform shadows are baked into the shadow pngs (one fixed direction, right/down). `platform_backdrop.light_direction`
(mod-data `fv-lights`) only shades the planet backdrop. No per-location shadow change exists, so shadows do NOT use it.

## Implementation
- data-final-fixes: for every entity with such layers, `fv-e-<name>-sh` (shadow), plus
  `-sh-<dir>` variants when that direction differs (fusion generator). Flags stripped (`pictures.clean(l, true)`).
  `pictures.find_layers(proto, dir, kind)`, kind nil / "shadow" / "glow".
- draw.plan_ship: all shadows first (after floor + flat rects, before building art, same layer as the buildings so
  creation order puts them under), tint white alpha 0.4 (not darkened by the ship shade).
- Old stored models need nothing: sprites are looked up by entity name at draw time.

## Cost (nn1 save, `dirs` ship, objects from the shot log)
Render objects: 1525 before (0.4.5) -> 1687 after (+162, +10.6%). No setting: the cost is one extra sprite per entity with a
shadow. Bench numbers: see the 0.4.7 commit message / report.

## Open points
- Glow (lamp emission, red bay lamps) is not possible with script sprites; the only route left would be pre-converting the
  glow pngs to RGBA (alpha = brightness) at build time and shipping them, or `draw_light` per lamp (night only). Not done.
- Shadows of buildings at the ship edge fall over space as a faint dark smear (alpha 0.4 black); mild.
