-- Hive + hive-node lifecycle: tracking, storage chest, robot top-up, charting.
--
-- The "hive storage" entity is the hidden passive-provider chest that lives
-- next to each hive and holds creature items + pollution items. It is the only
-- inventory the network reads/writes from.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Telemetry = require("script.telemetry")

local M = {}

-- ── Storage chest ─────────────────────────────────────────────────────────────

-- Get (or create) the storage record for `entity`. The record holds the
-- hidden chest reference; creep growth no longer needs per-record state.
function M.get_storage(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil end
  local s = State.get()
  local id = entity.unit_number
  if not s.hive_storage[id] then
    s.hive_storage[id] = {entity = entity, chest = nil}
  end
  local record = s.hive_storage[id]
  record.entity = entity
  return record
end

-- Returns the chest entity for `hive` if it exists and is still valid.
function M.get_chest(hive)
  local record = M.get_storage(hive)
  if not record then return nil end
  if record.chest and record.chest.valid then return record.chest end
  record.chest = nil
  return nil
end

-- Spawn the hidden storage chest next to `hive`. Falls back to the hive's tile
-- if no non-colliding position is available — visually overlapping is fine
-- because the chest renders as nothing.
function M.create_chest(hive)
  if not (hive and hive.valid) then return end
  local record = M.get_storage(hive)
  if not record then return end
  if record.chest and record.chest.valid then record.chest.destroy() end
  record.chest = nil

  local pos = hive.surface.find_non_colliding_position(
    shared.entities.hive_storage,
    {hive.position.x + 2, hive.position.y},
    6, 0.5)
  if not pos then
    pos = hive.surface.find_non_colliding_position(
      shared.entities.hive_storage, hive.position, 10, 0.5)
  end
  if not pos then pos = hive.position end

  local chest = hive.surface.create_entity{
    name        = shared.entities.hive_storage,
    position    = pos,
    force       = hive.force,
    raise_built = false
  }
  if chest and chest.valid then record.chest = chest end
end

-- ── Tracking ──────────────────────────────────────────────────────────────────

function M.track(player_index, entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  player_index = player_index or 0
  local s = State.get()
  s.hives_by_player[player_index] = s.hives_by_player[player_index] or {}
  s.hives_by_player[player_index][entity.unit_number] = {entity = entity}
  local record = M.get_storage(entity)
  if record then record.owner_player_index = player_index end
  M.invalidate_cache()
end

function M.untrack(entity)
  local s = State.get()
  for _, bucket in pairs(s.hives_by_player) do
    if bucket[entity.unit_number] then
      bucket[entity.unit_number] = nil
      break
    end
  end
  s.hive_storage[entity.unit_number] = nil
  M.invalidate_cache()
end

function M.track_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local s = State.get()
  s.hive_nodes[entity.unit_number] = {entity = entity}
end

function M.untrack_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local s = State.get()
  s.hive_nodes[entity.unit_number] = nil
end

-- First valid hive owned by `player_index` (or nil).
function M.get_primary(player_index)
  local s = State.get()
  local bucket = s.hives_by_player[player_index]
  if not bucket then return nil end
  for _, hive_data in pairs(bucket) do
    if hive_data.entity and hive_data.entity.valid then
      return hive_data.entity
    end
  end
end

function M.owner_player_index(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil end
  local s = State.get()
  local record = s.hive_storage[entity.unit_number]
  if record and record.owner_player_index then return record.owner_player_index end
  for player_index, bucket in pairs(s.hives_by_player) do
    if bucket[entity.unit_number] then return player_index end
  end
  return nil
end

local function add_hive(result, seen, entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  if seen[entity.unit_number] then return end
  seen[entity.unit_number] = true
  result[#result + 1] = entity
  M.get_storage(entity)
end

-- Every valid hive across all players.
--
-- The world-scan part (find_entities_filtered per surface) is expensive
-- enough that calling it on every tick across every Hive.all() call site
-- (Scan ×2, Creep, Workers, Labels, Cost, …) was eating ~2.8 sec/sec wall
-- time on a Space-Age save with several surfaces. The result almost never
-- changes — only when a hive is placed, promoted, or dies — so we cache
-- it module-locally and invalidate on those events (M.invalidate_cache,
-- called from M.track / M.untrack / lifecycle hooks). On a cache hit we
-- still filter for entity.valid in case something died via a path that
-- didn't go through untrack.
--
-- The cache lives only in module-local Lua state, so save/load
-- automatically starts cold. on_init and on_configuration_changed should
-- also call M.invalidate_cache() defensively.
local cached_hives = nil

function M.invalidate_cache()
  cached_hives = nil
end

local function rebuild_cache()
  local s = State.get()
  local result = {}
  local seen = {}
  for _, bucket in pairs(s.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      add_hive(result, seen, hive_data.entity)
    end
  end
  local hive_force = Force.get_hive()
  if hive_force and game then
    for _, surface in pairs(game.surfaces) do
      local hives = surface.find_entities_filtered{
        name  = shared.entities.hive,
        force = hive_force,
      }
      for _, hive in pairs(hives) do add_hive(result, seen, hive) end
    end
  end
  return result
end

function M.all()
  return Telemetry.measure("hive_all", function()
    if cached_hives then
      -- Filter out anything that became invalid since the last build.
      -- Cheap (~one entry per hive in the world; most ticks it's all
      -- valid and the loop is a flat copy).
      local fresh = {}
      for _, hive in ipairs(cached_hives) do
        if hive and hive.valid then fresh[#fresh + 1] = hive end
      end
      cached_hives = fresh
      return cached_hives
    end
    cached_hives = rebuild_cache()
    return cached_hives
  end)
end

-- ── Worker corpse ─────────────────────────────────────────────────────────────

-- Spawn a corpse at `entity` to fake a death animation when Space Age provides
-- the matching wiggler corpse. Base-only profiles skip the corpse instead of
-- showing a biter corpse for a wiggler-looking worker.
function M.spawn_worker_corpse(entity)
  if not (entity and entity.valid) then return end
  local candidates = {"small-wriggler-pentapod-corpse"}
  for _, name in ipairs(candidates) do
    if prototypes.entity[name] then
      pcall(function()
        entity.surface.create_entity{
          name = name, position = entity.position, force = entity.force
        }
      end)
      return
    end
  end
end

-- ── Charting ─────────────────────────────────────────────────────────────────

function M.chart(entity, range)
  if not (entity and entity.valid) then return end
  local pos = entity.position
  entity.force.chart(entity.surface,
    {{pos.x - range, pos.y - range}, {pos.x + range, pos.y + range}})
end

return M
