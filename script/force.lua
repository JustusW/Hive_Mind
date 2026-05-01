-- Hive force, permission group, and recipe/tech enable matrix.

local shared = require("shared")

local M = {}

-- Recipes that should always be available to anyone on the hive force,
-- independent of any tech. The hm-hive recipe is conditional: only included
-- when the anchor-binding setting is OFF. With binding ON, the hive item
-- is handed out exactly once per player on join (Anchor.ensure_hive_available).
local function build_always_enabled()
  local list =
  {
    shared.recipes.pheromones_on,
    shared.recipes.pollution_generator
  }
  if not shared.feature_enabled("hm-anchor-binding") then
    list[#list + 1] = shared.recipes.hive
  end
  return list
end

-- Get or create the hivemind force. New forces are mutually friend +
-- cease-fired with `enemy` (so recruited biters mingle with vanilla biters
-- without fighting) and with `spectator` if it exists.
function M.get_hive()
  local force = game.forces[shared.force_name]
  if force then return force end
  force = game.create_force(shared.force_name)
  local enemy = game.forces.enemy
  force.set_cease_fire(enemy, true)
  force.set_friend(enemy, true)
  enemy.set_cease_fire(force, true)
  enemy.set_friend(force, true)
  if game.forces.spectator then
    force.set_cease_fire(game.forces.spectator, true)
    force.set_friend(game.forces.spectator, true)
    game.forces.spectator.set_cease_fire(force, true)
    game.forces.spectator.set_friend(force, true)
  end
  return force
end

function M.get_enemy()
  return game.forces.enemy
end

-- Permission group used by hive directors. Blocks every action a god-controller
-- could take to mine, drop, or transfer items.
function M.get_permission_group()
  local group = game.permissions.get_group(shared.permission_group)
  if group then return group end
  group = game.permissions.create_group(shared.permission_group)
  group.set_allows_action(defines.input_action.begin_mining, false)
  group.set_allows_action(defines.input_action.begin_mining_terrain, false)
  group.set_allows_action(defines.input_action.drop_item, false)
  group.set_allows_action(defines.input_action.fast_entity_transfer, false)
  group.set_allows_action(defines.input_action.inventory_transfer, false)
  group.set_allows_action(defines.input_action.stack_transfer, false)
  group.set_allows_action(defines.input_action.cursor_transfer, false)
  return group
end

local function is_hive_tech(name)
  -- All techs added by this mod are namespaced "hm-"; vanilla and other
  -- mods' techs are not. The hive directorate's tree shows only hive
  -- research, so we disable everything else on the hive force. Disabled
  -- techs are hidden from the tech-tree GUI in 2.0 (their default
  -- visible_when_disabled is false).
  return name:sub(1, 3) == "hm-"
end

-- Disable every recipe and every non-hive tech, then re-enable the always-on
-- recipes plus anything whose tech is already researched. Idempotent — safe
-- to call from on_init, on_configuration_changed, and after force creation.
function M.configure(force)
  if not (force and force.valid) then return end
  for _, recipe in pairs(force.recipes)      do recipe.enabled = false end
  for _, tech   in pairs(force.technologies) do
    tech.enabled = is_hive_tech(tech.name)
  end

  for _, name in pairs(build_always_enabled()) do
    if force.recipes[name] then force.recipes[name].enabled = true end
  end

  local function on_tech(tech_name, recipe_names)
    local tech = force.technologies[tech_name]
    if tech and tech.researched then
      for _, rname in pairs(recipe_names) do
        if force.recipes[rname] then force.recipes[rname].enabled = true end
      end
    end
  end
  on_tech(shared.technologies.hive_spawners,
          {shared.recipes.hive_node, shared.recipes.hive_spawner, shared.recipes.hive_spitter_spawner, shared.recipes.promote_node})
  on_tech(shared.technologies.hive_labs,     {shared.recipes.hive_lab})
  on_tech(shared.technologies.pheromone_vent, {shared.recipes.pheromone_vent})
  for _, tier in pairs(shared.worm_tiers) do
    on_tech(shared.worm[tier].tech, {shared.worm[tier].recipe})
  end
end

return M
