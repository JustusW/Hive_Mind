-- Hive Supremacy: while researched, anything standing on hive creep that isn't
-- on the hive force or a vanilla biter/spitter/spawner/worm takes damage.
--
-- Implementation:
--   * Once per `shared.intervals.supremacy` ticks, on every surface that has
--     at least one hive on the hive force, we scan around each hive and node
--     for entities on the player + neutral forces. (The hive force and the
--     enemy force are excluded by the find_entities_filtered force filter, so
--     hive-side entities and vanilla biters never even appear in the result
--     set — they don't need a name-by-name allowlist.)
--   * Each candidate is checked against the creep tile under its centre. Off
--     the creep => skipped.
--   * Damage per tick is derived from the entity's max_health and a target
--     lifetime (trees ~30s, everything else ~60s). We snapshot pollution data
--     for trees before damaging so we can release it to the world if the
--     damage call kills the entity.

local shared = require("shared")
local Hive   = require("script.hive")
local Force  = require("script.force")

local M = {}

local SCAN_FORCES = {"player", "neutral"}
-- We never damage these even if they slip into the player/neutral filter.
-- `character` covers any joined-but-not-god player; `corpse` and friends are
-- pure visuals; resources / fish / decorations should not block creep growth.
local SKIP_TYPE = {
  ["character"] = true,
  ["corpse"]    = true,
  ["resource"]  = true,
  ["fish"]      = true,
  ["item-entity"]    = true,
  ["entity-ghost"]   = true,
  ["tile-ghost"]     = true,
  ["highlight-box"]  = true,
  ["flying-text"]    = true,
  ["smoke"]          = true,
  ["smoke-with-trigger"] = true,
  ["sticker"]        = true,
  ["particle"]       = true,
  ["explosion"]      = true,
  ["construction-robot"] = true,
  ["logistic-robot"]     = true,
  ["spider-leg"]         = true
}

local function tree_pollution_amount(entity)
  local proto = entity.prototype
  if not proto then return shared.supremacy.tree_pollution_default end
  -- Trees expose their absorbable pollution as `emissions_per_second` on the
  -- prototype in 2.0. Fall back to autoplace_specification.tile_restriction
  -- absorption if missing. Lastly fall back to the configured default.
  local raw = proto.emissions_per_second
  if type(raw) == "table" then
    -- Some prototypes report a per-pollution-type table; sum the values.
    local total = 0
    for _, v in pairs(raw) do total = total + (tonumber(v) or 0) end
    if total > 0 then return total end
  elseif type(raw) == "number" and raw ~= 0 then
    -- emissions_per_second is negative for absorbers; we want a magnitude.
    return math.abs(raw) > 0 and (math.abs(raw) * 60) or shared.supremacy.tree_pollution_default
  end
  return shared.supremacy.tree_pollution_default
end

local function damage_amount(entity, lifetime_seconds)
  local hp = entity.prototype and entity.prototype.max_health or entity.health or 50
  if hp <= 0 then hp = 50 end
  if lifetime_seconds <= 0 then return hp end
  -- Convert "lifetime in seconds" to "damage per supremacy tick".
  local ticks_per_call = shared.intervals.supremacy
  local calls_per_second = 60 / ticks_per_call
  local total_calls = lifetime_seconds * calls_per_second
  return hp / total_calls
end

local function process_surface(surface, hive_force, areas)
  if not (surface and surface.valid) then return end
  if #areas == 0 then return end

  -- Collect candidates per area; dedupe by unit_number so overlapping hive
  -- boxes don't double-tap the same entity.
  local seen = {}
  local candidates = {}
  for _, area in ipairs(areas) do
    local found = surface.find_entities_filtered{ area = area, force = SCAN_FORCES }
    for _, entity in pairs(found) do
      if entity.valid then
        local id = entity.unit_number or (entity.name .. ":" .. entity.position.x .. ":" .. entity.position.y)
        if not seen[id] then
          seen[id] = true
          candidates[#candidates + 1] = entity
        end
      end
    end
  end

  if #candidates == 0 then return end

  local creep_name = shared.creep_tile

  for _, entity in ipairs(candidates) do
    if entity.valid and not SKIP_TYPE[entity.type] then
      local pos = entity.position
      local tile = surface.get_tile(pos.x, pos.y)
      if tile and tile.valid and tile.name == creep_name then
        local is_tree = entity.type == "tree"
        local pollution_burst = is_tree and tree_pollution_amount(entity) or 0
        local lifetime = is_tree and shared.supremacy.tree_lifetime or shared.supremacy.building_lifetime
        local dmg = damage_amount(entity, lifetime)
        if dmg > 0 then
          local pre_pos = {x = pos.x, y = pos.y}
          entity.damage(dmg, hive_force, "physical")
          if is_tree and not entity.valid and pollution_burst > 0 then
            surface.pollute(pre_pos, pollution_burst)
          end
        end
      end
    end
  end
end

function M.tick()
  local hive_force = Force.get_hive()
  if not hive_force then return end

  local tech = hive_force.technologies[shared.technologies.hive_supremacy]
  if not tech or not tech.researched then return end

  -- Bucket areas by surface so we only touch each surface once.
  local areas_by_surface = {}
  local surfaces_by_index = {}

  local function add(entity, range)
    if not (entity and entity.valid) then return end
    local surface = entity.surface
    local idx = surface.index
    surfaces_by_index[idx] = surface
    local areas = areas_by_surface[idx]
    if not areas then
      areas = {}
      areas_by_surface[idx] = areas
    end
    local x, y = entity.position.x, entity.position.y
    areas[#areas + 1] = {{x - range, y - range}, {x + range, y + range}}
  end

  for _, hive in pairs(Hive.all()) do
    add(hive, shared.creep_radius.hive)
  end
  -- Hive nodes also project creep, so they need supremacy coverage too.
  local State = require("script.state")
  local s = State.get()
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      add(node, shared.creep_radius.hive_node)
    end
  end

  for idx, areas in pairs(areas_by_surface) do
    process_surface(surfaces_by_index[idx], hive_force, areas)
  end
end

return M
