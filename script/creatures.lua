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
  -- Hive-side internal units (workers in particular) are not part of the
  -- creature economy. Excluding them here keeps absorption from trying to
  -- file a worker as `hm-creature-hm-hive-worker` (no such item exists,
  -- non-recoverable engine error) and keeps recruitment from overriding
  -- a worker's go_to_location command mid-route.
  if entity.name == shared.entities.hive_worker then return false end
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
      -- Defensive: only absorb units that actually have a registered
      -- creature item. Without this guard, a unit type with no matching
      -- hm-creature-* item raises a non-recoverable engine error inside
      -- inv.insert and tears down the whole on_tick chain.
      local item_name = shared.creature_item_name(unit.name)
      if prototypes.item[item_name] then
        unit.destroy({raise_destroy = true})
        inv.insert{name = item_name, count = 1}
      end
    end
  end
end

function M.tick_absorption()
  for _, hive in pairs(Hive.all()) do absorb_units_into_hive(hive) end
end

-- ── Recruitment ──────────────────────────────────────────────────────────────

-- Multiplier on the base recruit radius from completed levels of the
-- infinite hm-attraction-reach tech. `tech.level` is the next level to
-- research, so completed levels = level - 1 (clamped at zero).
local function reach_factor(force)
  if not (force and force.valid) then return 1 end
  local tech = force.technologies[shared.technologies.attraction_reach]
  if not tech then return 1 end
  local completed = tech.level - 1
  if completed < 0 then completed = 0 end
  return 1 + completed * shared.attraction_reach_step
end

-- Closest hive on the same surface as `entity`, or nil if there are none.
-- Used to redirect units recruited from a node (which has no chest) toward
-- a hive where they can actually be absorbed.
local function nearest_hive_on_surface(entity, hives)
  local best, best_dist
  for _, h in pairs(hives) do
    if h.valid and h.surface == entity.surface then
      local dx = h.position.x - entity.position.x
      local dy = h.position.y - entity.position.y
      local d2 = dx * dx + dy * dy
      if not best_dist or d2 < best_dist then
        best_dist = d2
        best = h
      end
    end
  end
  return best
end

-- Recruit (and reassign) any eligible units inside `radius` of `recruiter`,
-- commanding each toward `target`. `target` is either an entity (walked to
-- via go_to_location with radius 5) or a position table {position = {...}}
-- (walked to via go_to_location with radius 1, used for pheromone players).
local function recruit_around(recruiter, radius, target, enemy_force, hive_force)
  local units = recruiter.surface.find_entities_filtered{
    position = recruiter.position, radius = radius, type = "unit"
  }
  for _, unit in pairs(units) do
    if unit.valid
       and (unit.force == enemy_force or unit.force == hive_force)
       and M.is_for_role(unit, shared.creature_roles.attract) then
      if unit.force == enemy_force then unit.force = hive_force end
      if target.position then
        command_unit_to_position(unit, target.position)
      else
        command_unit_to_entity(unit, target.entity)
      end
    end
  end
end

-- Recruitment scan: every hive AND every hive node draws eligible units
-- from its construction box (hives 100×100, nodes 50×50, both scaled by
-- the Attraction Reach tech). Units recruited from a hive walk to that
-- hive. Units recruited from a node walk to the nearest hive on the same
-- surface, since nodes have no chest of their own. A player carrying
-- pheromones overrides every target — recruited units converge on them
-- regardless of which recruiter spotted them.
function M.tick_recruitment()
  local s           = State.get()
  local enemy_force = Force.get_enemy()
  local hive_force  = Force.get_hive()
  if not (enemy_force and hive_force) then return end

  local factor      = reach_factor(hive_force)
  local hive_radius = shared.ranges.hive      * factor
  local node_radius = shared.ranges.hive_node * factor

  -- One pheromone player wins: pick the first one we see that's actually
  -- holding the lure. Multiplayer with multiple pheromone-carriers is rare
  -- and the simple choice keeps the per-tick cost bounded.
  local pheromone_player
  for player_index in pairs(s.joined_players) do
    local player = game.get_player(player_index)
    if player and player.valid then
      local inv = player.get_main_inventory()
      if inv and inv.get_item_count(shared.items.pheromones) > 0 then
        pheromone_player = player
        break
      end
    end
  end

  local hives = Hive.all()

  -- Hives: target is the hive itself (or the pheromone player if any).
  for _, hive in pairs(hives) do
    local target = pheromone_player
                 and {position = pheromone_player.position}
                 or  {entity = hive}
    recruit_around(hive, hive_radius, target, enemy_force, hive_force)
  end

  -- Nodes: redirect to the nearest hive on the surface, since nodes don't
  -- absorb. Pheromone player still overrides.
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      local target
      if pheromone_player then
        target = {position = pheromone_player.position}
      else
        local hive = nearest_hive_on_surface(node, hives)
        if hive then target = {entity = hive} end
      end
      if target then
        recruit_around(node, node_radius, target, enemy_force, hive_force)
      end
    end
  end
end

return M
