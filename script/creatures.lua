-- Creature classification, absorption, and recruitment.
--
-- The remote interface lets other mods register/unregister specific entity
-- names against the `attract`, `store`, `consume` roles so modded biters can
-- participate in the hive economy. By default any entity with type == "unit"
-- is eligible.

local shared = require("shared")
local State  = require("script.state")
local Force  = require("script.force")
local Hive   = require("script.hive")

local M = {}

-- ── Role registry ────────────────────────────────────────────────────────────

function M.register_role(entity_name, role)
  local s = State.get()
  s.hive_roles[entity_name] = s.hive_roles[entity_name] or {}
  s.hive_roles[entity_name][role] = true
end

function M.unregister_role(entity_name, role)
  local s = State.get()
  if s.hive_roles[entity_name] then
    s.hive_roles[entity_name][role] = nil
  end
end

local function has_registered_role(entity_name, role)
  local s = State.get()
  local entry = s.hive_roles[entity_name]
  return entry and entry[role] == true
end

function M.is_for_role(entity, role)
  if not (entity and entity.valid) then return false end
  if has_registered_role(entity.name, role) then return true end
  return entity.type == "unit"
end

-- ── Unit commands ────────────────────────────────────────────────────────────

local function command_unit_to_entity(unit, target_entity)
  if not (unit and unit.valid and target_entity and target_entity.valid) then return end
  local commandable = unit.commandable
  if not commandable then return end
  commandable.set_command{
    type        = defines.command.go_to_location,
    destination = target_entity.position,
    distraction = defines.distraction.none,
    radius      = 5
  }
end

local function command_unit_to_position(unit, position)
  if not (unit and unit.valid and position) then return end
  local commandable = unit.commandable
  if not commandable then return end
  commandable.set_command{
    type        = defines.command.go_to_location,
    destination = position,
    distraction = defines.distraction.none,
    radius      = 1
  }
end

-- ── Absorption ───────────────────────────────────────────────────────────────

-- Eat any hive-eligible unit standing on the hive into its storage chest.
local function absorb_units_into_hive(entity)
  local chest = Hive.get_chest(entity)
  if not chest then return end
  local inv = chest.get_inventory(defines.inventory.chest)
  if not inv then return end

  local hive_force  = Force.get_hive()
  local enemy_force = Force.get_enemy()
  local units = entity.surface.find_entities_filtered{
    position = entity.position, radius = 6, type = "unit"
  }
  for _, unit in pairs(units) do
    if unit.valid
       and (unit.force == enemy_force or unit.force == hive_force)
       and M.is_for_role(unit, shared.creature_roles.store) then
      local item_name = shared.creature_item_name(unit.name)
      unit.destroy({raise_destroy = true})
      inv.insert{name = item_name, count = 1}
    end
  end
end

function M.tick_absorption()
  for _, hive in pairs(Hive.all()) do absorb_units_into_hive(hive) end
end

-- ── Recruitment ──────────────────────────────────────────────────────────────

-- Long-range scan from each player's primary hive: reassign vanilla biters
-- to the hive force and command them toward the hive. If the player carries
-- a pheromone item they become the recruitment target instead.
function M.tick_recruitment()
  local s            = State.get()
  local enemy_force  = Force.get_enemy()
  local hive_force   = Force.get_hive()

  for player_index in pairs(s.joined_players) do
    local player = game.get_player(player_index)
    if not (player and player.valid) then goto continue end

    local hive = Hive.get_primary(player_index)
    if not hive then goto continue end

    local has_pheromones = false
    local inv = player.get_main_inventory()
    if inv then has_pheromones = inv.get_item_count(shared.items.pheromones) > 0 end

    local units = hive.surface.find_entities_filtered{
      position = hive.position, radius = shared.ranges.recruit, type = "unit"
    }
    for _, unit in pairs(units) do
      if unit.valid
         and (unit.force == enemy_force or unit.force == hive_force)
         and M.is_for_role(unit, shared.creature_roles.attract) then
        if unit.force == enemy_force then unit.force = hive_force end
        local commandable = unit.commandable
        if commandable then
          if has_pheromones then
            command_unit_to_position(unit, player.position)
          else
            command_unit_to_entity(unit, hive)
          end
        end
      end
    end

    ::continue::
  end
end

return M
