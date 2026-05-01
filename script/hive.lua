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

-- Drain `from_hive`'s chest contents into `to_hive`'s chest. Both chests
-- must already exist; caller is responsible for creating `to_hive`'s if
-- needed (typically via Network.ensure_chest_at_primary). Used when a new
-- hive becomes the network primary, or when the dying primary's chest
-- needs to roll into the surviving primary's. Stack-by-stack copy. Returns
-- true on success.
function M.move_chest_contents(from_hive, to_hive)
  if not (from_hive and to_hive) then return false end
  local from_chest = M.get_chest(from_hive)
  local to_chest   = M.get_chest(to_hive)
  if not (from_chest and from_chest.valid and to_chest and to_chest.valid) then return false end
  if from_chest == to_chest then return true end
  local from_inv = from_chest.get_inventory(defines.inventory.chest)
  local to_inv   = to_chest.get_inventory(defines.inventory.chest)
  if not (from_inv and to_inv) then return false end
  for i = 1, #from_inv do
    local stack = from_inv[i]
    if stack and stack.valid_for_read then
      to_inv.insert{name = stack.name, count = stack.count}
    end
  end
  from_inv.clear()
  return true
end

-- ── Tracking ──────────────────────────────────────────────────────────────────

-- Subscriber registry for hive-side topology changes (hive built, hive
-- destroyed, node built, node destroyed, promote). Other modules call
-- `Hive.on_topology_change(fn)` once at require time and the registered
-- functions fire on every track/untrack/track_node/untrack_node. Used by
-- Scan, Network, Cost to invalidate their member-keyed caches without
-- circular imports — Hive doesn't need to know who's subscribed.
local topology_subscribers = {}

function M.on_topology_change(fn)
  topology_subscribers[#topology_subscribers + 1] = fn
end

local function fire_topology_change()
  for _, fn in ipairs(topology_subscribers) do
    fn()
  end
end

function M.track(player_index, entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  player_index = player_index or 0
  local s = State.get()
  s.hives_by_player[player_index] = s.hives_by_player[player_index] or {}
  s.hives_by_player[player_index][entity.unit_number] = {entity = entity}
  local record = M.get_storage(entity)
  if record then record.owner_player_index = player_index end
  M.invalidate_cache()
  fire_topology_change()
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
  fire_topology_change()
end

function M.track_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local s = State.get()
  s.hive_nodes[entity.unit_number] = {entity = entity}
  fire_topology_change()
end

function M.untrack_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local s = State.get()
  s.hive_nodes[entity.unit_number] = nil
  fire_topology_change()
end

-- ── Lab tracking ──────────────────────────────────────────────────────────────
--
-- Hive labs were previously discovered every 60 ticks via
-- `surface.find_entities_filtered{name = "hm-hive-lab"}` per surface. On
-- multi-surface saves that's the same per-surface cost as the old
-- `Hive.all()` had, and it's pure waste — labs only appear/disappear on
-- explicit build/destroy events. Track them in state and serve a cached
-- list. Same shape as the hive cache: lazy populate, event invalidate,
-- reconciler safety net.

function M.track_lab(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  if entity.name ~= shared.entities.hive_lab then return end
  local s = State.get()
  s.hive_labs[entity.unit_number] = {entity = entity}
  M.invalidate_labs_cache()
end

function M.untrack_lab(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  if entity.name ~= shared.entities.hive_lab then return end
  local s = State.get()
  s.hive_labs[entity.unit_number] = nil
  M.invalidate_labs_cache()
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
      for _, hive in pairs(hives) do
        if hive and hive.valid and hive.unit_number and not seen[hive.unit_number] then
          -- World-scan found a hive that's not in any player bucket.
          -- Backfill into the ownerless bucket (player_index 0) so
          -- Network.all_structures and Network.resolve_at see it on
          -- subsequent calls. Without this, a hive that landed in the
          -- world via a code path that didn't call Hive.track — most
          -- visibly the brief window inside on_legacy_hive_placed
          -- between the engine creating the new hive and Hive.track
          -- running on it — would be visible to Hive.all() but
          -- invisible to network resolution, breaking the
          -- "surviving-hive detection picks up replacement hives"
          -- guarantee in design.md → Network collapse.
          s.hives_by_player[0] = s.hives_by_player[0] or {}
          s.hives_by_player[0][hive.unit_number] = {entity = hive}
        end
        add_hive(result, seen, hive)
      end
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

-- ── Lab cache ────────────────────────────────────────────────────────────────
--
-- Same shape as Hive.all(). The world-scan rebuild is the safety net for
-- any code path that creates a hive_lab without calling track_lab (e.g.
-- migrating an old save where labs weren't tracked).
local cached_labs = nil

function M.invalidate_labs_cache()
  cached_labs = nil
end

local function rebuild_labs_cache()
  local s = State.get()
  local result = {}
  local seen = {}
  for unit_number, record in pairs(s.hive_labs) do
    local lab = record and record.entity
    if lab and lab.valid then
      seen[unit_number] = true
      result[#result + 1] = lab
    else
      s.hive_labs[unit_number] = nil
    end
  end
  local hive_force = Force.get_hive()
  if hive_force and game then
    for _, surface in pairs(game.surfaces) do
      local labs = surface.find_entities_filtered{
        name  = shared.entities.hive_lab,
        force = hive_force,
      }
      for _, lab in pairs(labs) do
        if lab.valid and lab.unit_number and not seen[lab.unit_number] then
          seen[lab.unit_number] = true
          result[#result + 1] = lab
          s.hive_labs[lab.unit_number] = {entity = lab}
        end
      end
    end
  end
  return result
end

function M.labs()
  return Telemetry.measure("hive_labs", function()
    if cached_labs then
      local fresh = {}
      for _, lab in ipairs(cached_labs) do
        if lab and lab.valid then fresh[#fresh + 1] = lab end
      end
      cached_labs = fresh
      return cached_labs
    end
    cached_labs = rebuild_labs_cache()
    return cached_labs
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
