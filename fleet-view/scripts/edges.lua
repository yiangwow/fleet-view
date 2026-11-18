-- Platform edge art (0.4.6). Pure: which underside ("background") piece goes on which EMPTY tile next to the deck.
-- Evidence: tiles.lua `space-platform-foundation` transition.background_layout (spritesheets
-- space-platform-<kind>-background.png, scale 0.5, tile_height 8) + the PNGs: every frame is 64 px wide and 512 px (8 tiles)
-- tall, one row of `count` frames per orientation (side 2048x2048 = 4 rows x 32, double 512x1024 = 2 x 8, inner/outer
-- corner 1024x2048 = 4 x 16, u 256x2048 = 4 x 4; the o_transition has no background layout). The engine draws a
-- transition on the lower-layer tile (the empty one) that touches the deck, the sprite's top 64 px square sitting on it
-- (shift 0.5 * (tile_height - 1) tiles, i.e. it hangs 7 tiles down); row 0 of `side` = deck to the north (stone rim on top,
-- art hanging down). ROW tables below = which neighbour(s) a row is for (side/u: see the comments; checked against the
-- real platform with tools/shot-linux.sh ... edges).
local edges = {}

edges.SIDE, edges.DOUBLE, edges.INNER, edges.OUTER, edges.U = 1, 2, 3, 4, 5
-- name = sheet name, count = frames per row, rows, nv = how many of the frames per row are used (spread over the row)
edges.KINDS = {
  [1] = {sheet = "side", count = 32, rows = 4, nv = 6},
  [2] = {sheet = "double-side", count = 8, rows = 2, nv = 3},
  [3] = {sheet = "inner-corner", count = 16, rows = 4, nv = 3},
  [4] = {sheet = "outer-corner", count = 16, rows = 4, nv = 3},
  [5] = {sheet = "u", count = 4, rows = 4, nv = 2},
}
edges.FRAME_W, edges.FRAME_H = 64, 512
edges.HANG = 3.5   -- tiles the sprite centre sits below the tile centre ((8 - 1) / 2)

-- orthogonal neighbour bits (deck present): N 1, E 2, S 4, W 8; diagonals NE 16, SE 32, SW 64, NW 128
local N, E, S, W = 1, 2, 4, 8
-- side row by the deck neighbour
edges.SIDE_ROW = { [N] = 0, [E] = 1, [S] = 2, [W] = 3 }
-- double: N+S = 0, W+E = 1
-- inner corner row by the two orthogonal neighbours (key = sum of bits)
edges.INNER_ROW = { [N + E] = 0, [S + E] = 1, [S + W] = 2, [N + W] = 3 }
-- outer corner row by the diagonal bit
edges.OUTER_ROW = { [16] = 0, [32] = 1, [64] = 2, [128] = 3 }
-- u row by the open side (the one orthogonal neighbour that is empty)
edges.U_ROW = { [S] = 0, [W] = 1, [N] = 2, [E] = 3 }

function edges.code(kind, row, v) return kind * 100 + row * 10 + v end
function edges.parts(code) return math.floor(code / 100), math.floor(code / 10) % 10, code % 10 end
function edges.sprite_name(code)
  local kind, row, v = edges.parts(code)
  return "fv-b-" .. kind .. "-" .. row .. "-" .. v
end
-- sheet column of variant v (spread over the row)
function edges.column(kind, v)
  local k = edges.KINDS[kind]
  return math.floor(v * k.count / k.nv)
end

local function bits(m, mask) return m % (mask * 2) >= mask end
local BIT = { N, E, S, W }

-- mask: deck neighbours of an empty tile (bits above). h: deterministic hash of the tile (any integer >= 0).
-- Returns a list of codes (usually 1, 0 for an enclosed tile, more only for outer corners).
function edges.classify(mask, h)
  local out = {}
  local orth, n = {}, 0
  for _, b in ipairs(BIT) do if bits(mask, b) then orth[b] = true; n = n + 1 end end
  local function v(kind) return (h + kind * 5) % edges.KINDS[kind].nv end
  if n == 1 then
    for b in pairs(orth) do out[#out + 1] = edges.code(1, edges.SIDE_ROW[b], v(1)) end
  elseif n == 2 then
    if orth[N] and orth[S] then out[#out + 1] = edges.code(2, 0, v(2))
    elseif orth[W] and orth[E] then out[#out + 1] = edges.code(2, 1, v(2))
    else
      local key = 0
      for b in pairs(orth) do key = key + b end
      out[#out + 1] = edges.code(3, edges.INNER_ROW[key], v(3))
    end
  elseif n == 3 then
    for _, b in ipairs(BIT) do
      if not orth[b] then out[#out + 1] = edges.code(5, edges.U_ROW[b], v(5)) end
    end
  end
  -- outer corners: a diagonal deck tile whose two orthogonal tiles are both empty
  for _, d in ipairs({ 16, 32, 64, 128 }) do
    if bits(mask, d) then
      local a, b = N, E
      if d == 32 then a, b = S, E elseif d == 64 then a, b = S, W elseif d == 128 then a, b = N, W end
      if not orth[a] and not orth[b] then out[#out + 1] = edges.code(4, edges.OUTER_ROW[d], v(4)) end
    end
  end
  return out
end

-- tiles: {{x, y}} deck tiles; set: key(x, y) lookup of the deck (snapshot's key function); cx, cy: model centre.
-- Returns flat {x, y, code, ...} (x, y = tile centre minus (cx, cy), tile units).
function edges.compute(tiles, has, cx, cy)
  local out, n, seen = {}, 0, {}
  local DX = { 0, 1, 0, -1, 1, 1, -1, -1 }
  local DY = { -1, 0, 1, 0, -1, 1, 1, -1 }
  for _, t in ipairs(tiles) do
    for i = 1, 8 do
      local x, y = t.x + DX[i], t.y + DY[i]
      if not has(x, y) then
        local k = x * 1048576 + y
        if not seen[k] then
          seen[k] = true
          local m = (has(x, y - 1) and N or 0) + (has(x + 1, y) and E or 0) + (has(x, y + 1) and S or 0)
            + (has(x - 1, y) and W or 0) + (has(x + 1, y - 1) and 16 or 0) + (has(x + 1, y + 1) and 32 or 0)
            + (has(x - 1, y + 1) and 64 or 0) + (has(x - 1, y - 1) and 128 or 0)
          for _, code in ipairs(edges.classify(m, (x * 7 + y * 13) % 1024)) do
            out[n + 1], out[n + 2], out[n + 3] = x + 0.5 - cx, y + 0.5 - cy, code
            n = n + 3
          end
        end
      end
    end
  end
  return out
end

return edges
