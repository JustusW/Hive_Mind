local shared = require("shared")

local persistent = storage or global

local state =
{
  hives_by_player = {},
  hive_roles = {}
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

remote.add_interface("hive_reboot",
{
  register_creature_role = register_creature_role,
  unregister_creature_role = unregister_creature_role
})

script.on_init(function()
  get_state()
  init_role_registry()
end)

script.on_configuration_changed(function()
  get_state()
  init_role_registry()
end)

script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.script_raised_built, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)

script.on_event(defines.events.on_entity_died, on_removed_entity)
script.on_event(defines.events.on_player_mined_entity, on_removed_entity)
script.on_event(defines.events.on_robot_mined_entity, on_removed_entity)
script.on_event(defines.events.script_raised_destroy, on_removed_entity)
