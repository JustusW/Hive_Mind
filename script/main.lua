local shared = require("shared")
local mod_gui = require("mod-gui")

local persistent = storage or global
local runtime =
{
  player_markers = {}
}

local state =
{
  hives_by_player = {},
  hive_roles = {},
  joined_players = {},
  hive_storage = {},
  pheromones = {},
  hive_nodes = {},
  restore_entities = {}
}

local allowed_cursor_items =
{
  [shared.items.hive] = true,
  [shared.items.pheromones] = true
}

local allowed_cursor_types =
{
  ["blueprint"] = true,
  ["blueprint-book"] = true,
  ["copy-paste-tool"] = true,
  ["selection-tool"] = true,
  ["deconstruction-item"] = true,
  ["upgrade-item"] = true
}

local function clone_table(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do
    result[k] = clone_table(v)
  end
  return result
end

local function get_state()
  persistent.hive_reboot = persistent.hive_reboot or clone_table(state)
  return persistent.hive_reboot
end

local function is_hive_player(player)
  local current = get_state()
  return player and player.valid and current.joined_players[player.index] == true
end

local function get_enemy_force()
  return game.forces.enemy
end

local function get_hive_force()
  local force = game.forces[shared.force_name]
  if force then
    return force
  end

  force = game.create_force(shared.force_name)
  local enemy = game.forces.enemy
  if enemy then
    force.set_cease_fire(enemy, true)
    force.set_friend(enemy, true)
    enemy.set_cease_fire(force, true)
    enemy.set_friend(force, true)
  end
  if game.forces.spectator then
    force.set_cease_fire(game.forces.spectator, true)
    force.set_friend(game.forces.spectator, true)
    game.forces.spectator.set_cease_fire(force, true)
    game.forces.spectator.set_friend(force, true)
  end
  return force
end

local function get_hive_permission_group()
  local groups = game.permissions
  local group = groups.get_group(shared.permission_group)
  if group then
    return group
  end

  group = groups.create_group(shared.permission_group)
  group.set_allows_action(defines.input_action.begin_mining, false)
  group.set_allows_action(defines.input_action.begin_mining_terrain, false)
  group.set_allows_action(defines.input_action.drop_item, false)
  group.set_allows_action(defines.input_action.fast_entity_transfer, false)
  group.set_allows_action(defines.input_action.inventory_transfer, false)
  group.set_allows_action(defines.input_action.stack_transfer, false)
  group.set_allows_action(defines.input_action.cursor_transfer, false)
  return group
end

local function configure_hive_force(force)
  if not (force and force.valid) then return end

  for recipe_name, recipe in pairs(force.recipes) do
    recipe.enabled = false
  end

  if force.recipes[shared.recipes.hive] then
    force.recipes[shared.recipes.hive].enabled = true
  end
  if force.recipes[shared.recipes.pheromones] then
    force.recipes[shared.recipes.pheromones].enabled = true
  end

  for _, technology in pairs(force.technologies) do
    technology.enabled = false
  end
end

local function clear_character_inventory(player)
  local character = player.character
  if not (character and character.valid) then return end

  local inventory_ids =
  {
    defines.inventory.character_main,
    defines.inventory.character_guns,
    defines.inventory.character_ammo,
    defines.inventory.character_armor,
    defines.inventory.character_trash
  }

  for _, inventory_id in pairs(inventory_ids) do
    local inventory = character.get_inventory(inventory_id)
    if inventory then
      inventory.clear()
    end
  end
end

local function clear_player_inventory(player)
  local inventory = player.get_main_inventory()
  if inventory then
    inventory.clear()
  end
end

local function destroy_player_marker(player_index)
  local marker_id = runtime.player_markers[player_index]
  if not marker_id then return end
  runtime.player_markers[player_index] = nil
  pcall(function()
    if rendering.is_valid(marker_id) then
      rendering.destroy(marker_id)
    end
  end)
end

local function update_player_marker(player)
  destroy_player_marker(player.index)
  if not is_hive_player(player) then return end
  if not (player.character and player.character.valid) then return end

  runtime.player_markers[player.index] = rendering.draw_sprite
  {
    sprite = "fluid/steam",
    target = player.character,
    target_offset = {0, -1.5},
    surface = player.surface,
    x_scale = 0.75,
    y_scale = 0.75,
    render_layer = "light-effect"
  }
end

local function update_join_button(player)
  local flow = mod_gui.get_button_flow(player)
  local button = flow[shared.gui.join_button]
  local joined = is_hive_player(player)

  if joined then
    if button then
      button.destroy()
    end
    return
  end

  if not button then
    flow.add
    {
      type = "button",
      name = shared.gui.join_button,
      caption = {"gui.hm-join-hive"},
      style = mod_gui.button_style
    }
  end
end

local function update_all_join_buttons()
  for _, player in pairs(game.players) do
    update_join_button(player)
    update_player_marker(player)
  end
end

local function apply_hive_director_state(player)
  local force = get_hive_force()
  configure_hive_force(force)
  player.force = force
  player.cheat_mode = false
  player.permission_group = get_hive_permission_group()

  if player.character and player.character.valid then
    clear_character_inventory(player)
    player.character.destructible = false
    player.character.operable = false
    player.character.color = {r = 1, g = 1, b = 1, a = 0}
  end
  clear_player_inventory(player)
  player.clear_cursor()
  update_player_marker(player)
  player.print({"gui.hm-hive-joined"})
end

local function queue_restored_entity(entity)
  local current = get_state()
  local restore = {
    name = entity.name,
    position = {x = entity.position.x, y = entity.position.y},
    direction = entity.direction,
    surface_index = entity.surface.index,
    force_name = entity.force and entity.force.name or nil
  }

  local ok_amount, amount = pcall(function()
    return entity.amount
  end)
  if ok_amount then
    restore.amount = amount
  end

  current.restore_entities[#current.restore_entities + 1] = restore
end

local function restore_mined_entities()
  local current = get_state()
  if #current.restore_entities == 0 then return end

  local pending = current.restore_entities
  current.restore_entities = {}
  for _, restore in pairs(pending) do
    local surface = game.surfaces[restore.surface_index]
    if surface then
      local params =
      {
        name = restore.name,
        position = restore.position,
        direction = restore.direction,
        force = restore.force_name
      }
      if restore.amount then
        params.amount = restore.amount
      end
      pcall(function()
        surface.create_entity(params)
      end)
    end
  end
end

local function join_hive(player)
  if is_hive_player(player) then return end
  local current = get_state()
  current.joined_players[player.index] = true
  apply_hive_director_state(player)
  update_join_button(player)
end

local function init_role_registry()
  local current = get_state()
  current.hive_roles = current.hive_roles or {}
end

local function register_creature_role(name, role)
  local current = get_state()
  current.hive_roles[name] = current.hive_roles[name] or {}
  current.hive_roles[name][role] = true
end

local function unregister_creature_role(name, role)
  local current = get_state()
  if current.hive_roles[name] then
    current.hive_roles[name][role] = nil
  end
end

local function is_hive_entity(entity)
  return entity and entity.valid and entity.name == shared.entities.hive
end

local function is_hive_node_entity(entity)
  return entity and entity.valid and entity.name == shared.entities.hive_node
end

local function remove_tracked_hive(player_index, unit_number)
  local current = get_state()
  local bucket = current.hives_by_player[player_index]
  if bucket then
    bucket[unit_number] = nil
  end
  current.hive_storage[unit_number] = nil
end

local function track_hive_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local current = get_state()
  current.hive_nodes[entity.unit_number] = {entity = entity}
end

local function untrack_hive_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local current = get_state()
  current.hive_nodes[entity.unit_number] = nil
end

local function get_hive_storage(entity)
  local current = get_state()
  if not (entity and entity.valid and entity.unit_number) then return end
  current.hive_storage[entity.unit_number] = current.hive_storage[entity.unit_number] or
  {
    owner_index = nil,
    entity = entity,
    creatures = {},
    pollution = 0
  }
  local storage = current.hive_storage[entity.unit_number]
  storage.entity = entity
  return storage
end

local function get_hive_inventory(entity)
  if not (entity and entity.valid) then return end
  return entity.get_inventory(defines.inventory.chest)
end

local function add_creature_to_hive_storage(storage, unit_name, count)
  local amount = count or 1
  local entity = storage and storage.entity
  local inventory = get_hive_inventory(entity)
  if not inventory then
    return 0
  end

  local item_name = shared.creature_item_name(unit_name)
  local inserted = inventory.insert{name = item_name, count = amount}
  if inserted > 0 then
    storage.creatures[unit_name] = (storage.creatures[unit_name] or 0) + inserted
  end
  return inserted
end

local function remove_creature_from_hive_storage(storage, unit_name, count)
  local amount = count or 1
  local available = storage.creatures[unit_name] or 0
  if available <= 0 then
    return 0
  end

  local removed = math.min(amount, available)
  local inventory = get_hive_inventory(storage.entity)
  if inventory then
    inventory.remove{name = shared.creature_item_name(unit_name), count = removed}
  end

  storage.creatures[unit_name] = available - removed
  if storage.creatures[unit_name] <= 0 then
    storage.creatures[unit_name] = nil
  end
  return removed
end

local function get_primary_player_hive(player_index)
  local current = get_state()
  local bucket = current.hives_by_player[player_index] or {}
  for _, hive_data in pairs(bucket) do
    local entity = hive_data.entity
    if entity and entity.valid then
      return entity
    end
  end
end

local function has_active_pheromones(player)
  local current = get_state()
  local pheromones = current.pheromones[player.index]
  if not pheromones then return false end
  if pheromones.expire_tick <= game.tick then
    current.pheromones[player.index] = nil
    return false
  end

  local inventory = player.get_main_inventory()
  if not inventory or inventory.get_item_count(shared.items.pheromones) <= 0 then
    current.pheromones[player.index] = nil
    return false
  end

  return true
end

local function get_unit_pollution_cost(prototype)
  if not prototype then return 0 end

  local ok, pollution_to_join_attack = pcall(function()
    return prototype.pollution_to_join_attack
  end)
  if ok and pollution_to_join_attack then
    return pollution_to_join_attack
  end

  local ok_absorb, absorptions_to_join_attack = pcall(function()
    return prototype.absorptions_to_join_attack
  end)
  if ok_absorb and absorptions_to_join_attack and absorptions_to_join_attack.pollution then
    return absorptions_to_join_attack.pollution
  end

  local ok_attack, attack_parameters = pcall(function()
    return prototype.attack_parameters
  end)
  if ok_attack and attack_parameters and attack_parameters.pollution_to_join_attack then
    return attack_parameters.pollution_to_join_attack
  end

  return 0
end

local function has_registered_role(entity_name, role)
  local current = get_state()
  local entry = current.hive_roles[entity_name]
  return entry and entry[role] == true or false
end

local function is_default_hive_creature(entity, role)
  if not (entity and entity.valid) then return false end
  if entity.type ~= "unit" then return false end
  if role == shared.creature_roles.attract or role == shared.creature_roles.store or role == shared.creature_roles.consume then
    return true
  end
  return false
end

local function is_hive_creature_for_role(entity, role)
  if not (entity and entity.valid) then return false end
  if has_registered_role(entity.name, role) then
    return true
  end
  return is_default_hive_creature(entity, role)
end

local function get_unit_recruit_target(player)
  if not (player and player.valid) then return end
  if has_active_pheromones(player) then
    return {type = "player", entity = player, player = player}
  end

  local hive = get_primary_player_hive(player.index)
  if hive then
    return {type = "hive", entity = hive, player = player}
  end
end

local function get_entity_build_cost(name)
  return shared.build_costs[name] or 0
end

local function get_total_stored_creatures(storage)
  local total = 0
  for _, count in pairs(storage.creatures) do
    total = total + count
  end
  return total
end

local function consume_hive_pollution(storage, amount)
  if amount <= 0 then return true end
  if storage.pollution >= amount then
    storage.pollution = storage.pollution - amount
    return true
  end

  local needed = amount - storage.pollution
  storage.pollution = 0

  while needed > 0 do
    local converted = false
    for unit_name, count in pairs(storage.creatures) do
      if count > 0 then
        local prototype = game.entity_prototypes[unit_name]
        local pollution = get_unit_pollution_cost(prototype)
        if pollution > 0 then
          if remove_creature_from_hive_storage(storage, unit_name, 1) > 0 then
            storage.pollution = storage.pollution + pollution
            converted = true
            break
          end
        end
      end
    end

    if not converted then
      return false
    end

    if storage.pollution >= needed then
      storage.pollution = storage.pollution - needed
      return true
    end

    needed = needed - storage.pollution
    storage.pollution = 0
  end

  return true
end

local function get_all_service_hives()
  local current = get_state()
  local results = {}
  for _, bucket in pairs(current.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      if hive_data.entity and hive_data.entity.valid then
        results[#results + 1] = hive_data.entity
      end
    end
  end
  return results
end

local function get_all_service_nodes()
  local current = get_state()
  local results = {}
  for unit_number, node_data in pairs(current.hive_nodes) do
    local entity = node_data.entity
    if entity and entity.valid then
      results[#results + 1] = entity
    else
      current.hive_nodes[unit_number] = nil
    end
  end
  return results
end

local function position_in_service_network(surface, position)
  for _, hive in pairs(get_all_service_hives()) do
    if hive.surface == surface then
      local dx = hive.position.x - position.x
      local dy = hive.position.y - position.y
      if math.sqrt((dx * dx) + (dy * dy)) <= shared.ranges.hive then
        return true
      end
    end
  end

  for _, node in pairs(get_all_service_nodes()) do
    if node.surface == surface then
      local dx = node.position.x - position.x
      local dy = node.position.y - position.y
      if math.sqrt((dx * dx) + (dy * dy)) <= shared.ranges.hive_node then
        return true
      end
    end
  end

  return false
end

local function get_best_hive_for_position(surface, position, range)
  if not position_in_service_network(surface, position) then
    return
  end

  local best_entity
  local best_distance
  for _, entity in pairs(get_all_service_hives()) do
    if entity.surface == surface then
      local dx = entity.position.x - position.x
      local dy = entity.position.y - position.y
      local distance = math.sqrt((dx * dx) + (dy * dy))
      if distance <= range and (not best_distance or distance < best_distance) then
        best_distance = distance
        best_entity = entity
      end
    end
  end
  return best_entity
end

local function command_unit_to_target(unit, target)
  if not (unit and unit.valid and target) then return end

  if unit.force ~= get_hive_force() then
    unit.force = get_hive_force()
  end

  local commandable = unit.commandable
  if not commandable then return end
  if target.type == "player" and target.player and target.player.valid then
    commandable.set_command
    {
      type = defines.command.go_to_location,
      destination = target.player.position,
      distraction = defines.distraction.none,
      radius = 1
    }
    return
  end

  if target.entity and target.entity.valid then
    commandable.set_command
    {
      type = defines.command.go_to_location,
      destination_entity = target.entity,
      distraction = defines.distraction.none,
      radius = 1
    }
  end
end

local function recruit_units_to_hive_targets()
  local current = get_state()
  local enemy_force = get_enemy_force()
  local hive_force = get_hive_force()

  for player_index in pairs(current.joined_players) do
    local player = game.get_player(player_index)
    local target = get_unit_recruit_target(player)
    if not target then
      goto continue_player
    end

    local surface = target.entity.surface
    local units = surface.find_entities_filtered
    {
      position = target.entity.position,
      radius = shared.ranges.hive,
      type = "unit"
    }

    for _, unit in pairs(units) do
      if unit.valid and (unit.force == enemy_force or unit.force == hive_force) and is_hive_creature_for_role(unit, shared.creature_roles.attract) then
        command_unit_to_target(unit, target)
      end
    end

    ::continue_player::
  end
end

local function absorb_units_into_hive(entity)
  local storage = get_hive_storage(entity)
  if not storage then return end

  local surface = entity.surface
  local hive_force = get_hive_force()
  local nearby_units = surface.find_entities_filtered
  {
    position = entity.position,
    radius = 3,
    type = "unit",
    force = hive_force
  }

  for _, unit in pairs(nearby_units) do
    if unit.valid and is_hive_creature_for_role(unit, shared.creature_roles.store) then
      if add_creature_to_hive_storage(storage, unit.name, 1) > 0 then
        unit.destroy({raise_destroy = true})
      end
    end
  end
end

local function release_hive_contents(entity)
  local storage = get_hive_storage(entity)
  if not storage then return end
  local surface = entity.surface
  local force = get_hive_force()

  for unit_name, count in pairs(storage.creatures) do
    for _ = 1, count do
      local position = surface.find_non_colliding_position(unit_name, entity.position, 24, 0.5)
      if position then
        surface.create_entity
        {
          name = unit_name,
          position = position,
          force = force,
          raise_built = true
        }
      end
    end
  end

  local inventory = get_hive_inventory(entity)
  if inventory then
    inventory.clear()
  end
  storage.creatures = {}
end

local function tick_hive_absorption()
  local current = get_state()
  for _, bucket in pairs(current.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      local entity = hive_data.entity
      if entity and entity.valid then
        absorb_units_into_hive(entity)
      end
    end
  end
end

local function expire_pheromones()
  local current = get_state()
  for player_index, pheromones in pairs(current.pheromones) do
    if pheromones.expire_tick <= game.tick then
      local player = game.get_player(player_index)
        if player and player.valid then
          local inventory = player.get_main_inventory()
          if inventory then
            inventory.remove{name = shared.items.pheromones, count = inventory.get_item_count(shared.items.pheromones)}
          end
        player.print({"message.hm-pheromones-faded"})
      end
      current.pheromones[player_index] = nil
    end
  end
end

local function fulfill_ghost_requests()
  local hive_force = get_hive_force()
  for _, hive in pairs(get_all_service_hives()) do
    local storage = get_hive_storage(hive)
    if storage then
      local ghosts = hive.surface.find_entities_filtered
      {
        position = hive.position,
        radius = shared.ranges.hive,
        force = hive_force,
        type = "entity-ghost"
      }

      for _, ghost in pairs(ghosts) do
        if ghost.valid then
          local ghost_name = ghost.ghost_name
          local build_cost = ghost_name and get_entity_build_cost(ghost_name) or 0
          if build_cost > 0 and consume_hive_pollution(storage, build_cost) then
            ghost.revive({raise_revive = true})
          end
        end
      end
    end
  end
end

local function supply_labs()
  local hive_force = get_hive_force()
  for _, surface in pairs(game.surfaces) do
    local labs = surface.find_entities_filtered{name = shared.entities.hive_lab, force = hive_force}
    for _, lab in pairs(labs) do
      if lab.valid then
        local inventory = lab.get_inventory(defines.inventory.lab_input)
        if inventory and inventory.get_item_count(shared.items.pollution_science_pack) < 10 then
          local hive = get_best_hive_for_position(surface, lab.position, shared.ranges.hive)
          if hive then
            local storage = get_hive_storage(hive)
            if storage and consume_hive_pollution(storage, shared.science.pollution_per_pack) then
              inventory.insert{name = shared.items.pollution_science_pack, count = 1}
            end
          end
        end
      end
    end
  end
end

local function destroy_previous_player_hives(player_index, newly_built)
  local current = get_state()
  current.hives_by_player[player_index] = current.hives_by_player[player_index] or {}
  local bucket = current.hives_by_player[player_index]
  for unit_number, hive_data in pairs(bucket) do
    if unit_number ~= newly_built.unit_number then
      local entity = hive_data.entity
      if entity and entity.valid then
        entity.destroy({raise_destroy = true})
      end
      bucket[unit_number] = nil
    end
  end
  bucket[newly_built.unit_number] = {entity = newly_built}
  local storage = get_hive_storage(newly_built)
  if storage then
    storage.owner_index = player_index
  end
end

local function on_built_entity(event)
  local entity = event.created_entity or event.entity
  if is_hive_node_entity(entity) then
    return track_hive_node(entity)
  end

  if not is_hive_entity(entity) then return end
  if not event.player_index then return end

  destroy_previous_player_hives(event.player_index, entity)

  local force = entity.force
  if force and force.valid and force.technologies[shared.technologies.hive_spawners] then
    force.technologies[shared.technologies.hive_spawners].researched = true
  end
end

local function on_removed_entity(event)
  local entity = event.entity
  if is_hive_node_entity(entity) then
    return untrack_hive_node(entity)
  end
  if not is_hive_entity(entity) then return end

  release_hive_contents(entity)

  local current = get_state()
  for player_index, bucket in pairs(current.hives_by_player) do
    if bucket[entity.unit_number] then
      remove_tracked_hive(player_index, entity.unit_number)
      break
    end
  end
end

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  update_join_button(player)
end

local function on_gui_click(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if event.element.name == shared.gui.join_button then
    join_hive(player)
  end
end

local function on_player_respawned(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  apply_hive_director_state(player)
end

local function on_player_crafted_item(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local recipe_name = event.recipe.name
  if recipe_name ~= shared.recipes.pheromones and recipe_name ~= shared.recipes.hive then return end

  if recipe_name == shared.recipes.pheromones then
    local current = get_state()
    current.pheromones[player.index] =
    {
      expire_tick = game.tick + shared.costs.pheromones_duration_ticks
    }
    local inventory = player.get_main_inventory()
    local stack = inventory and inventory.find_item_stack(shared.items.pheromones)
    if stack and stack.valid_for_read then
      stack.spoil_tick = game.tick + shared.costs.pheromones_duration_ticks
    end
  end
end

local function on_player_mined_entity(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  if event.buffer then
    event.buffer.clear()
  end
  if event.entity and event.entity.valid then
    queue_restored_entity(event.entity)
  end
  player.print({"message.hm-no-mining"})
end

local function on_player_mined_item(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local inventory = player.get_main_inventory()
  if inventory then
    inventory.remove{name = event.item_stack.name, count = event.item_stack.count}
  end
end

local function on_player_cursor_stack_changed(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end

  local stack = player.cursor_stack
  if not stack.valid_for_read then return end
  if allowed_cursor_items[stack.name] or allowed_cursor_types[stack.type] then return end

  player.print({"message.hm-director-only"})
  stack.clear()
end

local function clear_forbidden_inventory(player, inventory_id)
  if not is_hive_player(player) then return end
  local inventory = player.get_inventory(inventory_id)
  if not inventory then return end
  inventory.clear()
end

local function on_player_main_inventory_changed(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local inventory = player.get_main_inventory()
  if not inventory then return end

  local allowed_counts = {}
  for name, count in pairs(inventory.get_contents()) do
    if allowed_cursor_items[name] then
      allowed_counts[name] = (allowed_counts[name] or 0) + count
    end
  end
  inventory.clear()
  for name, count in pairs(allowed_counts) do
    inventory.insert{name = name, count = count}
  end
end

local function on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  if event.gui_type == defines.gui_type.entity and event.entity and event.entity.valid and event.entity.name == shared.entities.hive then
    return
  end
  if event.gui_type == defines.gui_type.entity and event.entity and event.entity.valid and event.entity.name == shared.entities.hive_lab then
    return
  end
  if event.gui_type == defines.gui_type.controller then
    return
  end
  if event.gui_type == defines.gui_type.crafting then
    return
  end
  if event.gui_type == defines.gui_type.none then
    return
  end
  player.opened = nil
end

local function on_tick(event)
  if event.tick % shared.intervals.pheromones == 0 then
    expire_pheromones()
  end
  restore_mined_entities()
  if event.tick % shared.intervals.recruit == 0 then
    recruit_units_to_hive_targets()
  end
  if event.tick % shared.intervals.absorb == 0 then
    tick_hive_absorption()
  end
  if event.tick % shared.intervals.absorb == 0 then
    fulfill_ghost_requests()
    supply_labs()
  end
end

remote.add_interface("hive_reboot",
{
  register_creature_role = register_creature_role,
  unregister_creature_role = unregister_creature_role,
  join_hive = function(player_index)
    local player = game.get_player(player_index)
    if player then
      join_hive(player)
    end
  end
})

script.on_init(function()
  get_state()
  init_role_registry()
  configure_hive_force(get_hive_force())
  get_hive_permission_group()
  update_all_join_buttons()
end)

script.on_configuration_changed(function()
  get_state()
  init_role_registry()
  configure_hive_force(get_hive_force())
  get_hive_permission_group()
  update_all_join_buttons()
end)

script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_player_respawned, on_player_respawned)
script.on_event(defines.events.on_player_crafted_item, on_player_crafted_item)
script.on_event(defines.events.on_player_cursor_stack_changed, on_player_cursor_stack_changed)
script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity)
script.on_event(defines.events.on_player_mined_item, on_player_mined_item)
script.on_event(defines.events.on_player_main_inventory_changed, on_player_main_inventory_changed)
script.on_event(defines.events.on_player_gun_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_guns) end)
script.on_event(defines.events.on_player_ammo_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_ammo) end)
script.on_event(defines.events.on_player_armor_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_armor) end)
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_tick, on_tick)

script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.script_raised_built, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)

script.on_event(defines.events.on_entity_died, on_removed_entity)
script.on_event(defines.events.on_robot_mined_entity, on_removed_entity)
script.on_event(defines.events.script_raised_destroy, on_removed_entity)
