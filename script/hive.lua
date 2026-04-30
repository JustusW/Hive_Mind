-- Hive + hive-node lifecycle: tracking, storage chest, robot top-up, charting.
--
-- The "hive storage" entity is the hidden passive-provider chest that lives
-- next to each hive and holds creature items + pollution items. It is the only
-- inventory the network reads/writes from.

local shared = require("shared")
local State  = require("script.state")

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
  local s = State.get()
  s.hives_by_player[player_index] = s.hives_by_player[player_index] or {}
  s.hives_by_player[player_index][entity.unit_number] = {entity = entity}
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

-- Every valid hive across all players.
function M.all()
  local s = State.get()
  local result = {}
  for _, bucket in pairs(s.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      if hive_data.entity and hive_data.entity.valid then
        result[#result + 1] = hive_data.entity
      end
    end
  end
  return result
end

-- ── Worker corpse ─────────────────────────────────────────────────────────────

-- Spawn a corpse at `entity` to fake a death animation. Picks the corpse
-- matching the worker's base prototype: wriggler corpse if Space Age is
-- loaded, biter corpse otherwise. Used when a hive worker delivers a build
-- and we silently destroy it (we can't use entity.die() because that would
-- re-enter on_entity_died with a death-effect cascade we don't want for a
-- completed-delivery teardown).
function M.spawn_worker_corpse(entity)
  if not (entity and entity.valid) then return end
  local candidates = {"small-wriggler-pentapod-corpse", "small-biter-corpse"}
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
