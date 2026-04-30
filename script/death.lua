-- Hive death and entity removal.
--
-- When a hive dies its stored creature items respawn as living units on the
-- hive force (R6 in the requirements doc). Pollution items are discarded.

local shared = require("shared")
local State  = require("script.state")
local Force  = require("script.force")
local Hive   = require("script.hive")

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

-- Single handler for on_entity_died, on_robot_mined_entity, script_raised_destroy.
function M.on_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end

  if entity.name == shared.entities.hive then
    M.release_hive_contents(entity)
    Hive.untrack(entity)
  elseif entity.name == shared.entities.hive_node then
    Hive.untrack_node(entity)
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
