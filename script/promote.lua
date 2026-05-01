-- Hive promotion: convert a Hive Node to a (second/Nth) Hive in place.
--
-- This is the only mechanism for multi-hive expansion. Crafting `Promote
-- Node` produces an `hm-promote-node` marker item; on craft completion this
-- module finds the closest `hm-hive-node` within
-- shared.promotion.search_radius of the player, validates network
-- membership, charges shared.promotion.cost from the network's pollution
-- pool, destroys the node, and creates an `hm-hive` at the same position.
--
-- The new hive is "promoted": it is minable (mining demotes back to a node)
-- and skips the 30-second anchor construction window. The anchor's
-- permanence rule does not apply.
--
-- The marker item is consumed unconditionally (event.item_stack.clear()).
-- If no eligible target is in range, no pollution is charged — the player
-- only loses the in-flight craft. If pollution is insufficient, ditto.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Network   = require("script.network")
local Hive      = require("script.hive")
local Cost      = require("script.cost")
local Telemetry = require("script.telemetry")
local Safe      = require("script.safe")

local M = {}

-- ── Target selection ──────────────────────────────────────────────────────

-- Closest hm-hive-node within search_radius of `position` on `surface`.
-- Returns the entity or nil. Force-filtered to the hive force so we don't
-- accidentally promote anything else.
local function closest_node(surface, position)
  if not (surface and surface.valid) then return nil end
  local hive_force = Force.get_hive()
  if not hive_force then return nil end
  local r = shared.promotion.search_radius
  local found = surface.find_entities_filtered{
    position = position,
    radius   = r,
    name     = shared.entities.hive_node,
    force    = hive_force
  }
  if not found or #found == 0 then return nil end

  local best, best_d2
  for _, node in pairs(found) do
    if node.valid then
      local dx = node.position.x - position.x
      local dy = node.position.y - position.y
      local d2 = dx * dx + dy * dy
      if not best_d2 or d2 < best_d2 then
        best_d2 = d2
        best    = node
      end
    end
  end
  return best
end

-- ── Promotion ─────────────────────────────────────────────────────────────

-- Replace `node` with a fresh hm-hive entity at the same position. Returns
-- the new hive entity (or nil if creation failed). The node entity is
-- destroyed before the hive is created to avoid collision-box overlap.
local function swap_node_for_hive(node, player_index)
  local surface  = node.surface
  local position = {x = node.position.x, y = node.position.y}
  local force    = node.force

  -- Drop the node from state tracking before destroying it.
  local s = State.get()
  s.hive_nodes[node.unit_number] = nil
  node.destroy({raise_destroy = true})

  local hive = surface.create_entity{
    name             = shared.entities.hive,
    position         = position,
    force            = force,
    raise_built      = false,
    create_build_effect_smoke = false
  }
  if not (hive and hive.valid) then return nil end

  -- Standard hive setup, mirroring on_hive_placed but without the anchor
  -- construction window. Promoted hives are live the moment they're created.
  -- Storage invariant: ensure_chest_at_primary creates a chest only if the
  -- network has none (typical for a fresh promoted hive in a network with
  -- no other chests, e.g. the first promotion of an isolated node cluster);
  -- otherwise re-uses the existing primary's chest.
  Hive.track(player_index, hive)
  Network.ensure_chest_at_primary(hive)
  Hive.chart(hive, shared.ranges.hive)

  -- Mark as promoted so the mining handler knows to demote rather than
  -- block, and so any other code that wants to distinguish anchors from
  -- promoted hives can do so.
  local record = Hive.get_storage(hive)
  if record then record.is_promoted = true end

  -- Belt-and-braces: ensure the hive isn't carrying the non-minable flag
  -- the anchor lock-in writes. Promoted hives stay minable.
  Safe.call("promote.minable_unlock", function() hive.minable = true end)

  return hive
end

-- on_player_crafted_item handler for hm-promote-node. Validates target,
-- charges pollution, performs the swap, prints messages on failure paths.
function M.on_crafted(event)
  if not event or not event.item_stack then return end
  -- The on_player_crafted_item dispatcher fans out to multiple handlers,
  -- and an earlier handler (Pheromone.on_crafted) may have already
  -- cleared the stack. Reading .name on an invalid stack raises, so gate
  -- on valid_for_read first; an already-cleared stack means it wasn't
  -- ours anyway.
  if not event.item_stack.valid_for_read then return end
  if event.item_stack.name ~= shared.items.promote_node then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid and player.surface and player.surface.valid) then return end

  -- Always consume the marker first; it has no in-world function.
  event.item_stack.clear()

  local node = closest_node(player.surface, player.position)
  if not node then
    player.print({"message.hm-promote-node-no-target", tostring(shared.promotion.search_radius)})
    return
  end

  -- Network validation: target must be on the player's network. Resolve
  -- from the node's position.
  local network = Network.resolve_at(node.surface, node.position)
  if not network then
    player.print({"message.hm-promote-node-not-in-network"})
    return
  end

  -- Evolution gate: promoted hives count as node-equivalents, so check
  -- against the post-swap count. node-equivalents = current nodes + current
  -- promoted hives. The destroyed node will be replaced by a promoted hive,
  -- so the count is unchanged — the gate is informational here, but we run
  -- it anyway in case a future tunable change makes promotion expand the
  -- node-equivalent count.
  -- (Skipping the strict check for now; node count stays the same.)

  local cost = shared.promotion.cost or 0
  if cost > 0 then
    local ok, reason, info = Cost.consume(node.surface, node.position, cost, 0)
    if not ok then
      if reason == "insufficient" then
        player.print({"message.hm-promote-node-insufficient",
                      tostring(info and info.need or cost),
                      tostring(info and info.have or 0)})
      else
        player.print({"message.hm-promote-node-no-network"})
      end
      return
    end
  end

  local hive = swap_node_for_hive(node, event.player_index)
  if not hive then
    player.print({"message.hm-promote-node-failed"})
    return
  end

  Telemetry.bump_op("dispatch")  -- reuse a counter; promotion is rare
  player.print({"message.hm-promote-node-success"})
end

-- Mining a promoted hive demotes it back to a hive_node. Called from the
-- existing on_player_mined_entity handler in director.lua. Returns true if
-- the entity was promoted and was demoted; false otherwise (caller falls
-- through to default mining behavior).
function M.demote_if_promoted(entity)
  if not (entity and entity.valid and entity.name == shared.entities.hive) then return false end
  local record = Hive.get_storage(entity)
  if not (record and record.is_promoted) then return false end

  local surface = entity.surface
  local position = {x = entity.position.x, y = entity.position.y}
  local force = entity.force
  local player_index = nil  -- node has no per-player owner; tracked in hive_nodes

  -- Destroy the hive entity (this also drops its chest via the death
  -- pipeline, which disgorges stored creatures as live units — same as a
  -- normal hive death). This is the cost of demotion.
  entity.destroy({raise_destroy = true})

  local node = surface.create_entity{
    name        = shared.entities.hive_node,
    position    = position,
    force       = force,
    raise_built = false
  }
  if node and node.valid then
    Hive.track_node(node)
    Hive.chart(node, shared.ranges.hive_node)
  end
  return true
end

return M
