-- Pure: which connection pieces a ship's hub/bay tiles need (docs/bay-connections.md).
-- conn = flat {x, y, mask, ...} from snapshot.conn_tiles; map = {["<mask>"] = {tileset index...}} and tiles =
-- {[tileset index] = {group = {variation = "<col>-<row>"}}} from the mod-data "fv-conn".
local bays = {}

-- Frame id for a piece: tileset entry `ti`, group = (tx + ty) % 2 (GUESS), variation (73 tx + 151 ty + 31 tx ty) % 97 % n (GUESS).
local function pick(tiles, ti, tx, ty)
  local groups = tiles[ti]
  if not groups or #groups == 0 then return nil end
  local g = groups[(#groups > 1) and ((tx + ty) % 2 + 1) or 1]
  if not g or #g == 0 then return nil end
  return g[(tx * 73 + ty * 151 + tx * ty * 31) % 97 % #g + 1]
end

-- Returns a flat array {x, y, id, ...}: one entry per drawn piece (a tile can have several).
function bays.pieces(conn, map, tiles)
  local out, n = {}, 0
  for i = 1, #conn, 3 do
    local list = map[tostring(conn[i + 2])]
    if list then
      local tx, ty = math.floor(conn[i]), math.floor(conn[i + 1])
      for _, ti in ipairs(list) do
        local id = pick(tiles, ti, tx, ty)
        if id and id ~= "" then
          out[n + 1], out[n + 2], out[n + 3] = conn[i], conn[i + 1], id
          n = n + 3
        end
      end
    end
  end
  return out
end

-- Bridge pieces: bridges = flat {x, y, kind, ...}, kinds as in snapshot.conn_tiles, br = {[kind] = {variation ids}}.
-- Variation of a 2-variation bridge: (floor(x) + floor(y)) % 2 (GUESS). Returns {x, y, id, ...} appended to `out`.
function bays.bridge_pieces(bridges, br, out)
  out = out or {}
  local n = #out
  for i = 1, #bridges, 3 do
    local vars = br[bridges[i + 2]]
    if vars and #vars > 0 then
      local id = vars[(math.floor(bridges[i]) + math.floor(bridges[i + 1])) % #vars + 1]
      if id and id ~= "" then
        out[n + 1], out[n + 2], out[n + 3] = bridges[i], bridges[i + 1], id
        n = n + 3
      end
    end
  end
  return out
end

return bays
