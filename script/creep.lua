-- Organic creep growth (Eden model).
--
-- The Eden growth model is the standard "blob with a rough but coherent
-- perimeter" algorithm. Every new tile placed must be adjacent to an
-- existing creep tile, so the colony grows by accreting onto its own
-- boundary instead of sprinkling tiles in a circle.
--
-- Each tick:
--   * Seed the centre tile if it isn't creep yet.
--   * For each placement attempt, pick a uniformly random direction and
--     walk outward from the centre. The first non-creep tile we hit on
--     that ray is converted to creep. Because every ray must traverse
--     existing creep before reaching new ground, the blob expands along
--     its perimeter.
--   * Water and void terminate a ray — creep does not cross them.
--
-- When a hive's creep first spreads we also flip the hive-labs tech to
-- researched (gameplay event unlocking the lab recipe).

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")

local M = {}

local function is_blocked(name)
  return name:find("water", 1, true) ~= nil
      or name:find("void",  1, true) ~= nil
end

local function place_organic_creep(entity, max_radius, attempts)
  local surface = entity.surface
  local cx = math.floor(entity.position.x + 0.5)
  local cy = math.floor(entity.position.y + 0.5)
  local rng = game.create_random_generator(
    (entity.unit_number or 0) * 7919 + game.tick)
  local placed = 0
  local tiles  = {}

  -- Seed: ensure the centre tile is creep so the boundary walk has
  -- something to grow from on the first call.
  local centre = surface.get_tile(cx, cy)
  if centre and centre.valid
     and not shared.is_creep_tile(centre.name)
     and not is_blocked(centre.name) then
    tiles[#tiles + 1] = {name = shared.creep_tile, position = {cx, cy}}
    placed = placed + 1
  end

  for _ = 1, attempts do
    local angle = rng() * math.pi * 2
    local dx, dy = math.cos(angle), math.sin(angle)
    for r = 1, max_radius do
      local tx = math.floor(cx + dx * r + 0.5)
      local ty = math.floor(cy + dy * r + 0.5)
      local tile = surface.get_tile(tx, ty)
      if not (tile and tile.valid) then break end
      local name = tile.name
      if is_blocked(name) then break end
      if not shared.is_creep_tile(name) then
        tiles[#tiles + 1] = {name = shared.creep_tile, position = {tx, ty}}
        placed = placed + 1
        break  -- one new tile per ray
      end
    end
  end

  if #tiles > 0 then surface.set_tiles(tiles, true) end
  return placed > 0
end

function M.tick()
  local hive_attempts = shared.creep_tiles_per_call.hive
  local node_attempts = shared.creep_tiles_per_call.hive_node
  local hive_r        = shared.creep_radius.hive
  local node_r        = shared.creep_radius.hive_node

  for _, hive in pairs(Hive.all()) do
    local placed = place_organic_creep(hive, hive_r, hive_attempts)
    if placed then
      local tech = hive.force.technologies[shared.technologies.hive_labs]
      if tech and not tech.researched then
        tech.researched = true
        local recipe = hive.force.recipes[shared.recipes.hive_lab]
        if recipe then recipe.enabled = true end
      end
    end
  end

  local s = State.get()
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      place_organic_creep(node, node_r, node_attempts)
    end
  end
end

return M
