local shared = require("shared")
local mod_gui = require("mod-gui")

local persistent = storage or global

local state =
{
  hives_by_player = {},
  hive_roles = {},
  joined_players = {}
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
  end
end

local function apply_hive_director_state(player)
  local force = get_hive_force()
  configure_hive_force(force)
  player.force = force
  player.cheat_mode = true

  if player.character and player.character.valid then
    clear_character_inventory(player)
    player.character.destructible = false
    player.character.operable = false
    player.character.color = {r = 0, g = 0, b = 0, a = 0}
  end

  player.character_mining_speed_modifier = -1
  player.character_build_distance_bonus = math.max(player.character_build_distance_bonus, 64)
  player.character_reach_distance_bonus = math.max(player.character_reach_distance_bonus, 64)
  player.character_resource_reach_distance_bonus = math.max(player.character_resource_reach_distance_bonus, 64)
  player.character_item_pickup_distance_bonus = 0
  player.character_loot_pickup_distance_bonus = 0
  player.character_running_speed_modifier = 0
  player.clear_cursor()
  player.print({"gui.hm-hive-joined"})
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

local function remove_tracked_hive(player_index, unit_number)
  local current = get_state()
  local bucket = current.hives_by_player[player_index]
  if bucket then
    bucket[unit_number] = nil
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
end

local function on_built_entity(event)
  local entity = event.created_entity or event.entity
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
  if not is_hive_entity(entity) then return end

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
  if event.element.name ~= shared.gui.join_button then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  join_hive(player)
end

local function on_player_respawned(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  apply_hive_director_state(player)
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
  local character = player.character
  if not (character and character.valid) then return end
  local inventory = character.get_inventory(inventory_id)
  if not inventory then return end
  inventory.clear()
end

local function on_player_main_inventory_changed(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local character = player.character
  if not (character and character.valid) then return end
  local inventory = character.get_main_inventory()
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
  update_all_join_buttons()
end)

script.on_configuration_changed(function()
  get_state()
  init_role_registry()
  configure_hive_force(get_hive_force())
  update_all_join_buttons()
end)

script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_player_respawned, on_player_respawned)
script.on_event(defines.events.on_player_cursor_stack_changed, on_player_cursor_stack_changed)
script.on_event(defines.events.on_player_main_inventory_changed, on_player_main_inventory_changed)
script.on_event(defines.events.on_player_gun_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_guns) end)
script.on_event(defines.events.on_player_ammo_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_ammo) end)
script.on_event(defines.events.on_player_armor_inventory_changed, function(event) clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_armor) end)
script.on_event(defines.events.on_gui_opened, on_gui_opened)

script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.script_raised_built, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)

script.on_event(defines.events.on_entity_died, on_removed_entity)
script.on_event(defines.events.on_player_mined_entity, on_removed_entity)
script.on_event(defines.events.on_robot_mined_entity, on_removed_entity)
script.on_event(defines.events.script_raised_destroy, on_removed_entity)
