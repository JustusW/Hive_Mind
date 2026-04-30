-- Hive death and entity removal.
--
-- When a hive dies its stored creature items respawn as living units on the
-- hive force (R6 in the requirements doc). Pollution items are discarded.

local shared  = require("shared")
local State   = require("script.state")
local Force   = require("script.force")
local Hive    = require("script.hive")
local Network = require("script.network")
local Vent    = require("script.vent")
local Anchor  = require("script.anchor")

local M = {}

-- Respawn every creature item in `entity`'s storage chest as a living unit on
-- the hive force, then destroy the chest.
function M.release_hive_contents(entity)
  if not (entity and entity.valid) then return end
  local chest = Hive.get_chest(entity)
  if not chest then return end

  local inv = chest.get_inventory(defines.inventory.chest)
  if inv then
    local surface    = entity.surface
    local hive_force = Force.get_hive()
    for i = 1, #inv do
      local stack = inv[i]
      if stack and stack.valid_for_read then
        local unit_name = shared.creature_unit_name(stack.name)
        if unit_name and prototypes.entity[unit_name] then
          for _ = 1, stack.count do
            local pos = surface.find_non_colliding_position(
              unit_name, entity.position, 8, 0.5)
            if pos then
              surface.create_entity{
                name        = unit_name,
                position    = pos,
                force       = hive_force,
                raise_built = false
              }
            end
          end
        end
      end
    end
  end

  chest.destroy()
  local storage = Hive.get_storage(entity)
  if storage then storage.chest = nil end
end

-- One hive per player: when a player places a new hive, release and destroy
-- the previous one(s).
function M.destroy_previous_player_hives(player_index, new_hive)
  if not (new_hive and new_hive.valid) then return end
  local s = State.get()
  player_index = player_index or 0
  local new_hive_id = new_hive.unit_number
  s.hives_by_player[player_index] = s.hives_by_player[player_index] or {}
  local bucket = s.hives_by_player[player_index]

  local function destroy_hive(e)
    if not (e and e.valid and e ~= new_hive) then return end
    local id = e.unit_number
    M.release_hive_contents(e)
    if e.valid then
      e.destroy({raise_destroy = true})
    end
    s.hive_storage[id] = nil
    for _, other_bucket in pairs(s.hives_by_player) do
      other_bucket[id] = nil
    end
  end

  for unit_number, hive_data in pairs(bucket) do
    if unit_number ~= new_hive_id then
      destroy_hive(hive_data.entity)
    end
  end

  -- Older saves or missed build events can leave hives in the world without a
  -- player bucket. Treat those as this player's stale hive when placing a new
  -- one so the network recovers instead of reporting "no hive in range".
  for _, hive in pairs(Hive.all()) do
    local owner = Hive.owner_player_index(hive)
    if owner == nil or owner == player_index then
      destroy_hive(hive)
    end
  end
end

-- Network collapse on last hive lost (0.9.0).
--
-- When a hive dies, walk every surviving hive (via Hive.all() — which queries
-- the surface, so a just-placed-but-untracked replacement hive IS counted)
-- and resolve its network. Any hive-side building on the same surface that
-- doesn't end up in a surviving network is orphaned and destroyed.
--
-- Player-placed enemy-force entities (real biter-spawners, spitter-spawners,
-- worm-turrets after the build-time swap) survive — they revert to ordinary
-- vanilla nests/turrets.
local function collapse_orphans(dead_hive)
  if not (dead_hive and dead_hive.valid) then return end
  local surface = dead_hive.surface
  if not (surface and surface.valid) then return end
  local hive_force = Force.get_hive()
  if not hive_force then return end

  -- Build the set of "surviving" member unit_numbers across all networks.
  local survivors = {}
  for _, hive in pairs(Hive.all()) do
    if hive and hive.valid and hive ~= dead_hive and hive.surface == surface then
      local network = Network.resolve_at(surface, hive.position)
      if network then
        for _, m in ipairs(network.members) do
          if m.entity and m.entity.unit_number then
            survivors[m.entity.unit_number] = true
          end
        end
      end
    end
  end

  -- Pheromone vents: resolved via placer hive. A vent whose placer's hive
  -- isn't in any surviving network is orphaned.
  local s = State.get()
  for unit_number, record in pairs(s.pheromone_vents) do
    local vent = record.entity
    if vent and vent.valid and vent.surface == surface then
      local placer_hive = Vent.placer_hive(record.placer_player_index)
      local kept = placer_hive and placer_hive.valid
                   and placer_hive ~= dead_hive
                   and survivors[placer_hive.unit_number]
      if not kept then
        vent.destroy({raise_destroy = true})
        s.pheromone_vents[unit_number] = nil
      end
    end
  end

  -- Hive nodes, hive labs, hive storage chests — destroy orphans on hive force.
  -- Storage chests release creatures first via release_hive_contents on their
  -- owning hive (already handled per-hive on hive death), so what's left here
  -- is orphaned chests whose hive is gone but whose creatures should still go
  -- back to the world before the chest disappears.
  local orphan_filter = surface.find_entities_filtered{
    force = hive_force,
    name  = {
      shared.entities.hive_node,
      shared.entities.hive_lab,
      shared.entities.hive_storage
    }
  }
  for _, e in pairs(orphan_filter) do
    if e.valid and not survivors[e.unit_number] then
      if e.name == shared.entities.hive_storage then
        -- Release storage as live units — same loop as release_hive_contents
        -- but the chest stands alone here.
        local inv = e.get_inventory(defines.inventory.chest)
        if inv then
          for i = 1, #inv do
            local stack = inv[i]
            if stack and stack.valid_for_read then
              local unit_name = shared.creature_unit_name(stack.name)
              if unit_name and prototypes.entity[unit_name] then
                for _ = 1, stack.count do
                  local pos = surface.find_non_colliding_position(
                    unit_name, e.position, 8, 0.5)
                  if pos then
                    surface.create_entity{
                      name = unit_name, position = pos,
                      force = hive_force, raise_built = false
                    }
                  end
                end
              end
            end
          end
        end
      end
      e.destroy({raise_destroy = true})
    end
  end

  -- Hive workers on the orphaned network die; surviving workers stay.
  local workers = surface.find_entities_filtered{
    force = hive_force,
    name  = shared.entities.hive_worker
  }
  for _, w in pairs(workers) do
    if w.valid and not survivors[w.unit_number] then
      w.die()
    end
  end

  -- Drop bucket entries whose anchor unit_number is no longer a survivor.
  for key in pairs(s.recruit_buckets or {}) do
    if not survivors[key] then s.recruit_buckets[key] = nil end
  end
end

-- Returns the first surviving hive (excluding `dying`) on `dying`'s network.
-- nil if the dying hive is the only hive in its network.
local function surviving_network_mate(dying)
  if not (dying and dying.valid) then return nil end
  local network = Network.resolve_at(dying.surface, dying.position)
  if not network then return nil end
  for _, hive in pairs(network.hives) do
    if hive and hive.valid and hive ~= dying then return hive end
  end
  return nil
end

-- Move every stack from the dying hive's chest into a survivor's chest.
-- Both hives' chests are part of the same shared-storage network, so the
-- merge is purely physical re-homing — no creature disgorge, no pollution
-- loss. Returns true if the chest was successfully drained.
local function merge_chest_into(dying, survivor)
  local from = Hive.get_chest(dying)
  local to   = Hive.get_chest(survivor)
  if not (from and from.valid and to and to.valid) then return false end
  local from_inv = from.get_inventory(defines.inventory.chest)
  local to_inv   = to.get_inventory(defines.inventory.chest)
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

-- Single handler for on_entity_died, on_robot_mined_entity, script_raised_destroy.
function M.on_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end

  if entity.name == shared.entities.hive then
    -- Shared-storage rule: the network only collapses when EVERY hive in
    -- it is destroyed. Killing one hive while another survives just merges
    -- this hive's chest into a surviving hive's chest — nothing else
    -- changes. The full disgorge / orphan-collection / re-grant pass only
    -- runs when no network mate remains.
    local survivor = surviving_network_mate(entity)
    if survivor then
      merge_chest_into(entity, survivor)
      -- Destroy the now-empty chest and untrack the hive without running
      -- release_hive_contents (no creatures left to release) or
      -- collapse_orphans (the network is intact).
      local record = State.get().hive_storage[entity.unit_number]
      if record and record.chest and record.chest.valid then
        record.chest.destroy()
      end
      Hive.untrack(entity)
    else
      M.release_hive_contents(entity)
      Hive.untrack(entity)
      collapse_orphans(entity)
    end

    -- Drop any pending-construction record so the anchor tick doesn't try
    -- to lock-in a corpse, and re-grant a starter hive to every joined
    -- player who lost their last hive. The grant is idempotent — players
    -- who still have a hive get nothing.
    State.get().pending_anchor_constructions[entity.unit_number] = nil
    for player_index in pairs(State.get().joined_players) do
      Anchor.ensure_hive_available(game.get_player(player_index))
    end
  elseif entity.name == shared.entities.hive_node then
    Hive.untrack_node(entity)
  elseif entity.name == shared.entities.pheromone_vent then
    State.get().pheromone_vents[entity.unit_number] = nil
  elseif entity.name == shared.entities.pollution_generator then
    State.get().pollution_generators[entity.unit_number] = nil
  elseif entity.name == shared.entities.hive_storage then
    -- A storage chest got destroyed independently of its hive. Clear our
    -- reference so the next access recreates it.
    local s = State.get()
    for _, bucket in pairs(s.hives_by_player) do
      for _, hive_data in pairs(bucket) do
        local hive = hive_data.entity
        if hive and hive.valid then
          local record = s.hive_storage[hive.unit_number]
          if record and record.chest == entity then record.chest = nil end
        end
      end
    end
  end
end

return M
