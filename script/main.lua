local shared = require("shared")
local mod_gui = require("mod-gui")

-- ── Persistent state ──────────────────────────────────────────────────────────

local function get_state()
  local s = storage or global
  if not s.hive_reboot then
    s.hive_reboot =
    {
      joined_players = {},        -- [player_index] = true
      hives_by_player = {},       -- [player_index][unit_number] = {entity}
      hive_nodes = {},            -- [unit_number] = {entity, creep_front}
      hive_storage = {},          -- [unit_number] = {entity, creep_front, chest}
      pollution_generators = {},  -- [unit_number] = entity
      hive_roles = {}             -- [entity_name][role] = true
    }
  end
  local state = s.hive_reboot
  if not state.pollution_generators then state.pollution_generators = {} end
  if not state.hive_roles            then state.hive_roles            = {} end
  return state
end

-- ── Force helpers ─────────────────────────────────────────────────────────────

local function get_hive_force()
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

local function get_enemy_force()
  return game.forces.enemy
end

-- ── Permission group ──────────────────────────────────────────────────────────

local function get_hive_permission_group()
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

-- ── Hive force recipe / tech configuration ───────────────────────────────────

local always_enabled_recipes =
{
  shared.recipes.hive,
  shared.recipes.pheromones_on,
  shared.recipes.pheromones_off,
  shared.recipes.pollution_generator
}

local function configure_hive_force(force)
  if not (force and force.valid) then return end
  for _, recipe in pairs(force.recipes) do recipe.enabled = false end
  for _, tech in pairs(force.technologies) do tech.enabled = true end
  for _, name in pairs(always_enabled_recipes) do
    if force.recipes[name] then force.recipes[name].enabled = true end
  end
  -- Re-enable tech-gated recipes whose tech is already researched.
  local function on_tech(tech_name, recipe_names)
    local tech = force.technologies[tech_name]
    if tech and tech.researched then
      for _, rname in pairs(recipe_names) do
        if force.recipes[rname] then force.recipes[rname].enabled = true end
      end
    end
  end
  on_tech(shared.technologies.hive_spawners, {shared.recipes.hive_node, shared.recipes.hive_spawner})
  on_tech(shared.technologies.hive_labs,     {shared.recipes.hive_lab})
  for _, tier in pairs(shared.worm_tiers) do
    on_tech(shared.worm[tier].tech, {shared.worm[tier].recipe})
  end
end

-- ── Player state helpers ──────────────────────────────────────────────────────

local function is_hive_player(player)
  local current = get_state()
  return player and player.valid and current.joined_players[player.index] == true
end

-- ── GUI ───────────────────────────────────────────────────────────────────────

local function update_join_button(player)
  if not (player and player.valid) then return end
  local flow = mod_gui.get_button_flow(player)
  local existing = flow[shared.gui.join_button]
  if is_hive_player(player) then
    if existing then existing.destroy() end
    return
  end
  if not existing then
    flow.add{
      type = "button",
      name = shared.gui.join_button,
      caption = {"gui.hm-join-hive"},
      style = mod_gui.button_style
    }
  end
end

local function update_all_join_buttons()
  for _, player in pairs(game.players) do update_join_button(player) end
end

-- ── Hive storage chest ────────────────────────────────────────────────────────

local function get_hive_storage(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil end
  local current = get_state()
  local id = entity.unit_number
  if not current.hive_storage[id] then
    current.hive_storage[id] = {entity = entity, creep_front = 1, chest = nil}
  end
  local s = current.hive_storage[id]
  s.entity = entity
  return s
end

local function get_hive_chest(hive)
  local s = get_hive_storage(hive)
  if not s then return nil end
  if s.chest and s.chest.valid then return s.chest end
  s.chest = nil
  return nil
end

local function create_hive_chest(hive)
  if not (hive and hive.valid) then return end
  local s = get_hive_storage(hive)
  if not s then return end
  if s.chest and s.chest.valid then s.chest.destroy() end
  s.chest = nil
  local pos = hive.surface.find_non_colliding_position(
    shared.entities.hive_storage,
    {hive.position.x + 2, hive.position.y},
    6, 0.5)
  if not pos then
    pos = hive.surface.find_non_colliding_position(
      shared.entities.hive_storage, hive.position, 10, 0.5)
  end
  if not pos then
    -- Last resort: drop on the hive's tile. The chest renders as nothing so
    -- visual overlap is fine.
    pos = hive.position
  end
  local chest = hive.surface.create_entity{
    name        = shared.entities.hive_storage,
    position    = pos,
    force       = hive.force,
    raise_built = false
  }
  if chest and chest.valid then
    s.chest = chest
  end
end

-- ── Pollution / cost helpers ──────────────────────────────────────────────────

local function get_unit_pollution_value(unit_name)
  local proto = prototypes.entity[unit_name]
  if not proto then return 1 end
  local absorb = proto.absorptions_to_join_attack
  if absorb and absorb.pollution then return math.max(1, math.floor(absorb.pollution)) end
  return 1
end

-- Recipe-derived build cost. Override via shared.build_costs[name].
local function compute_build_cost(entity_name)
  local override = shared.build_costs[entity_name]
  if override then return override end
  local entity_proto = prototypes.entity[entity_name]
  if not entity_proto then return shared.fallback_build_cost end
  local items = entity_proto.items_to_place_this
  if not items or #items == 0 then return shared.fallback_build_cost end
  local item_name = items[1].name
  for _, recipe in pairs(prototypes.recipe) do
    for _, product in pairs(recipe.products or {}) do
      if product.name == item_name then
        local total = 0
        for _, ing in pairs(recipe.ingredients) do
          local factor = shared.item_pollution_factors[ing.name]
                      or shared.default_item_pollution_factor
          total = total + (ing.amount or 0) * factor
        end
        if total > 0 then return total end
      end
    end
  end
  return shared.fallback_build_cost
end

-- ── Network resolver ──────────────────────────────────────────────────────────

-- All hive-side structures (hives + nodes) on a surface, with their range.
local function all_network_structures(surface)
  local current = get_state()
  local list = {}
  for _, bucket in pairs(current.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      local e = hive_data.entity
      if e and e.valid and e.surface == surface then
        list[#list + 1] = {entity = e, range = shared.ranges.hive, kind = "hive"}
      end
    end
  end
  for _, node_data in pairs(current.hive_nodes) do
    local e = node_data.entity
    if e and e.valid and e.surface == surface then
      list[#list + 1] = {entity = e, range = shared.ranges.hive_node, kind = "node"}
    end
  end
  return list
end

-- Returns the list of hive entities (chests, not nodes) in the network whose
-- combined construction radii cover `position`. nil if no member reaches it.
local function get_network_hives_for_position(surface, position)
  local structs = all_network_structures(surface)
  if #structs == 0 then return nil end
  local in_net = {}
  -- Seed: anything covering the position.
  for i, s in ipairs(structs) do
    local dx = s.entity.position.x - position.x
    local dy = s.entity.position.y - position.y
    if dx * dx + dy * dy <= s.range * s.range then
      in_net[i] = true
    end
  end
  if not next(in_net) then return nil end
  -- Expand by overlap until stable.
  local changed = true
  while changed do
    changed = false
    for i, s in ipairs(structs) do
      if not in_net[i] then
        for j in pairs(in_net) do
          local m = structs[j]
          local dx = s.entity.position.x - m.entity.position.x
          local dy = s.entity.position.y - m.entity.position.y
          local touch = s.range + m.range
          if dx * dx + dy * dy <= touch * touch then
            in_net[i] = true
            changed = true
            break
          end
        end
      end
    end
  end
  local hives = {}
  for i in pairs(in_net) do
    if structs[i].kind == "hive" then
      hives[#hives + 1] = structs[i].entity
    end
  end
  return (#hives > 0) and hives or nil
end

local function network_item_count(hives, item_name)
  local total = 0
  for _, hive in pairs(hives) do
    local chest = get_hive_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv then total = total + inv.get_item_count(item_name) end
    end
  end
  return total
end

-- Convert creature items in the network to pollution items until total ≥ target.
-- Batches per slot: a single 350-stack of small-biters is converted in one call,
-- not one biter at a time.
local function network_convert_creatures(hives, target)
  local total = network_item_count(hives, shared.items.pollution)
  if total >= target then return total end
  for _, hive in pairs(hives) do
    if total >= target then break end
    local chest = get_hive_chest(hive)
    if not chest then goto continue end
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then goto continue end
    for i = 1, #inv do
      if total >= target then break end
      local stack = inv[i]
      if stack and stack.valid_for_read then
        local unit_name = shared.creature_unit_name(stack.name)
        if unit_name then
          local value = get_unit_pollution_value(unit_name)
          if value > 0 then
            local needed_units = math.ceil((target - total) / value)
            local convert = math.min(stack.count, needed_units)
            if convert > 0 then
              local removed = inv.remove{name = stack.name, count = convert}
              if removed > 0 then
                inv.insert{name = shared.items.pollution, count = removed * value}
                total = total + removed * value
              end
            end
          end
        end
      end
    end
    ::continue::
  end
  return total
end

-- Charge `amount` pollution from the network covering `position`.
-- Returns:  true                      on success
--           false, "no_hive"          if no hive is in range
--           false, "insufficient"     if hives are in range but pool is too low
local function consume_network_pollution(surface, position, amount)
  if amount <= 0 then return true end
  local hives = get_network_hives_for_position(surface, position)
  if not hives then return false, "no_hive" end
  local need = math.ceil(amount)
  local total = network_convert_creatures(hives, need)
  if total < need then return false, "insufficient" end
  local remaining = need
  for _, hive in pairs(hives) do
    if remaining <= 0 then break end
    local chest = get_hive_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv then
        local available = inv.get_item_count(shared.items.pollution)
        local take = math.min(available, remaining)
        if take > 0 then
          inv.remove{name = shared.items.pollution, count = take}
          remaining = remaining - take
        end
      end
    end
  end
  return true
end

-- Caller helper: print the right localised message for a charge failure.
local function print_charge_failure(player_index, reason)
  if not player_index then return end
  local p = game.get_player(player_index)
  if not (p and p.valid) then return end
  if reason == "no_hive" then
    p.print({"message.hm-no-hive-in-range"})
  else
    p.print({"message.hm-insufficient-resources"})
  end
end

-- Insert `item_stack` into any chest in the network covering `position`.
local function insert_into_network(surface, position, item_stack)
  local hives = get_network_hives_for_position(surface, position)
  if not hives then return false end
  for _, hive in pairs(hives) do
    local chest = get_hive_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv and inv.can_insert(item_stack) then
        inv.insert(item_stack)
        return true
      end
    end
  end
  return false
end

-- ── Hive tracking ─────────────────────────────────────────────────────────────

local function track_hive(player_index, entity)
  local current = get_state()
  current.hives_by_player[player_index] = current.hives_by_player[player_index] or {}
  current.hives_by_player[player_index][entity.unit_number] = {entity = entity}
end

local function untrack_hive(entity)
  local current = get_state()
  for _, bucket in pairs(current.hives_by_player) do
    if bucket[entity.unit_number] then
      bucket[entity.unit_number] = nil
      break
    end
  end
  current.hive_storage[entity.unit_number] = nil
end

local function track_hive_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local current = get_state()
  current.hive_nodes[entity.unit_number] = {entity = entity, creep_front = 1}
end

local function untrack_hive_node(entity)
  if not (entity and entity.valid and entity.unit_number) then return end
  local current = get_state()
  current.hive_nodes[entity.unit_number] = nil
end

local function get_primary_player_hive(player_index)
  local current = get_state()
  local bucket = current.hives_by_player[player_index]
  if not bucket then return nil end
  for _, hive_data in pairs(bucket) do
    if hive_data.entity and hive_data.entity.valid then
      return hive_data.entity
    end
  end
end

local function all_hives()
  local current = get_state()
  local result = {}
  for _, bucket in pairs(current.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      if hive_data.entity and hive_data.entity.valid then
        result[#result + 1] = hive_data.entity
      end
    end
  end
  return result
end

-- ── Creature classification ───────────────────────────────────────────────────

local function has_registered_role(entity_name, role)
  local current = get_state()
  local entry = current.hive_roles[entity_name]
  return entry and entry[role] == true
end

local function is_hive_creature_for_role(entity, role)
  if not (entity and entity.valid) then return false end
  if has_registered_role(entity.name, role) then return true end
  return entity.type == "unit"
end

-- ── Absorption ────────────────────────────────────────────────────────────────

local function absorb_units_into_hive(entity)
  local chest = get_hive_chest(entity)
  if not chest then return end
  local inv = chest.get_inventory(defines.inventory.chest)
  if not inv then return end
  local hive_force = get_hive_force()
  local enemy_force = get_enemy_force()
  local units = entity.surface.find_entities_filtered{
    position = entity.position, radius = 6, type = "unit"
  }
  for _, unit in pairs(units) do
    if unit.valid
       and (unit.force == enemy_force or unit.force == hive_force)
       and is_hive_creature_for_role(unit, shared.creature_roles.store) then
      local item_name = shared.creature_item_name(unit.name)
      unit.destroy({raise_destroy = true})
      inv.insert{name = item_name, count = 1}
    end
  end
end

local function tick_absorption()
  for _, hive in pairs(all_hives()) do
    absorb_units_into_hive(hive)
  end
end

-- ── Unit commands ─────────────────────────────────────────────────────────────

local function command_unit_to_entity(unit, target_entity)
  if not (unit and unit.valid and target_entity and target_entity.valid) then return end
  local commandable = unit.commandable
  if not commandable then return end
  commandable.set_command{
    type = defines.command.go_to_location,
    destination = target_entity.position,
    distraction = defines.distraction.none,
    radius = 5
  }
end

local function command_unit_to_position(unit, position)
  if not (unit and unit.valid and position) then return end
  local commandable = unit.commandable
  if not commandable then return end
  commandable.set_command{
    type = defines.command.go_to_location,
    destination = position,
    distraction = defines.distraction.none,
    radius = 1
  }
end

-- ── Join hive ─────────────────────────────────────────────────────────────────

local function apply_hive_director_state(player)
  local force = get_hive_force()
  configure_hive_force(force)
  player.force = force
  player.permission_group = get_hive_permission_group()
  if player.controller_type ~= defines.controllers.god then
    player.set_controller({type = defines.controllers.god})
  end
  local inv = player.get_main_inventory()
  if inv then inv.clear() end
  player.clear_cursor()
end

local function join_hive(player)
  if is_hive_player(player) then return end
  local current = get_state()
  current.joined_players[player.index] = true
  apply_hive_director_state(player)
  update_join_button(player)
  player.print({"gui.hm-hive-joined"})
end

-- ── Hive death / release living creatures ─────────────────────────────────────
-- R6: stored creatures respawn as living units on the hive force.

local function release_hive_contents(entity)
  if not (entity and entity.valid) then return end
  local chest = get_hive_chest(entity)
  if not chest then return end
  local inv = chest.get_inventory(defines.inventory.chest)
  if inv then
    local surface = entity.surface
    local hive_force = get_hive_force()
    for i = 1, #inv do
      local stack = inv[i]
      if stack and stack.valid_for_read then
        local unit_name = shared.creature_unit_name(stack.name)
        if unit_name and prototypes.entity[unit_name] then
          local count = stack.count
          for _ = 1, count do
            local pos = surface.find_non_colliding_position(
              unit_name, entity.position, 8, 0.5)
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
  chest.destroy()
  local storage = get_hive_storage(entity)
  if storage then storage.chest = nil end
end

local function destroy_previous_player_hives(player_index, new_hive)
  local current = get_state()
  current.hives_by_player[player_index] = current.hives_by_player[player_index] or {}
  local bucket = current.hives_by_player[player_index]
  for unit_number, hive_data in pairs(bucket) do
    if unit_number ~= new_hive.unit_number then
      local e = hive_data.entity
      if e and e.valid then
        release_hive_contents(e)
        e.destroy({raise_destroy = true})
      end
      current.hive_storage[unit_number] = nil
      bucket[unit_number] = nil
    end
  end
end

-- ── Cost / refund plumbing ────────────────────────────────────────────────────

local function refund_player_item(player_index, item_name, count)
  if not (player_index and item_name) then return end
  local player = game.get_player(player_index)
  if not (player and player.valid) then return end
  local inv = player.get_main_inventory()
  if not inv then return end
  inv.insert{name = item_name, count = count or 1}
end

-- Charge for a build at `surface, position`.
-- Returns: true / false, reason (same shape as consume_network_pollution).
local function charge_for_build(surface, position, entity_name)
  local cost = compute_build_cost(entity_name)
  if cost <= 0 then return true end
  return consume_network_pollution(surface, position, cost)
end

-- ── Ghost fulfillment ─────────────────────────────────────────────────────────

local function tech_for_ghost(ghost_name)
  if ghost_name == shared.entities.hive_node      then return shared.technologies.hive_spawners end
  if ghost_name == shared.entities.spawner_ghost  then return shared.technologies.hive_spawners end
  if ghost_name == shared.entities.hive_lab       then return shared.technologies.hive_labs end
  for _, tier in pairs(shared.worm_tiers) do
    if ghost_name == shared.worm[tier].ghost then return shared.worm[tier].tech end
  end
  return nil
end

local function fulfill_ghost(ghost, player_index)
  if not (ghost and ghost.valid) then return end
  local ghost_name = ghost.ghost_name
  if not ghost_name then return end

  -- Tech gating for hive-tier structures.
  local required_tech = tech_for_ghost(ghost_name)
  if required_tech then
    local tech = ghost.force.technologies[required_tech]
    if not (tech and tech.researched) then
      if player_index then
        local p = game.get_player(player_index)
        if p then p.print({"message.hm-tech-required"}) end
      end
      ghost.destroy()
      return
    end
  end

  local cost = compute_build_cost(ghost_name)
  local ok, reason = consume_network_pollution(ghost.surface, ghost.position, cost)
  if not ok then
    print_charge_failure(player_index, reason)
    -- Leave the ghost up so it auto-fulfils when resources arrive.
    return
  end

  local item_name = shared.ghost_items[ghost_name] or ghost_name
  local item_proto = prototypes.item[item_name]
  if not item_proto then
    -- Cost was charged but no item; the ghost will sit unbuilt. Rare: only
    -- happens for entities whose item we couldn't resolve.
    return
  end
  if not insert_into_network(ghost.surface, ghost.position, {name = item_name, count = 1}) then
    -- Network full; fall back to dropping the item on the ground at the ghost.
    ghost.surface.spill_item_stack(
      ghost.position, {name = item_name, count = 1}, true, ghost.force, false)
  end
end

-- ── Recruitment ───────────────────────────────────────────────────────────────

local function recruit_units_to_hive_targets()
  local current = get_state()
  local enemy_force = get_enemy_force()
  local hive_force = get_hive_force()

  for player_index in pairs(current.joined_players) do
    local player = game.get_player(player_index)
    if not (player and player.valid) then goto continue end

    local hive = get_primary_player_hive(player_index)
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
         and is_hive_creature_for_role(unit, shared.creature_roles.attract) then
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

-- ── Lab supply ────────────────────────────────────────────────────────────────

local function supply_labs()
  local hive_force = get_hive_force()
  for _, surface in pairs(game.surfaces) do
    local labs = surface.find_entities_filtered{
      name = shared.entities.hive_lab, force = hive_force
    }
    for _, lab in pairs(labs) do
      if lab.valid then
        local lab_inv = lab.get_inventory(defines.inventory.lab_input)
        if lab_inv and lab_inv.get_item_count(shared.items.pollution_science_pack) < 10 then
          if consume_network_pollution(surface, lab.position, shared.science.pollution_per_pack) then
            lab_inv.insert{name = shared.items.pollution_science_pack, count = 1}
          end
        end
      end
    end
  end
end

-- ── Creep spreading (organic) ─────────────────────────────────────────────────
-- Layered random sampler:
--   - 10% of attempts probe the outer edge (front + 1) to expand the territory
--   - 60% land in the frontier band [front-3, front] to thicken the ring
--   - 30% backfill anywhere in [1, front-4] so inner gaps don't stay bare
-- The `front` advances by 1 per call only when an edge probe succeeded, and
-- only with 50% probability — so growth is gradual instead of jumping to max.

local function place_organic_creep(entity, record, max_radius, attempts)
  local surface = entity.surface
  local cx, cy = entity.position.x, entity.position.y
  local rng = game.create_random_generator(
    (entity.unit_number or 0) * 7919 + game.tick)
  local placed = 0
  local tiles = {}
  local front = math.min(max_radius, math.max(2, math.floor(record.creep_front or 2)))
  local edge_hits = 0

  for _ = 1, attempts do
    local angle = rng() * math.pi * 2
    local dx, dy = math.cos(angle), math.sin(angle)
    local roll = rng(1, 100)
    local r
    if roll <= 10 then
      r = math.min(max_radius, front + 1)                  -- edge probe
    elseif roll <= 70 then
      r = rng(math.max(1, front - 3), front)               -- frontier band
    else
      r = rng(1, math.max(1, front - 4))                   -- inner backfill
    end
    local tx = math.floor(cx + dx * r + 0.5)
    local ty = math.floor(cy + dy * r + 0.5)
    local tile = surface.get_tile(tx, ty)
    if tile and tile.valid then
      local name = tile.name
      if not shared.is_creep_tile(name)
         and not name:find("water", 1, true)
         and not name:find("void", 1, true) then
        tiles[#tiles + 1] = {
          name = shared.random_creep_tile(rng),
          position = {tx, ty}
        }
        placed = placed + 1
        if r >= front then edge_hits = edge_hits + 1 end
      end
    end
  end

  if edge_hits > 0 and front < max_radius and rng(1, 2) == 1 then
    record.creep_front = math.min(max_radius, front + 1)
  end

  if #tiles > 0 then
    surface.set_tiles(tiles, true)
  end
  return placed > 0
end

local function tick_creep()
  local hive_attempts = shared.creep_tiles_per_call.hive
  local node_attempts = shared.creep_tiles_per_call.hive_node
  local hive_r        = shared.creep_radius.hive
  local node_r        = shared.creep_radius.hive_node

  for _, hive in pairs(all_hives()) do
    local storage = get_hive_storage(hive)
    if storage then
      local placed = place_organic_creep(hive, storage, hive_r, hive_attempts)
      if placed then
        local tech = hive.force.technologies[shared.technologies.hive_labs]
        if tech and not tech.researched then
          tech.researched = true
          local recipe = hive.force.recipes[shared.recipes.hive_lab]
          if recipe then recipe.enabled = true end
        end
      end
    end
  end

  local current = get_state()
  for _, node_data in pairs(current.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      place_organic_creep(node, node_data, node_r, node_attempts)
    end
  end
end

-- ── Pollution generators (debug) ──────────────────────────────────────────────

local function tick_pollution_generators()
  local current = get_state()
  local amount = shared.pollution_generator_per_tick
  for id, entity in pairs(current.pollution_generators) do
    if entity and entity.valid then
      entity.surface.pollute(entity.position, amount)
    else
      current.pollution_generators[id] = nil
    end
  end
end

-- ── Static charting ───────────────────────────────────────────────────────────

local function chart_area(entity, range)
  if not (entity and entity.valid) then return end
  local pos = entity.position
  entity.force.chart(entity.surface,
    {{pos.x - range, pos.y - range}, {pos.x + range, pos.y + range}})
end

-- ── Hive worker maintenance ───────────────────────────────────────────────────

local function init_hive(entity)
  if not (entity and entity.valid) then return end
  local robot_inv = entity.get_inventory(defines.inventory.roboport_robot)
  if robot_inv then
    local needed = shared.hive_robot_count
                 - robot_inv.get_item_count(shared.items.construction_robot)
    if needed > 0 then
      robot_inv.insert{name = shared.items.construction_robot, count = needed}
    end
  end
end

local function tick_robots()
  for _, hive in pairs(all_hives()) do
    init_hive(hive)
  end
end

-- Spawn a small-biter corpse where the worker died to fake a death animation.
local function spawn_worker_corpse(entity)
  if not (entity and entity.valid) then return end
  local corpse_name = "small-biter-corpse"
  if prototypes.entity[corpse_name] then
    pcall(function()
      entity.surface.create_entity{
        name = corpse_name, position = entity.position, force = entity.force
      }
    end)
  end
end

-- ── Proxy → real swap ─────────────────────────────────────────────────────────

local function proxy_real_name(entity_name)
  if entity_name == shared.entities.spawner_ghost then return "biter-spawner" end
  for _, tier in pairs(shared.worm_tiers) do
    if entity_name == shared.worm[tier].ghost then return shared.worm[tier].real end
  end
  return nil
end

local function swap_proxy_for_real(entity, real_name, real_force)
  if not (entity and entity.valid) then return end
  local pos = {x = entity.position.x, y = entity.position.y}
  local surface = entity.surface
  entity.destroy()
  if not prototypes.entity[real_name] then return end
  surface.create_entity{
    name = real_name, position = pos, force = real_force, raise_built = true
  }
end

-- ── Event: built ──────────────────────────────────────────────────────────────

local function on_built_entity(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end
  local player_index = event.player_index

  -- Hive placed by player. No cost; the hive itself is always free.
  if entity.name == shared.entities.hive then
    if player_index then
      destroy_previous_player_hives(player_index, entity)
      track_hive(player_index, entity)
    end
    create_hive_chest(entity)
    init_hive(entity)
    chart_area(entity, shared.ranges.hive)
    local tech = entity.force.technologies[shared.technologies.hive_spawners]
    if tech and not tech.researched then tech.researched = true end
    for _, rname in pairs({shared.recipes.hive_node, shared.recipes.hive_spawner}) do
      local recipe = entity.force.recipes[rname]
      if recipe then recipe.enabled = true end
    end
    return
  end

  -- Hive node placed directly (rare).
  if entity.name == shared.entities.hive_node then
    if player_index then
      local ok, reason = charge_for_build(entity.surface, entity.position, entity.name)
      if not ok then
        print_charge_failure(player_index, reason)
        refund_player_item(player_index, shared.items.hive_node)
        entity.destroy()
        return
      end
    end
    track_hive_node(entity)
    chart_area(entity, shared.ranges.hive_node)
    return
  end

  -- Hive lab placed directly.
  if entity.name == shared.entities.hive_lab then
    if player_index then
      local ok, reason = charge_for_build(entity.surface, entity.position, entity.name)
      if not ok then
        print_charge_failure(player_index, reason)
        refund_player_item(player_index, shared.items.hive_lab)
        entity.destroy()
        return
      end
    end
    return
  end

  -- Spawner / worm proxy placed directly: charge, swap, done.
  local real_name = proxy_real_name(entity.name)
  if real_name then
    if player_index then
      local ok, reason = charge_for_build(entity.surface, entity.position, entity.name)
      if not ok then
        print_charge_failure(player_index, reason)
        local refund = shared.ghost_items[entity.name] or entity.name
        refund_player_item(player_index, refund)
        entity.destroy()
        return
      end
    end
    swap_proxy_for_real(entity, real_name, get_enemy_force())
    return
  end

  -- Pollution generator (debug) placed.
  if entity.name == shared.entities.pollution_generator then
    local current = get_state()
    current.pollution_generators[entity.unit_number] = entity
    return
  end

  -- Ghost placed (any kind): cost + insert + worker fulfils.
  if entity.type == "entity-ghost" then
    fulfill_ghost(entity, player_index)
    return
  end
end

-- ── Event: robot built ────────────────────────────────────────────────────────

local function on_robot_built_entity(event)
  local robot = event.robot
  local entity = event.entity or event.created_entity

  if entity and entity.valid then
    if entity.name == shared.entities.hive_node then
      track_hive_node(entity)
      chart_area(entity, shared.ranges.hive_node)
    elseif entity.name == shared.entities.pollution_generator then
      local current = get_state()
      current.pollution_generators[entity.unit_number] = entity
    else
      local real_name = proxy_real_name(entity.name)
      if real_name then
        swap_proxy_for_real(entity, real_name, get_enemy_force())
      end
    end
  end

  -- Worker dies on the build site: corpse + silent destroy. We can't use
  -- robot.die() because that would re-enter on_entity_died with this same
  -- handler attached.
  if robot and robot.valid and robot.name == shared.entities.construction_robot then
    spawn_worker_corpse(robot)
    robot.destroy()
  end
end

-- ── Event: removed ────────────────────────────────────────────────────────────

local function on_removed_entity(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name == shared.entities.hive then
    release_hive_contents(entity)
    untrack_hive(entity)
  elseif entity.name == shared.entities.hive_node then
    untrack_hive_node(entity)
  elseif entity.name == shared.entities.pollution_generator then
    local current = get_state()
    current.pollution_generators[entity.unit_number] = nil
  elseif entity.name == shared.entities.hive_storage then
    local current = get_state()
    for _, bucket in pairs(current.hives_by_player) do
      for _, hive_data in pairs(bucket) do
        local hive = hive_data.entity
        if hive and hive.valid then
          local s = current.hive_storage[hive.unit_number]
          if s and s.chest == entity then s.chest = nil end
        end
      end
    end
  end
end

-- ── Event: player created / respawned ─────────────────────────────────────────

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then update_join_button(player) end
end

local function on_player_respawned(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  apply_hive_director_state(player)
end

-- ── Event: GUI click ──────────────────────────────────────────────────────────

local function on_gui_click(event)
  if event.element.name ~= shared.gui.join_button then return end
  local player = game.get_player(event.player_index)
  if player then join_hive(player) end
end

-- ── Event: GUI opened ─────────────────────────────────────────────────────────

local allowed_entity_gui =
{
  [shared.entities.hive] = true,
  [shared.entities.hive_node] = true,
  [shared.entities.hive_lab] = true,
  [shared.entities.hive_storage] = true
}

local function on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  if event.gui_type == defines.gui_type.controller then return end
  if event.gui_type == defines.gui_type.crafting then return end
  if event.gui_type == defines.gui_type.none then return end
  if event.gui_type == defines.gui_type.entity then
    if event.entity and event.entity.valid and allowed_entity_gui[event.entity.name] then
      return
    end
  end
  player.opened = nil
end

-- ── Event: player mined ───────────────────────────────────────────────────────

local queued_restorations = {}

local function on_player_mined_entity(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  if event.buffer then event.buffer.clear() end
  local entity = event.entity
  if entity and entity.valid then
    queued_restorations[#queued_restorations + 1] =
    {
      name = entity.name,
      position = {x = entity.position.x, y = entity.position.y},
      direction = entity.direction,
      surface_index = entity.surface.index,
      force_name = entity.force and entity.force.name
    }
  end
  player.print({"message.hm-no-mining"})
end

local function on_player_mined_item(event)
  local player = game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local inv = player.get_main_inventory()
  if inv and event.item_stack then
    inv.remove{name = event.item_stack.name, count = event.item_stack.count}
  end
end

local function restore_mined_entities()
  if #queued_restorations == 0 then return end
  local pending = queued_restorations
  queued_restorations = {}
  for _, r in pairs(pending) do
    local surface = game.surfaces[r.surface_index]
    if surface then
      pcall(function()
        surface.create_entity{
          name = r.name, position = r.position,
          direction = r.direction, force = r.force_name
        }
      end)
    end
  end
end

local function clear_forbidden_inventory(player, inventory_id)
  if not is_hive_player(player) then return end
  local inv = player.get_inventory(inventory_id)
  if inv then inv.clear() end
end

-- ── on_tick ───────────────────────────────────────────────────────────────────

local function on_tick(event)
  restore_mined_entities()
  local tick = event.tick
  if tick % shared.intervals.recruit == 0 then recruit_units_to_hive_targets() end
  if tick % shared.intervals.absorb  == 0 then tick_absorption() end
  if tick % shared.intervals.supply  == 0 then supply_labs() end
  if tick % shared.intervals.robots  == 0 then tick_robots() end
  if tick % shared.intervals.creep   == 0 then tick_creep() end
  tick_pollution_generators()
end

-- ── Remote interface ──────────────────────────────────────────────────────────

remote.add_interface("hive_reboot",
{
  register_creature_role = function(entity_name, role)
    local current = get_state()
    current.hive_roles[entity_name] = current.hive_roles[entity_name] or {}
    current.hive_roles[entity_name][role] = true
  end,
  unregister_creature_role = function(entity_name, role)
    local current = get_state()
    if current.hive_roles[entity_name] then
      current.hive_roles[entity_name][role] = nil
    end
  end,
  join_hive = function(player_index)
    local player = game.get_player(player_index)
    if player then join_hive(player) end
  end
})

-- ── Init / config changed ─────────────────────────────────────────────────────

script.on_init(function()
  get_state()
  configure_hive_force(get_hive_force())
  get_hive_permission_group()
  update_all_join_buttons()
end)

script.on_configuration_changed(function()
  local current = get_state()
  configure_hive_force(get_hive_force())
  get_hive_permission_group()
  update_all_join_buttons()
  for player_index in pairs(current.joined_players) do
    local player = game.get_player(player_index)
    if player and player.valid and player.controller_type ~= defines.controllers.god then
      player.set_controller({type = defines.controllers.god})
    end
  end
  for _, hive in pairs(all_hives()) do
    local s = get_hive_storage(hive)
    if s and not (s.chest and s.chest.valid) then
      create_hive_chest(hive)
    end
    init_hive(hive)
  end
end)

-- ── Event registration ────────────────────────────────────────────────────────

script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_player_respawned, on_player_respawned)
script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity)
script.on_event(defines.events.on_player_mined_item, on_player_mined_item)

script.on_event(defines.events.on_player_gun_inventory_changed, function(event)
  clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_guns)
end)
script.on_event(defines.events.on_player_ammo_inventory_changed, function(event)
  clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_ammo)
end)
script.on_event(defines.events.on_player_armor_inventory_changed, function(event)
  clear_forbidden_inventory(game.get_player(event.player_index), defines.inventory.character_armor)
end)

script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.script_raised_built, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_robot_built_entity)

script.on_event(defines.events.on_entity_died, on_removed_entity)
script.on_event(defines.events.on_robot_mined_entity, on_removed_entity)
script.on_event(defines.events.script_raised_destroy, on_removed_entity)

script.on_event(defines.events.on_marked_for_deconstruction, function(event)
  local player = event.player_index and game.get_player(event.player_index)
  if not is_hive_player(player) then return end
  local entity = event.entity
  if entity and entity.valid then
    entity.cancel_deconstruction(entity.force, player)
  end
  if player then player.print({"message.hm-no-deconstruction"}) end
end)
