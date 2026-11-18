-- Micro benchmark anchors (2026-11-16, 0.5.0 float research): what does moving N attached render objects cost?
local car = table.deepcopy(data.raw.car.car)
car.name = "fvm-car"
car.collision_mask = {layers = {}}
car.minable = nil
car.energy_source = {type = "void"}
car.flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"}
car.surface_conditions = nil
local ch = table.deepcopy(data.raw.character.character)
ch.name = "fvm-char"
ch.collision_mask = {layers = {}}
ch.flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"}
ch.minable = nil
data:extend{ch}
data:extend{
  {type = "simple-entity-with-owner", name = "fvm-anchor",
    picture = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
    collision_mask = {layers = {}}, selectable_in_game = false,
    flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "placeable-off-grid"}, hidden = true},
  car,
}

-- Is the move cost per render OBJECT or per picture (layer) inside it? The same floor picture as: one layer; two
-- layers with a shift (how Fleet View's sprites are built since 0.4.10: pad + picture); 16 layers in a 4x4 grid.
local function piece(shift) return {filename = "__space-age__/graphics/terrain/space-platform/space-platform-2x2.png",
  x = 0, y = 0, width = 128, height = 128, scale = 0.5, shift = shift} end
local l16 = {}
for i = 0, 3 do for j = 0, 3 do l16[#l16 + 1] = piece({i * 2 - 3, j * 2 - 3}) end end
data:extend{
  {type = "sprite", name = "fvm-1", layers = {piece({0, 0})}},
  {type = "sprite", name = "fvm-2", layers = {piece({0, 66}), piece({0, 66})}},
  {type = "sprite", name = "fvm-16", layers = l16},
}
