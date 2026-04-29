-- Build pipeline: ghost fulfilment, direct placement, and proxy → real swap.
--
-- Three placement paths:
--
--   1. Player places a hive item directly       → on_built_entity
--   2. Player places a ghost (any kind)         → on_built_entity → fulfill_ghost
--   3. Hive worker delivers a ghost             → on_robot_built_entity
--
-- "Proxy" entities are placeholder prototypes whose only job is to be swapped
-- for an enemy-force real entity (biter spawner, worm turret) once placed.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Hive      = require("script.hive")
local Network   = require("script.network")
local Cost      = require("script.cost")
local Death     = require("script.death")

local M = {}

-- ── Obstruction guard ────────────────────────────────────────────────────────
--
-- The hive does not deconstruct: its workers cannot mine trees, rocks, or
-- cliffs. If the player places on top of any of those, the engine would
-- normally mark them for deconstruction and ghost-build the structure, which
-- would either sit unbuilt forever or leave the world in a collision state
-- once we cancel the deconstruction order. Refuse the placement up front.

local OBSTRUCTION_TYPES = {"tree", "cliff", "simple-entity"}

local function placement_obstructed(entity)
  if not (entity and entity.valid) then return false end
  local found = entity.surface.find_entities_filtered{
    area = entity.bounding_box,
    type = OBSTRUCTION_TYPES
  }
  for _, e in pairs(found) do
    if e ~= entity and e.valid then return true end
  end
  return false
end

-- Map the entity actually placed by the engine to the player-facing item the
-- player consumed from their cursor. Used to refund on a refused placement.
local function placed_entity_item(entity_name)
  if shared.ghost_items[entity_name] then return shared.ghost_items[entity_name] end
  if entity_name == shared.entities.hive                then return shared.items.hive                end
  if entity_name == shared.entities.hive_node           then return shared.items.hive_node           end
  if entity_name == shared.entities.hive_lab            then return shared.items.hive_lab            end
  if entity_name == shared.entities.pollution_generator then return shared.items.pollution_generator end
  return nil
end

local function refuse_obstructed_placement(entity, player_index)
  if player_index then
    local item_name = placed_entity_item(entity.name)
    if item_name then Cost.refund_player_item(player_index, item_name) end
    local p = game.get_player(player_index)
    if p then p.print({"message.hm-placement-obstructed"}) end
  end
  entity.destroy()
end

-- ── Proxy → real swap ────────────────────────────────────────────────────────

local function proxy_real_name(entity_name)
  if entity_name == shared.entities.spawner_ghost         then return "biter-spawner"   end
  if entity_name == shared.entities.spitter_spawner_ghost then return "spitter-spawner" end
  for _, tier in pairs(shared.worm_tiers) do
    if entity_name == shared.worm[tier].ghost then return shared.worm[tier].real end
  end
  return nil
end

-- Replace `entity` with a real `real_name` entity on `real_force` at the same
-- position. raise_built fires so vanilla scripts (and our own listeners)
-- treat the result as a normal placement.
local function swap_proxy_for_real(entity, real_name, real_force)
  if not (entity and entity.valid) then return end
  local pos     = {x = entity.position.x, y = entity.position.y}
  local surface = entity.surface
  entity.destroy()
  if not prototypes.entity[real_name] then return end
  surface.create_entity{
    name = real_name, position = pos, force = real_force, raise_built = true
  }
end

-- ── Ghost fulfilment ─────────────────────────────────────────────────────────

local function tech_for_ghost(ghost_name)
  if ghost_name == shared.entities.hive_node             then return shared.technologies.hive_spawners end
  if ghost_name == shared.entities.spawner_ghost         then return shared.technologies.hive_spawners end
  if ghost_name == shared.entities.spitter_spawner_ghost then return shared.technologies.hive_spawners end
  if ghost_name == shared.entities.hive_lab              then return shared.technologies.hive_labs end
  for _, tier in pairs(shared.worm_tiers) do
    if ghost_name == shared.worm[tier].ghost then return shared.worm[tier].tech end
  end
  return nil
end

-- Pay the cost for `ghost` from the network and insert a fulfilment item into
-- the network's chest. The chest's worker then picks the item up and builds.
-- A ghost that cannot be fulfilled (any reason — tech, obstruction, charge
-- failure) is destroyed rather than left lingering, so the world doesn't
-- accumulate dead ghosts the player thinks will eventually build.
local function fulfill_ghost(ghost, player_index)
  if not (ghost and ghost.valid) then return end
  local ghost_name = ghost.ghost_name
  if not ghost_name then return end

  local function notify(msg)
    if not player_index then return end
    local p = game.get_player(player_index)
    if p then p.print(msg) end
  end

  -- Tech gating for hive-tier structures.
  local required_tech = tech_for_ghost(ghost_name)
  if required_tech then
    local tech = ghost.force.technologies[required_tech]
    if not (tech and tech.researched) then
      notify({"message.hm-tech-required"})
      ghost.destroy()
      return
    end
  end

  -- Refuse obstructed builds — the hive doesn't clear terrain, so a ghost
  -- on top of trees/rocks/cliffs would never be fulfilled.
  if placement_obstructed(ghost) then
    notify({"message.hm-placement-obstructed"})
    ghost.destroy()
    return
  end

  local cost = Cost.build_cost(ghost_name)
  local ok, reason, info = Cost.consume(ghost.surface, ghost.position, cost)
  if not ok then
    Cost.print_charge_failure(player_index, reason, info)
    ghost.destroy()
    return
  end

  local item_name  = shared.ghost_items[ghost_name] or ghost_name
  local item_proto = prototypes.item[item_name]
  if not item_proto then
    -- Cost was charged but no item to insert; the ghost would sit unbuilt,
    -- so destroy it. Rare: only happens for entities whose item we can't
    -- resolve.
    ghost.destroy()
    return
  end
  if not Network.insert(ghost.surface, ghost.position, {name = item_name, count = 1}) then
    -- Network full: drop the item on the ground at the ghost as a fallback.
    ghost.surface.spill_item_stack(
      ghost.position, {name = item_name, count = 1}, true, ghost.force, false)
  end
end

-- ── Direct-placement helpers ─────────────────────────────────────────────────

-- Charge-or-refund flow for a direct hive-item placement. On failure: print
-- the localised message, refund the player's item, destroy `entity`, return
-- false. On success: return true.
-- Charge pollution for the placement at `entity.position` and either refund
-- the item back to the cursor (success) or refund + destroy (failure).
-- Hive recipes are zero-ingredient: the actual cost is the pollution just
-- paid, so the cursor item is really a placement tool. Refunding on success
-- keeps the player from running dry mid-row and accidentally placing ghosts.
local function charge_or_refund(entity, player_index, refund_item_name)
  local ok, reason, info = Cost.charge_build(entity.surface, entity.position, entity.name)
  if not ok then
    Cost.print_charge_failure(player_index, reason, info)
    Cost.refund_player_item(player_index, refund_item_name)
    entity.destroy()
    return false
  end
  Cost.refund_player_item(player_index, refund_item_name)
  return true
end

-- Hive placed by player. Free; first-hive-ever flips the spawner tech and
-- enables the gated recipes.
local function on_hive_placed(entity, player_index)
  if player_index then
    Death.destroy_previous_player_hives(player_index, entity)
    Hive.track(player_index, entity)
  end
  Hive.create_chest(entity)
  Hive.init(entity)
  Hive.chart(entity, shared.ranges.hive)

  local tech = entity.force.technologies[shared.technologies.hive_spawners]
  if tech and not tech.researched then tech.researched = true end
  for _, rname in pairs({shared.recipes.hive_node, shared.recipes.hive_spawner}) do
    local recipe = entity.force.recipes[rname]
    if recipe then recipe.enabled = true end
  end
end

-- ── Event handlers ───────────────────────────────────────────────────────────

function M.on_built(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end
  local player_index = event.player_index

  -- Obstruction guard for direct placements. Ghosts go through fulfill_ghost
  -- which has its own guard.
  if entity.type ~= "entity-ghost" and placement_obstructed(entity) then
    refuse_obstructed_placement(entity, player_index)
    return
  end

  if entity.name == shared.entities.hive then
    on_hive_placed(entity, player_index)
    if player_index then
      Cost.refund_player_item(player_index, shared.items.hive)
    end
    return
  end

  if entity.name == shared.entities.hive_node then
    if player_index and not charge_or_refund(entity, player_index, shared.items.hive_node) then
      return
    end
    Hive.track_node(entity)
    Hive.chart(entity, shared.ranges.hive_node)
    return
  end

  if entity.name == shared.entities.hive_lab then
    if player_index then
      charge_or_refund(entity, player_index, shared.items.hive_lab)
    end
    return
  end

  -- Spawner / worm proxy placed directly: charge, swap, done.
  local real_name = proxy_real_name(entity.name)
  if real_name then
    if player_index then
      local refund = shared.ghost_items[entity.name] or entity.name
      if not charge_or_refund(entity, player_index, refund) then return end
    end
    swap_proxy_for_real(entity, real_name, Force.get_enemy())
    return
  end

  if entity.name == shared.entities.pollution_generator then
    State.get().pollution_generators[entity.unit_number] = entity
    if player_index then
      Cost.refund_player_item(player_index, shared.items.pollution_generator)
    end
    return
  end

  if entity.type == "entity-ghost" then
    fulfill_ghost(entity, player_index)
    return
  end
end

function M.on_robot_built(event)
  local robot  = event.robot
  local entity = event.entity or event.created_entity

  if entity and entity.valid then
    if entity.name == shared.entities.hive_node then
      Hive.track_node(entity)
      Hive.chart(entity, shared.ranges.hive_node)
    elseif entity.name == shared.entities.pollution_generator then
      State.get().pollution_generators[entity.unit_number] = entity
    else
      local real_name = proxy_real_name(entity.name)
      if real_name then
        swap_proxy_for_real(entity, real_name, Force.get_enemy())
      end
    end
  end

  -- Worker dies on the build site: corpse + silent destroy. We can't use
  -- robot.die() because that would re-enter on_entity_died with this same
  -- handler attached.
  if robot and robot.valid and robot.name == shared.entities.construction_robot then
    Hive.spawn_worker_corpse(robot)
    robot.destroy()
  end
end

return M
