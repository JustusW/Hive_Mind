-- Pollution arithmetic, build cost, and the consume / charge / refund flow.
--
-- The mod has two currencies stored in the network's chests:
--   * hm-creature-<unit-name>   one per absorbed unit
--   * hm-pollution              hidden currency, stack 10000
--
-- Every spend converts creatures → pollution items as needed, then deducts
-- pollution. Conversion is value-aware: each creature is worth its prototype's
-- absorptions_to_join_attack.pollution (defaulting to 1).

local shared  = require("shared")
local Hive    = require("script.hive")
local Network = require("script.network")

local M = {}

-- ── Pollution value of a creature ─────────────────────────────────────────────

function M.unit_pollution_value(unit_name)
  local proto = prototypes.entity[unit_name]
  if not proto then return 1 end
  local absorb = proto.absorptions_to_join_attack
  if absorb and absorb.pollution then
    return math.max(1, math.floor(absorb.pollution))
  end
  return 1
end

-- ── Build cost ───────────────────────────────────────────────────────────────

-- Pollution cost for placing `entity_name`. Uses the explicit override table
-- in shared.build_costs, falling back to a recipe-derived computation:
--
--     cost = sum(ingredient.amount * shared.item_pollution_factors[ingredient.name])
--
-- Unknown ingredients use shared.default_item_pollution_factor.
-- If no recipe produces the entity's place-item, returns shared.fallback_build_cost.
function M.build_cost(entity_name)
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

-- ── Creature → pollution conversion ──────────────────────────────────────────

-- Convert creature items in `hives` into pollution items until the network has
-- at least `target` pollution. Batch-converts whole stacks at a time, not one
-- creature at a time. Returns the post-conversion pollution total.
function M.convert_creatures(hives, target)
  local total = Network.item_count(hives, shared.items.pollution)
  if total >= target then return total end

  for _, hive in pairs(hives) do
    if total >= target then break end
    local chest = Hive.get_chest(hive)
    if not chest then goto continue end

    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then goto continue end

    for i = 1, #inv do
      if total >= target then break end
      local stack = inv[i]
      if stack and stack.valid_for_read then
        local unit_name = shared.creature_unit_name(stack.name)
        if unit_name then
          local value = M.unit_pollution_value(unit_name)
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

-- ── Charge / consume ─────────────────────────────────────────────────────────

-- Total pollution this network could produce: existing pollution items plus
-- the value of every stored creature, summed across every hive's chest.
-- Read-only; safe to call before deciding whether to spend.
function M.pollution_capacity(hives)
  local total = 0
  for _, hive in pairs(hives) do
    local chest = Hive.get_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv then
        total = total + inv.get_item_count(shared.items.pollution)
        for i = 1, #inv do
          local stack = inv[i]
          if stack and stack.valid_for_read then
            local unit_name = shared.creature_unit_name(stack.name)
            if unit_name then
              total = total + stack.count * M.unit_pollution_value(unit_name)
            end
          end
        end
      end
    end
  end
  return total
end

-- Reach extension applied when looking up a network for a placement. Most
-- placements use 0 (the position must already sit inside the network's
-- build zone). Hive nodes use their own range so the player can extend the
-- network outward without having to plant each new node inside the
-- previous one's footprint.
function M.placement_reach(entity_name)
  if entity_name == shared.entities.hive_node then
    return shared.ranges.hive_node
  end
  return 0
end

-- Charge `amount` pollution from the network covering `position`. `reach`,
-- when non-zero, lets the network resolver count any structure within
-- `s.range + reach` of `position` as covering it (see Network for the
-- node-placement rationale).
-- Returns:  true                                     on success
--           false, "no_hive"                         if no hive is in range
--           false, "insufficient", {need, have}      if pool is too low (no
--                                                    state mutation in this
--                                                    case — biters stay biters)
function M.consume(surface, position, amount, reach)
  if amount <= 0 then return true end

  local hives = Network.hives_for_position(surface, position, reach or 0)
  if not hives then return false, "no_hive" end

  local need  = math.ceil(amount)
  local have  = M.pollution_capacity(hives)
  if have < need then
    return false, "insufficient", {need = need, have = have}
  end

  -- Capacity check passed; only now do we mutate state. convert_creatures
  -- only consumes the minimum needed (it stops once the running total covers
  -- `need`), so no extra biters get burned.
  M.convert_creatures(hives, need)

  local remaining = need
  for _, hive in pairs(hives) do
    if remaining <= 0 then break end
    local chest = Hive.get_chest(hive)
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

-- Convenience wrapper around consume() for build sites. Applies the
-- placement-reach extension keyed off the entity name so node placement
-- can extend the network outward by its own range.
function M.charge_build(surface, position, entity_name)
  local cost = M.build_cost(entity_name)
  if cost <= 0 then return true end
  return M.consume(surface, position, cost, M.placement_reach(entity_name))
end

-- ── Refund / messages ────────────────────────────────────────────────────────

-- Put `count` of `item_name` back on the player. Tries the cursor first so
-- placement stays smooth (the next click can land another building without
-- having to dig the item out of the inventory), and falls back to the main
-- inventory when the cursor is busy.
function M.refund_player_item(player_index, item_name, count)
  if not (player_index and item_name) then return end
  count = count or 1
  local player = game.get_player(player_index)
  if not (player and player.valid) then return end

  local cursor = player.cursor_stack
  if cursor then
    if cursor.valid_for_read and cursor.name == item_name then
      cursor.count = cursor.count + count
      return
    end
    if not cursor.valid_for_read then
      cursor.set_stack{name = item_name, count = count}
      return
    end
  end

  local inv = player.get_main_inventory()
  if inv then inv.insert{name = item_name, count = count} end
end

-- Print the right localised message for a charge failure. `info`, when
-- provided, carries `need` and `have` so the player sees the actual gap
-- (e.g. "needs 100 pollution, only has 30") instead of a generic refusal.
function M.print_charge_failure(player_index, reason, info)
  if not player_index then return end
  local p = game.get_player(player_index)
  if not (p and p.valid) then return end
  if reason == "no_hive" then
    p.print({"message.hm-no-hive-in-range"})
  elseif info and info.need and info.have then
    p.print({"message.hm-insufficient-resources",
             tostring(info.need), tostring(info.have)})
  else
    p.print({"message.hm-insufficient-resources-generic"})
  end
end

return M
