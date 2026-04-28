local util = require("script/script_util")
local shared = require("shared")
local data =
{
  spawner_tick_check = {},
  ghost_tick_check = {},
  not_idle_units = {},
  clear_rendering = false,
  destroy_factor = 0.002,
  enemy_attack_pollution_consumption_modifier = 1,
  can_spawn = false,
  pop_count = {},
  max_pop_count = 1000,
  generated_events = {}
}

local unit_spawned_event
local clear_tracked_render_references
local rebuild_rendering
local register_ghost_data

local persistent = storage or global

local get_entity_prototypes = function()
  if prototypes and prototypes.entity then
    return prototypes.entity
  end
  return game.entity_prototypes
end

local render_object_valid = function(object)
  local ok, valid = pcall(function()
    return object and object.valid
  end)
  return ok and valid
end

local destroy_render_object = function(object)
  if not render_object_valid(object) then return end
  object.destroy()
end

local set_render_object_text = function(object, text)
  if not render_object_valid(object) then return end
  object.text = text
end

local get_technology_prototypes = function()
  if prototypes and prototypes.technology then
    return prototypes.technology
  end
  return game.technology_prototypes
end

local get_item_production_statistics = function(force, surface)
  if not (force and force.valid) then return end
  if force.get_item_production_statistics then
    return force.get_item_production_statistics(surface)
  end
  return force.item_production_statistics
end

local get_entity_build_count_statistics = function(force, surface)
  if not (force and force.valid) then return end
  if force.get_entity_build_count_statistics then
    return force.get_entity_build_count_statistics(surface)
  end
  return force.entity_build_count_statistics
end

local get_destroy_factor = function()
  return data.destroy_factor
end

local get_enemy_attack_pollution_consumption_modifier = function()
  return data.enemy_attack_pollution_consumption_modifier
end

local get_max_pop_count = function()
  return data.max_pop_count
end

local can_spawn_units = function(force_index)
  return data.pop_count[force_index] < get_max_pop_count()
end

local names = names.deployers
local units = names.units
--todo allow other mods to add deployers
local spawner_map = {}
for k, deployer in pairs (names) do
  spawner_map[deployer] = true
end

local direction_enum =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.south] = {0, 2},
  [defines.direction.east] = {2, 0},
  [defines.direction.west] = {-2, 0}
}

local get_spawn_position = function(source, prototype)
  local surface = source.surface
  local source_box = source.bounding_box
  local collision_box = prototype.collision_box
  local half_width = math.max(math.abs(collision_box.left_top.x), math.abs(collision_box.right_bottom.x))
  local half_height = math.max(math.abs(collision_box.left_top.y), math.abs(collision_box.right_bottom.y))
  local margin = 0.25
  local positions =
  {
    [defines.direction.north] = {source.position.x, source_box.left_top.y - half_height - margin},
    [defines.direction.south] = {source.position.x, source_box.right_bottom.y + half_height + margin},
    [defines.direction.east] = {source_box.right_bottom.x + half_width + margin, source.position.y},
    [defines.direction.west] = {source_box.left_top.x - half_width - margin, source.position.y}
  }

  local preferred = positions[source.direction] or positions[defines.direction.north]
  local deploy_position = surface.find_non_colliding_position(prototype.name, preferred, 4, 0.25)
  if deploy_position then
    return deploy_position
  end

  return surface.find_non_colliding_position(prototype.name, source.position, 8, 0.5)
end

local deploy_unit = function(source, prototype)
  if not (source and source.valid and prototype) then return end
  local direction = source.direction
  local name = prototype.name
  local surface = source.surface
  local force = source.force
  local create_entity = surface.create_entity
  local item_production_statistics = get_item_production_statistics(force, surface)
  local deploy_position = get_spawn_position(source, prototype)
  if not deploy_position then
    return
  end
  local blood = {name = "blood-explosion-big", position = deploy_position}
  local create_param = {name = name, position = deploy_position, force = force, direction = direction, raise_built = true}
  create_entity(blood)
  local unit = create_entity(create_param)
  if unit and unit.valid then
    if item_production_statistics then
      item_production_statistics.on_flow(name, 1)
    end
    local index = force.index
    data.pop_count[index] = data.pop_count[index] + 1
    script.raise_event(unit_spawned_event, {entity = unit, spawner = source})
    return unit
  end
end

local get_finished_unit_count = function(entity, recipe_name)
  local output_inventory = entity.get_output_inventory and entity.get_output_inventory()
  if output_inventory and output_inventory.valid then
    return output_inventory.get_item_count(recipe_name)
  end
  return entity.get_item_count(recipe_name)
end


--Max pollution each spawner can absorb is 10% of whatever the chunk has.
local pollution_percent_to_take = 0.1

local min_to_take = 1

local prototype_cache = {}

local get_prototype = function(name)
  local prototype = prototype_cache[name]
  if prototype then return prototype end
  prototype = get_entity_prototypes()[name]
  prototype_cache[name] = prototype
  return prototype
end

local required_pollution = shared.required_pollution
local pollution_cost_multiplier = shared.pollution_cost_multiplier
local growth_node_name = shared.growth_node
local growth_node_prefix = shared.growth_node_prefix
local growth_progress_item_name = shared.growth_progress_item
local growth_recipe_prefix = shared.growth_recipe_prefix
local growth_cancel_recipe = shared.growth_cancel_recipe

local get_required_pollution = function(name)
  return required_pollution[name] * pollution_cost_multiplier
end

local growth_recipe_to_target = {}
local growth_node_names = {}
for target_name, _ in pairs(required_pollution) do
  growth_recipe_to_target[growth_recipe_prefix .. target_name] = target_name
  growth_node_names[#growth_node_names + 1] = growth_node_prefix .. target_name
end

local is_growth_node = function(entity)
  return entity and entity.valid and entity.name and entity.name:find(growth_node_prefix, 1, true) == 1
end

local get_growth_recipe_name = function(target_name)
  return growth_recipe_prefix .. target_name
end

local get_growth_node_entity_name = function(target_name)
  return growth_node_prefix .. target_name
end

local get_growth_node_inventory = function(entity)
  if not is_growth_node(entity) then return end
  return entity.get_inventory(defines.inventory.assembling_machine_input)
end

local get_growth_node_target_name = function(entity)
  if not is_growth_node(entity) then return end
  local derived_name = entity.name:sub(#growth_node_prefix + 1)
  if required_pollution[derived_name] then
    return derived_name
  end
  local recipe = entity.get_recipe()
  if not recipe then return end
  return growth_recipe_to_target[recipe.name]
end

local growth_node_should_cancel = function(entity)
  if not is_growth_node(entity) then return end
  local recipe = entity.get_recipe()
  return recipe and recipe.name == growth_cancel_recipe
end

local set_growth_node_progress = function(entity, remaining)
  local inventory = get_growth_node_inventory(entity)
  if not inventory then return end
  inventory.clear()
  local whole_remaining = math.max(0, math.floor((remaining or 0) + 0.5))
  if whole_remaining > 0 then
    inventory.insert{name = growth_progress_item_name, count = whole_remaining}
  end
end

local get_growth_node_progress = function(entity)
  local inventory = get_growth_node_inventory(entity)
  if not inventory then return end
  return inventory.get_item_count(growth_progress_item_name)
end

local create_growth_node = function(surface, position, force, target_name, remaining_pollution, direction)
  local entity = surface.create_entity
  {
    name = get_growth_node_entity_name(target_name),
    position = position,
    force = force,
    direction = direction,
    raise_built = false
  }
  if not (entity and entity.valid) then return end
  entity.active = false
  entity.operable = true
  entity.set_recipe(get_growth_recipe_name(target_name))
  set_growth_node_progress(entity, remaining_pollution)
  return entity
end

local convert_ghost_to_growth_node = function(ghost_entity, target_name, remaining_pollution)
  if not (ghost_entity and ghost_entity.valid and ghost_entity.type == "entity-ghost") then return end
  local surface = ghost_entity.surface
  local position = ghost_entity.position
  local force = ghost_entity.force
  local direction = ghost_entity.direction
  ghost_entity.destroy()
  return create_growth_node(surface, position, force, target_name, remaining_pollution, direction)
end

local try_get = function(fn)
  local ok, value = pcall(fn)
  if ok then
    return value
  end
end

local get_unit_pollution_cost = function(prototype)
  local pollution_to_join_attack = try_get(function()
    return prototype.pollution_to_join_attack
  end)
  if pollution_to_join_attack then
    return pollution_to_join_attack
  end

  local absorptions_to_join_attack = try_get(function()
    return prototype.absorptions_to_join_attack
  end)
  if absorptions_to_join_attack and absorptions_to_join_attack.pollution then
    return absorptions_to_join_attack.pollution
  end

  local attack_parameters = try_get(function()
    return prototype.attack_parameters
  end)
  if attack_parameters and attack_parameters.pollution_to_join_attack then
    return attack_parameters.pollution_to_join_attack
  end
  return 0
end

local min = math.min

local progress_color = {r = 0.8, g = 0.8}
local spawning_color = {r = 0, g = 1, b = 0, a = 0.5}

-- 1 pollution = 1 energy of crafting

local ensure_spawner_rendering = function(spawner_data, progress_override)
  local entity = spawner_data.entity
  if not (entity and entity.valid) then return end

  local progress = progress_override
  if progress == nil then
    progress = entity.crafting_progress
  end

  local progress_bar = spawner_data.progress
  if progress_bar and (not render_object_valid(progress_bar)) then
    progress_bar = nil
    spawner_data.progress = nil
  end

  if render_object_valid(progress_bar) then
    set_render_object_text(progress_bar, math.floor(progress * 100) .. "%")
  else
    progress_bar = rendering.draw_text
    {
      text = math.floor(progress * 100) .. "%",
      surface = entity.surface,
      target = entity,
      color = progress_color,
      alignment = "center",
      forces = {entity.force},
      scale = 3,
      only_in_alt_mode = true
    }
    spawner_data.progress = progress_bar
  end
end

local check_spawner = function(spawner_data)
  local entity = spawner_data.entity
  if not (entity and entity.valid) then return true end
  --entity.surface.create_entity{name = "flying-text", position = entity.position, text = game.tick % 60}

  local recipe = entity.get_recipe()
  if not recipe then
    if render_object_valid(spawner_data.progress) then
      destroy_render_object(spawner_data.progress)
      spawner_data.progress = nil
    end
    return
  end

  local force = entity.force
  local surface = entity.surface
  local position = entity.position
  local progress = entity.crafting_progress

  local can_spawn = can_spawn_units(force.index)
  entity.active = can_spawn
  if can_spawn then
    local recipe_name = recipe.name
    local item_count = get_finished_unit_count(entity, recipe_name)
    if item_count > 0 then
      local unit = deploy_unit(entity, get_prototype(recipe_name))
      if unit then
        entity.remove_item{name = recipe_name, count = 1}
      end
    end
  end

  if progress < 1 then

    local pollution = surface.get_pollution(position)
    local pollution_to_take = pollution * pollution_percent_to_take
    if pollution_to_take < min_to_take then
      pollution_to_take = min(min_to_take, pollution)
    end

    local energy = recipe.energy
    local current_energy = energy * progress

    pollution_to_take = min(pollution_to_take, energy - current_energy)

    current_energy = current_energy + pollution_to_take

    progress = current_energy / energy

    entity.crafting_progress = progress

    surface.pollute(position, -pollution_to_take)
    game.get_pollution_statistics(surface).on_flow(entity.name, -pollution_to_take)
    local item_production_statistics = get_item_production_statistics(force, surface)
    if item_production_statistics then
      item_production_statistics.on_flow(shared.pollution_proxy, -pollution_to_take)
    end
  end

  ensure_spawner_rendering(spawner_data, progress)


end

local teleport_unit_away = util.teleport_unit_away

local try_to_revive_entity = function(entity)
  if not (entity and entity.valid) then return true end
  local force = entity.force
  local name = entity.ghost_name
  local entity_build_count_statistics = get_entity_build_count_statistics(force, entity.surface)
  local revived = entity.revive({raise_revive = true})
  if revived then
    if entity_build_count_statistics then
      entity_build_count_statistics.on_flow(name, 1)
    end
    return true
  end
  local prototype = get_prototype(entity.ghost_name)
  local box = prototype.collision_box
  local origin = entity.position
  local area = {{box.left_top.x + origin.x, box.left_top.y + origin.y},{box.right_bottom.x + origin.x, box.right_bottom.y + origin.y}}
  local units = {}
  for k, unit in pairs (entity.surface.find_entities_filtered{area = area, force = force, type = "unit"}) do
    teleport_unit_away(unit, area)
  end
  local revived = entity.revive({raise_revive = true})
  if revived then
    if entity_build_count_statistics then
      entity_build_count_statistics.on_flow(name, 1)
    end
    return true
  end
end

local is_idle = function(unit_number)
  return not (data.not_idle_units[unit_number]) --and remote.call("unit_control", "is_unit_idle", unit.unit_number)
end


local distance = util.distance

local get_sacrifice_radius = function()
  return 40
end

local get_sacrifice_contact_radius = function(entity)
  local box = entity.bounding_box
  local width = math.abs(box.right_bottom.x - box.left_top.x)
  local height = math.abs(box.right_bottom.y - box.left_top.y)
  return math.max(width, height, 1.5)
end

local get_ghost_target_name = function(ghost_data)
  return ghost_data.target_name or get_growth_node_target_name(ghost_data.entity) or (ghost_data.entity and ghost_data.entity.valid and ghost_data.entity.type == "entity-ghost" and ghost_data.entity.ghost_name) or nil
end

local get_ghost_progress_text = function(ghost_data)
  local target_name = get_ghost_target_name(ghost_data)
  if not target_name then
    return "0%"
  end
  return math.floor((1 - (ghost_data.required_pollution / get_required_pollution(target_name))) * 100) .. "%"
end

local ensure_ghost_rendering = function(ghost_data)
  local entity = ghost_data.entity
  if not (entity and entity.valid) then return end

  local progress = ghost_data.progress
  if progress and (not render_object_valid(progress)) then
    progress = nil
    ghost_data.progress = nil
  end

  if render_object_valid(progress) then
    set_render_object_text(progress, get_ghost_progress_text(ghost_data))
  else
    progress = rendering.draw_text
    {
      text = get_ghost_progress_text(ghost_data),
      surface = entity.surface,
      target = entity,
      color = spawning_color,
      alignment = "center",
      forces = {entity.force},
      scale = 3,
      only_in_alt_mode = true
    }
    ghost_data.progress = progress
  end

  local radius = ghost_data.radius
  if not render_object_valid(radius) then
    radius = rendering.draw_circle
    {
      color = {r = 0.6, g = 0.6},
      width = 1,
      target = entity,
      surface = entity.surface,
      forces = {entity.force},
      draw_on_ground = true,
      filled = false,
      radius = get_sacrifice_radius(),
      only_in_alt_mode = true
    }
    ghost_data.radius = radius
  end
end

local needs_technology
local get_needs_technology = function(name)
  if needs_technology then return needs_technology[name] end
  needs_technology = {}
  local technology_prototypes = get_technology_prototypes()
  for name, entity in pairs(required_pollution) do
    if technology_prototypes["hivemind-unlock-"..name] then
      needs_technology[name] = true
    end
  end
  return needs_technology[name]
end

local needs_creep = shared.needs_creep
local creep_name = shared.creep

local complete_growth_node = function(entity, target_name)
  if not is_growth_node(entity) then
    return try_to_revive_entity(entity)
  end

  local surface = entity.surface
  local position = entity.position
  local force = entity.force
  local direction = entity.direction
  local inventory = get_growth_node_inventory(entity)
  if inventory then
    inventory.clear()
  end
  entity.destroy()
  local created = surface.create_entity
  {
    name = target_name,
    position = position,
    force = force,
    direction = direction,
    raise_built = true
  }
  return created and created.valid
end

local destroy_growth_node = function(entity)
  if not (entity and entity.valid and is_growth_node(entity)) then return end
  local inventory = get_growth_node_inventory(entity)
  if inventory then
    inventory.clear()
  end
  entity.destroy({raise_destroy = true})
end

local prune_colliding_growth_nodes = function(entity)
  if not (entity and entity.valid and is_growth_node(entity)) then return end
  local surface = entity.surface
  local area = entity.bounding_box
  for _, other in pairs(surface.find_entities_filtered{area = area, force = entity.force, type = "assembling-machine"}) do
    if other.valid and other ~= entity and is_growth_node(other) then
      destroy_growth_node(other)
    end
  end
end

local check_ghost = function(ghost_data)
  local entity = ghost_data.entity
  if not (entity and entity.valid) then
    return true
  end

  local target_name = get_ghost_target_name(ghost_data)
  if entity.type == "entity-ghost" and target_name then
    local remaining = ghost_data.required_pollution or get_required_pollution(target_name)
    local growth_node = convert_ghost_to_growth_node(entity, target_name, remaining)
    if not (growth_node and growth_node.valid) then
      return true
    end
    entity = growth_node
    ghost_data.entity = growth_node
    ghost_data.target_name = target_name
    ghost_data.required_pollution = get_growth_node_progress(growth_node) or remaining
  end

  target_name = get_ghost_target_name(ghost_data)
  if growth_node_should_cancel(entity) then
    destroy_growth_node(entity)
    return true
  end
  if not target_name then
    return true
  end

  if is_growth_node(entity) then
    ghost_data.required_pollution = get_growth_node_progress(entity) or 0
  end

  local surface = entity.surface

  if ghost_data.required_pollution > 0 then
    local contact_radius = get_sacrifice_contact_radius(entity)
    for k, unit in pairs (surface.find_entities_filtered{position = entity.position, radius = contact_radius, force = entity.force, type = "unit"}) do
      if unit.valid then
        local prototype = get_prototype(unit.name)
        local pollution = get_unit_pollution_cost(prototype) * pollution_cost_multiplier
        if unit.destroy({raise_destroy = true}) then
          ghost_data.required_pollution = math.max(0, ghost_data.required_pollution - pollution)
          set_growth_node_progress(entity, ghost_data.required_pollution)
          if ghost_data.required_pollution <= 0 then break end
        end
      end
    end
  end

  if ghost_data.required_pollution <= 0 then
    if complete_growth_node(entity, target_name) then
      return true
    end
  end

  local origin = entity.position
  local r = get_sacrifice_radius()
  local command =
  {
    type = defines.command.go_to_location,
    destination_entity = entity,
    distraction = defines.distraction.none,
    radius = 0.2
  }

  local needed_pollution = ghost_data.required_pollution
  for k, unit in pairs (surface.find_entities_filtered{position = origin, radius = r, force = entity.force, type = "unit"}) do
    if unit.valid then
      local unit_number = unit.unit_number
      if is_idle(unit_number) then
        --entity.surface.create_entity{name = "flying-text", position = unit.position, text = "IDLE"}
        local commandable = unit.commandable
        if commandable then
          commandable.set_command(command)
          local pollution = get_unit_pollution_cost(unit.prototype) * pollution_cost_multiplier
          needed_pollution = needed_pollution - pollution
          data.not_idle_units[unit_number] = {tick = game.tick, ghost_data = ghost_data}
          if needed_pollution <= 0 then break end
        end
      end
    end
  end

  ensure_ghost_rendering(ghost_data)

end

local make_proxy = function(entity)
  error("Not used")
  local radar_prototype = get_prototype(entity.name.."-radar")
  if not radar_prototype then return end
  --game.print("Made proxy for ".. entity.name)
  local radar_proxy = entity.surface.create_entity
  {
    name = radar_prototype.name,
    position = entity.position,
    force = entity.force
  } or error("Couldn't build radar proxy for some reason...")
  entity.destructible = false
  data.proxies[radar_proxy.unit_number] = entity
end

-- So, 59, so that its not exactly 60. Which means over a minute or so, each spawner will 'go first' at the pollution.
local spawners_update_interval = 59

local register_spawner_data = function(spawner_data)
  local entity = spawner_data.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  local update_tick = entity.unit_number % spawners_update_interval
  data.spawner_tick_check[update_tick] = data.spawner_tick_check[update_tick] or {}
  data.spawner_tick_check[update_tick][entity.unit_number] = spawner_data
end

local spawner_built = function(entity)
  local spawner_data = {entity = entity, proxy = radar_proxy}
  register_spawner_data(spawner_data)
  return spawner_data
end

local ensure_spawners_registered = function(tick)
  if tick and tick % 600 ~= 0 then return end

  local known_spawners = {}
  for _, bucket in pairs(data.spawner_tick_check) do
    for _, spawner_data in pairs(bucket) do
      local entity = spawner_data.entity
      local unit_number = entity and entity.valid and entity.unit_number
      if unit_number then
        known_spawners[unit_number] = spawner_data
      end
    end
  end

  data.spawner_tick_check = {}
  for _, spawner_data in pairs(known_spawners) do
    register_spawner_data(spawner_data)
  end

  local deployer_names = {shared.deployers.biter_deployer, shared.deployers.spitter_deployer}
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = deployer_names}) do
      local unit_number = entity.unit_number
      if unit_number and not known_spawners[unit_number] then
        spawner_built(entity)
      end
    end
  end
end

local ghost_update_interval = 60

local spawner_ghost_built = function(entity, player_index)
  local ghost_name = entity.ghost_name

  if get_needs_technology(ghost_name) and not entity.force.technologies["hivemind-unlock-"..ghost_name].researched then
    if player_index then
      local player = game.get_player(player_index)
      player.create_local_flying_text
      {
        text={"entity-not-unlocked", get_prototype(ghost_name).localised_name},
        position=entity.position,
        color=nil,
        time_to_live=nil,
        speed=nil
      }
    end
    entity.destroy()
    return
  end

  if needs_creep[ghost_name] and entity.surface.get_tile(entity.position).name ~= creep_name then
    if player_index then
      local player = game.get_player(player_index)
      player.create_local_flying_text
      {
        text={"must-be-placed-on-creep", get_prototype(ghost_name).localised_name},
        position=entity.position,
        color=nil,
        time_to_live=nil,
        speed=nil
      }
    end
    entity.destroy()
    return
  end

  local pollution = get_required_pollution(entity.ghost_name)
  local growth_node = convert_ghost_to_growth_node(entity, ghost_name, pollution)
  if not (growth_node and growth_node.valid) then
    return
  end
  prune_colliding_growth_nodes(growth_node)
  if not growth_node.valid then
    return
  end
  local ghost_data =
  {
    entity = growth_node,
    target_name = ghost_name,
    required_pollution = pollution
  }
  register_ghost_data(ghost_data)
  check_ghost(ghost_data)
end

register_ghost_data = function(ghost_data)
  local entity = ghost_data.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  local update_tick = entity.unit_number % ghost_update_interval
  data.ghost_tick_check[update_tick] = data.ghost_tick_check[update_tick] or {}
  data.ghost_tick_check[update_tick][entity.unit_number] = ghost_data
end

local ensure_ghosts_registered = function(tick)
  if tick and tick % 600 ~= 0 then return end
  local hivemind_force = game.forces["hivemind"]
  if not (hivemind_force and hivemind_force.valid) then
    data.ghost_tick_check = {}
    return
  end

  local known_ghosts = {}
  for _, bucket in pairs(data.ghost_tick_check) do
    for _, ghost_data in pairs(bucket) do
      local entity = ghost_data.entity
      local unit_number = entity and entity.valid and entity.unit_number
      if unit_number then
        if is_growth_node(entity) then
          ghost_data.target_name = get_growth_node_target_name(entity) or ghost_data.target_name
          ghost_data.required_pollution = get_growth_node_progress(entity) or ghost_data.required_pollution
        end
        known_ghosts[unit_number] = ghost_data
      end
    end
  end

  for _, unit_data in pairs(data.not_idle_units) do
    local ghost_data = unit_data.ghost_data
    local entity = ghost_data and ghost_data.entity
    if entity and entity.valid and entity.unit_number then
      if is_growth_node(entity) then
        ghost_data.target_name = get_growth_node_target_name(entity) or ghost_data.target_name
        ghost_data.required_pollution = get_growth_node_progress(entity) or ghost_data.required_pollution
      end
      known_ghosts[entity.unit_number] = known_ghosts[entity.unit_number] or ghost_data
    end
  end

  data.ghost_tick_check = {}
  for _, ghost_data in pairs(known_ghosts) do
    register_ghost_data(ghost_data)
  end

  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = growth_node_names, force = hivemind_force}) do
      prune_colliding_growth_nodes(entity)
      if not entity.valid then
        goto continue_growth_node
      end
      local unit_number = entity.unit_number
      local target_name = get_growth_node_target_name(entity)
      if unit_number and target_name and required_pollution[target_name] and not known_ghosts[unit_number] then
        register_ghost_data
        {
          entity = entity,
          target_name = target_name,
          required_pollution = get_growth_node_progress(entity) or get_required_pollution(target_name)
        }
      end
      ::continue_growth_node::
    end

    for _, entity in pairs(surface.find_entities_filtered{type = "entity-ghost", force = hivemind_force}) do
      local ghost_name = entity.ghost_name
      if ghost_name and required_pollution[ghost_name] then
        spawner_ghost_built(entity)
      end
    end
  end

end

local on_built_entity = function(event)
  local entity = event.created_entity or event.entity
  if not (entity and entity.valid) then return end

  --make_proxy(entity)

  if (spawner_map[entity.name]) then
    return spawner_built(entity)
  end

  if entity.type == "entity-ghost" then
    local ghost_name = entity.ghost_name
    if required_pollution[ghost_name] then
      return spawner_ghost_built(entity, event.player_index)
    end
  end

end

local check_spawners_on_tick = function(tick)

  local mod = tick % spawners_update_interval
  local entities = data.spawner_tick_check[mod]
  if not entities then return end

  for unit_number, spawner_data in pairs (entities) do
    --count = count + 1
    if check_spawner(spawner_data) then
      entities[unit_number] = nil
    end
  end
end

local check_ghosts_on_tick = function(tick)

  local mod = tick % ghost_update_interval
  local entities = data.ghost_tick_check[mod]
  if not entities then return end

  for unit_number, ghost_data in pairs (entities) do
    if check_ghost(ghost_data) then
      entities[unit_number] = nil
    end
  end
end

local expiry_time = 180
local check_not_idle_units = function(tick)
  if tick % expiry_time ~= 0 then return end
  local expiry_tick = tick - expiry_time
  local max = sanity_max
  for unit_number, unit_data in pairs (data.not_idle_units) do
    if unit_data.tick <= expiry_tick then
      data.not_idle_units[unit_number] = nil
    end
  end
end

local check_update_map_settings = function(tick)
  if tick and tick % 600 ~= 0 then return end
  data.destroy_factor = game.map_settings.enemy_evolution.destroy_factor
  data.enemy_attack_pollution_consumption_modifier = game.map_settings.pollution.enemy_attack_pollution_consumption_modifier
end

local unit_list

local get_units = function()
  if unit_list then return unit_list end
  unit_list = {}
  for name, prototype in pairs (get_entity_prototypes()) do
    if prototype.type == "unit" then
      table.insert(unit_list, name)
    end
  end
  return unit_list
end

local update_force_popcap_labels = function(force, caption)
  for k, player in pairs (force.players) do
    local gui = player.gui.left
    local label = gui.unit_deployment_pop_cap_label
    if not label then
      label = gui.add{name = "unit_deployment_pop_cap_label", type = "label"}
    end
    label.caption = caption
    label.visible = (caption ~= "")
  end
end

local check_update_pop_cap = function(tick)
  if tick and tick % 60 ~= 0 then return end
  --local profiler = game.create_profiler()
  local list = get_units()
  local forces = game.forces
  local forces_to_update = {}
  data.pop_count = {}
  for name, force in pairs (forces) do
    local total = 0
    local get_entity_count = force.get_entity_count
    for k = 1, #list do
      total = total + get_entity_count(list[k])
    end
    local index = force.index
    local current = data.pop_count[index]
    data.pop_count[index] = total
    local caption = total > 0 and {"popcap", total.."/"..get_max_pop_count()} or ""
    update_force_popcap_labels(force, caption)
  end

  --game.print({"", game.tick, profiler})
end

local on_tick = function(event)
  ensure_spawners_registered(event.tick)
  ensure_ghosts_registered(event.tick)
  if data.clear_rendering then
    data.not_idle_units = {}
    rendering.clear("Hive_Mind")
    clear_tracked_render_references()
    rebuild_rendering()
    for _, bucket in pairs(data.ghost_tick_check or {}) do
      for _, ghost_data in pairs(bucket) do
        check_ghost(ghost_data)
      end
    end
    data.clear_rendering = false
  end
  check_spawners_on_tick(event.tick)
  check_ghosts_on_tick(event.tick)
  check_not_idle_units(event.tick)
  check_update_map_settings(event.tick)
  check_update_pop_cap(event.tick)
end

local on_ai_command_completed = function(event)
  local command_data = data.not_idle_units[event.unit_number]
  if command_data then
    return check_ghost(command_data.ghost_data)
  end
end

clear_tracked_render_references = function()
  for _, bucket in pairs(data.spawner_tick_check or {}) do
    for _, spawner_data in pairs(bucket) do
      spawner_data.progress = nil
    end
  end

  for _, bucket in pairs(data.ghost_tick_check or {}) do
    for _, ghost_data in pairs(bucket) do
      ghost_data.progress = nil
      ghost_data.radius = nil
    end
  end
end

rebuild_rendering = function()
  for _, bucket in pairs(data.spawner_tick_check or {}) do
    for _, spawner_data in pairs(bucket) do
      ensure_spawner_rendering(spawner_data)
    end
  end

  for _, bucket in pairs(data.ghost_tick_check or {}) do
    for _, ghost_data in pairs(bucket) do
      ensure_ghost_rendering(ghost_data)
    end
  end
end

local redistribute_on_tick_checks = function()

  local new_spawner_tick_check = {}
  for k, array in pairs (data.spawner_tick_check) do
    for unit_number, data in pairs (array) do
      local mod = unit_number % spawners_update_interval
      new_spawner_tick_check[mod] = new_spawner_tick_check[mod] or {}
      new_spawner_tick_check[mod][unit_number] = data
    end
  end
  data.spawner_tick_check = new_spawner_tick_check

  local new_ghost_tick_check = {}
  for k, array in pairs (data.ghost_tick_check) do
    for unit_number, data in pairs (array) do
      local mod = unit_number % ghost_update_interval
      new_ghost_tick_check[mod] = new_ghost_tick_check[mod] or {}
      new_ghost_tick_check[mod][unit_number] = data
    end
  end
  data.ghost_tick_check = new_ghost_tick_check

end

local migrate_proxies = function()
  if not data.proxies then return end
  local types = {"assembling-machine", "lab", "mining-drill"}
  for k, surface in pairs (game.surfaces) do
    for k, entity in pairs (surface.find_entities_filtered{type = types, force = "hivemind"}) do
      entity.destructible = true
    end
  end
  data.proxies = nil
end

local events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_robot_built_entity] = on_built_entity,
  [defines.events.script_raised_revive] = on_built_entity,
  [defines.events.script_raised_built] = on_built_entity,
  [defines.events.on_tick] = on_tick,
  [defines.events.on_ai_command_completed] = on_ai_command_completed
}

commands.add_command("popcap", "Set the popcap for hive mind biters", function(command)
  local player = game.get_player(command.player_index)
  if not player.admin then player.print("Setting popcap is only for admins") return end
  if not tonumber(command.parameter) then player.print("Popcap must be a number") return end
  data.max_pop_count = tonumber(command.parameter)
end)

local setup_spawn_event = function()
  data.generated_events = data.generated_events or {}
  if data.generated_events.on_unit_spawned then
    unit_spawned_event = data.generated_events.on_unit_spawned
    return
  end
  unit_spawned_event = script.generate_event_name()
  data.generated_events.on_unit_spawned = unit_spawned_event
end

local register_remote_interface = function()
  if remote.interfaces["hive_mind_unit_deployment"] then return end
  remote.add_interface("hive_mind_unit_deployment",
  {
    get_events = function()
      return data.generated_events
    end
  })
end

local unit_deployment = {}

unit_deployment.get_events = function() return events end

unit_deployment.on_init = function()
  persistent.unit_deployment = persistent.unit_deployment or data
  data = persistent.unit_deployment
  data.clear_rendering = false
  ensure_spawners_registered()
  ensure_ghosts_registered()
  check_update_map_settings()
  check_update_pop_cap()
  setup_spawn_event()
  register_remote_interface()
end

unit_deployment.on_load = function()
  data = persistent.unit_deployment or data
  data.not_idle_units = {}
  data.clear_rendering = true
  setup_spawn_event()
end

unit_deployment.on_configuration_changed = function()
  setup_spawn_event()
  register_remote_interface()
  ensure_spawners_registered()
  ensure_ghosts_registered()
  check_update_map_settings()
  check_update_pop_cap()
  rendering.clear("Hive_Mind")
  redistribute_on_tick_checks()
  migrate_proxies()
  data.max_pop_count = data.max_pop_count or 1000
  data.not_idle_units = {}
  data.clear_rendering = true
end

return unit_deployment
