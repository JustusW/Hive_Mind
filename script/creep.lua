-- Organic creep growth.
--
-- A "creep front" cursor advances outward from each hive/node. Per call we
-- sample a few random angles and place creep tiles along three layers:
--
--   * 10% of attempts: probe the outer edge (front + 1) to expand territory
--   * 60%: land in the frontier band [front-3, front] to thicken the ring
--   * 30%: backfill [1, front-4] so inner gaps don't stay bare
--
-- The front advances by 1 only when an edge probe succeeded, and only with
-- 50% probability — so growth is gradual instead of jumping to max radius.
--
-- When a hive's creep first spreads we also flip the hive-labs tech to
-- researched (gameplay event unlocking the lab recipe).

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")

local M = {}

local function place_organic_creep(entity, record, max_radius, attempts)
  local surface = entity.surface
  local cx, cy  = entity.position.x, entity.position.y
  local rng     = game.create_random_generator(
    (entity.unit_number or 0) * 7919 + game.tick)
  local placed    = 0
  local tiles     = {}
  local front     = math.min(max_radius, math.max(2, math.floor(record.creep_front or 2)))
  local edge_hits = 0

  for _ = 1, attempts do
    local angle = rng() * math.pi * 2
    local dx, dy = math.cos(angle), math.sin(angle)
    local roll = rng(1, 100)
    local r
    if roll <= 10 then
      r = math.min(max_radius, front + 1)             -- edge probe
    elseif roll <= 70 then
      r = rng(math.max(1, front - 3), front)          -- frontier band
    else
      r = rng(1, math.max(1, front - 4))              -- inner backfill
    end

    local tx = math.floor(cx + dx * r + 0.5)
    local ty = math.floor(cy + dy * r + 0.5)
    local tile = surface.get_tile(tx, ty)
    if tile and tile.valid then
      local name = tile.name
      if not shared.is_creep_tile(name)
         and not name:find("water", 1, true)
         and not name:find("void",  1, true) then
        tiles[#tiles + 1] = {
          name     = shared.random_creep_tile(rng),
          position = {tx, ty}
        }
        placed = placed + 1
        if r >= front then edge_hits = edge_hits + 1 end
      end
    end
  end

  if edge_hits > 0 and front < max_radius and rng(1, 2) == 1 then
    record.creep_front = math.min(max_radius, front + 1)
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
    local storage = Hive.get_storage(hive)
    if storage then
      local placed = place_organic_creep(hive, storage, hive_r, hive_attempts)
      if placed then
        local tech = hive.force.technologies[shared.technologies.hive_labs]
        if tech and not tech.researched then
          tech.researched = true
          local recipe = hive.force.recipes[shared.recipes.hive_lab]
          if recipe then recipe.enabled = true end
        end
      end
    end
  end

  local s = State.get()
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      place_organic_creep(node, node_data, node_r, node_attempts)
    end
  end
end

return M
