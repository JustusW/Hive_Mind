-- Build pipeline: ghost fulfilment, direct placement, and proxy → real swap.
--
-- Every build (except the hive itself) is animated by a hive worker walking
-- out of the nearest hive. There are three entry points:
--
--   1. Player places a hive item directly → on_built_entity → the entity is
--      charged, the cursor item is refunded, the entity is destroyed and
--      replaced with an entity-ghost at the same spot, then queued in
--      Workers (charge_and_ghostify). The hive itself is the exception —
--      it is built directly because no workers exist before the first hive
--      lands.
--   2. Player places a ghost (any kind) → on_built_entity → fulfill_ghost
--      runs tech / obstruction / consume guards and queues the ghost.
--   3. A worker materialises a queued ghost via
--      surface.create_entity{raise_built = true}. script_raised_built
--      re-enters this handler with player_index = nil, which routes to the
--      tracking / proxy-swap path without re-charging.
--
-- "Proxy" entities are placeholder prototypes whose only job is to be swapped
-- for an enemy-force real entity (biter spawner, worm turret) once placed.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Hive      = require("script.hive")
local Cost      = require("script.cost")
local Death     = require("script.death")
local Workers   = require("script.workers")
local Vent      = require("script.vent")
local Anchor    = require("script.anchor")
local Network   = require("script.network")

local M = {}

-- ── Obstruction guard ────────────────────────────────────────────────────────
--
-- The hive does not deconstruct: its workers cannot mine trees, rocks, or
-- cliffs. If the player places on top of any of those, the engine would
-- normally mark them for deconstruction and ghost-build the structure, which
-- would either sit unbuilt forever or leave the world in a collision state
-- once we cancel the deconstruction order. Refuse the placement up front.

local OBSTRUCTION_TYPES = {"tree", "cliff", "simple-entity"}

-- Detects obstructing terrain in the placement area AND, as a side effect,
-- cancels any deconstruction orders the engine queued for those obstructions
-- on the hive force. Without the cancellation, refusing the placement still
-- leaves the auto-decon mark behind, so a hive worker dispatches to chop
-- the tree we just declined to build over and then hovers indefinitely
-- because the resulting wood has nowhere to land (hive storage is a passive-
-- provider chest and won't accept bot inserts).
local function placement_obstructed(entity)
  if not (entity and entity.valid) then return false end
  local found = entity.surface.find_entities_filtered{
    area = entity.bounding_box,
    type = OBSTRUCTION_TYPES
  }
  local obstructed = false
  local hive_force = Force.get_hive()
  for _, e in pairs(found) do
    if e ~= entity and e.valid then
      obstructed = true
      if e.to_be_deconstructed() then
        if hive_force then e.cancel_deconstruction(hive_force) end
        e.cancel_deconstruction(e.force)
      end
    end
  end
  return obstructed
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

-- Pay the cost for `ghost` from the network, then hand the ghost off to the
-- Workers dispatcher. A unit walks from the nearest in-network hive to the
-- ghost and materialises it on arrival. A ghost that cannot be fulfilled
-- (any reason — tech, obstruction, charge failure) is destroyed rather than
-- left lingering, so the world doesn't accumulate dead ghosts.
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
  local ok, reason, info = Cost.consume(
    ghost.surface, ghost.position, cost, Cost.placement_reach(ghost_name))
  if not ok then
    Cost.print_charge_failure(player_index, reason, info)
    ghost.destroy()
    return
  end

  -- Cost paid, terrain clear: hand the ghost off to the worker dispatcher.
  -- A unit at the closest in-network hive will walk to the ghost and
  -- materialise it on arrival.
  Workers.queue(ghost, player_index)
end

-- ── Direct-placement helpers ─────────────────────────────────────────────────

-- Charge-or-refund flow for a direct hive-item placement. On failure: print
-- the localised message, refund the player's item, destroy `entity`, return
-- false. On success: return true.
-- Charge the network for a player-placed entity. On failure: print, refund
-- the cursor item, destroy the entity. On success: refund the cursor item
-- AND replace the real entity with an entity-ghost at the same position,
-- then queue the ghost so a worker walks over and materialises it. Direct
-- placement and ghost placement therefore converge: every build is animated
-- by a worker out of the nearest hive. Hive recipes are zero-ingredient, so
-- the cursor item is really a placement tool; the actual cost is pollution.
local function charge_and_ghostify(entity, player_index, refund_item_name)
  local ok, reason, info = Cost.charge_build(entity.surface, entity.position, entity.name)
  if not ok then
    Cost.print_charge_failure(player_index, reason, info)
    Cost.refund_player_item(player_index, refund_item_name)
    entity.destroy()
    return false
  end
  Cost.refund_player_item(player_index, refund_item_name)

  local entity_name = entity.name
  local position    = {x = entity.position.x, y = entity.position.y}
  local surface     = entity.surface
  local force       = entity.force
  entity.destroy()
  local ghost = surface.create_entity{
    name        = "entity-ghost",
    inner_name  = entity_name,
    position    = position,
    force       = force,
    raise_built = false
  }
  if ghost and ghost.valid then
    Workers.queue(ghost, player_index)
  end
  return true
end

-- Anchor placed by player (anchor-binding setting ON). The starter hive
-- item came from Anchor.ensure_hive_available; do not refund. We register
-- the entity, give it a chest, chart its construction zone, then hand off
-- to Anchor.tick to finalise after the 30-second construction window
-- (recipe unlocks happen on completion, not on placement).
local function on_anchor_placed(entity, player_index)
  Hive.track(player_index, entity)
  Hive.create_chest(entity)
  Hive.chart(entity, shared.ranges.hive)
  Anchor.start_construction(entity, player_index, Hive.get_storage(entity))
end

-- Legacy hive placement (anchor-binding setting OFF). Behaviour the mod had
-- before the anchor rework: any prior hive of this player is destroyed, the
-- new one is fully live immediately, gated recipes unlock at once, and the
-- placed item is refunded so the cursor stays loaded.
local function on_legacy_hive_placed(entity, player_index)
  Death.destroy_previous_player_hives(player_index, entity)
  Hive.track(player_index, entity)
  Hive.create_chest(entity)
  Hive.chart(entity, shared.ranges.hive)

  local tech = entity.force.technologies[shared.technologies.hive_spawners]
  if tech and not tech.researched then tech.researched = true end
  for _, rname in pairs({
    shared.recipes.hive_node,
    shared.recipes.hive_spawner,
    shared.recipes.hive_spitter_spawner,
    shared.recipes.promote_node
  }) do
    local recipe = entity.force.recipes[rname]
    if recipe then recipe.enabled = true end
  end
end

-- Evolution gate for hive_node placement. Counts existing hive_node entities
-- in the network the new node would join (using node placement-reach so
-- chains can extend outward). Returns true if the placement passes; false
-- after refunding the item and printing the gating message.
local function pass_node_evolution_gate(entity, player_index)
  if not (entity and entity.valid) then return true end
  local enemy = Force.get_enemy()
  local current_evo = enemy and enemy.evolution_factor or 0

  -- Count hive_node entities already in this network. Hives don't count.
  local existing = 0
  local network = Network.resolve_at(entity.surface, entity.position)
  if network and network.members then
    for _, m in ipairs(network.members) do
      if m.kind == "node" and m.entity and m.entity.valid and m.entity ~= entity then
        existing = existing + 1
      end
    end
  end
  -- New node will be the (existing + 1)th, requiring threshold = existing * step.
  local step     = (shared.network and shared.network.evolution_step) or 0.05
  local required = existing * step
  if current_evo + 1e-9 < required then
    if player_index then
      local p = game.get_player(player_index)
      if p then
        p.print({"message.hm-node-evolution-gated",
                 string.format("%.2f", required),
                 string.format("%.2f", current_evo),
                 tostring(existing + 1)})
      end
      Cost.refund_player_item(player_index, shared.items.hive_node)
    end
    entity.destroy()
    return false
  end
  return true
end

-- ── Event handlers ───────────────────────────────────────────────────────────

function M.on_built(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end
  local player_index = event.player_index

  -- Ghost placements run their own pipeline.
  if entity.type == "entity-ghost" then
    fulfill_ghost(entity, player_index)
    return
  end

  if player_index then
    -- Player direct-placement.
    if placement_obstructed(entity) then
      refuse_obstructed_placement(entity, player_index)
      return
    end

    -- Hive placement. Anchor-binding setting ON: track + 30s construction,
    -- no refund (player consumes their one starter item). OFF: legacy
    -- behaviour — destroy previous, live immediately, refund the cursor.
    if entity.name == shared.entities.hive then
      if shared.feature_enabled("hm-anchor-binding") then
        on_anchor_placed(entity, player_index)
      else
        on_legacy_hive_placed(entity, player_index)
        Cost.refund_player_item(player_index, shared.items.hive)
      end
      return
    end

    -- Pheromone Vent (0.9.0): direct-placed, free, buildable anywhere. No
    -- construction-zone check, no cost, no ghost/worker pipeline. Register
    -- and refund the cursor item.
    if entity.name == shared.entities.pheromone_vent then
      Vent.on_built(entity, player_index)
      if entity.valid then
        Cost.refund_player_item(player_index, shared.items.pheromone_vent)
      end
      return
    end

    -- Evolution-gated node count (startup setting hm-evolution-gate). When
    -- on, refuse a hive_node placement if the network already has too many
    -- nodes for the current evolution. When off, no check — the legacy
    -- node-spam behaviour returns.
    if entity.name == shared.entities.hive_node
       and shared.feature_enabled("hm-evolution-gate") then
      if not pass_node_evolution_gate(entity, player_index) then return end
    end

    local refund_item = placed_entity_item(entity.name)
    if refund_item then
      charge_and_ghostify(entity, player_index, refund_item)
    end
    return
  end

  -- Script-raised path: a worker just materialised this entity. Run the
  -- tracking / proxy-swap that the engine event delivers without re-running
  -- charge or refund (those happened when the player originally placed).
  if entity.name == shared.entities.hive then
    -- Worker-built hive (rare; promoted-hive create_entity uses raise_built
    -- = false to skip this path). Treat as a fully-live hive, no anchor
    -- construction window.
    Hive.track(nil, entity)
    Hive.create_chest(entity)
    Hive.chart(entity, shared.ranges.hive)
    return
  end
  if entity.name == shared.entities.hive_node then
    Hive.track_node(entity)
    Hive.chart(entity, shared.ranges.hive_node)
    return
  end
  if entity.name == shared.entities.pollution_generator then
    State.get().pollution_generators[entity.unit_number] = entity
    return
  end
  if entity.name == shared.entities.pheromone_vent then
    Vent.on_built(entity, nil)
    return
  end
  -- Spawner / worm / spitter-spawner proxy → real swap.
  local real_name = proxy_real_name(entity.name)
  if real_name then
    swap_proxy_for_real(entity, real_name, Force.get_enemy())
    return
  end
end

return M
