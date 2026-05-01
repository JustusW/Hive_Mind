-- Player pheromone burst.
--
-- A one-shot, building-less pheromone vent. Crafting `hm-pheromones-on`
-- locks a position at the player's location and turns it into a temporary
-- attractor: the network's incoming biter stream (recruited + disgorged) is
-- diverted there until N biters have arrived, at which point they form an
-- engine-routed attack group and the burst clears.
--
-- Singleton: only one instance is ever live. Re-crafting overwrites the
-- previous record (effective cancellation during gather). Re-crafting after
-- dispatch is unrelated to the dispersed group — that group is a real
-- engine attack group running on its own.
--
-- A hard timeout (`shared.pheromone_burst.timeout_ticks`) clears any burst
-- that has been live too long without reaching its target_size. Without
-- this, a burst placed somewhere with no biters within attack range would
-- permanently divert recruitment and pile up units around the spot.
--
-- State at `state.active_pheromone`:
--   { surface_index, position = {x,y}, target_size, gather_count,
--     seen_units = {}, started_tick, disgorged = bool }
-- or nil.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Telemetry = require("script.telemetry")
local Safe      = require("script.safe")

local M = {}

-- ── Sizing ─────────────────────────────────────────────────────────────────

-- X = same as a default-mode Pheromone Vent's attack_group_size, scaled by
-- the Attack Group Size tech.
local function target_size_now()
  local force = Force.get_hive()
  local base  = shared.pheromone_vent.base_size
  if not force then return math.max(1, base) end
  local tech = force.technologies[shared.technologies.attack_group_size]
  if not tech then return math.max(1, base) end
  local levels = tech.level - 1
  if levels < 0 then levels = 0 end
  return math.max(1, base + shared.pheromone_vent.tech_increment * levels)
end

-- ── Public lookups ─────────────────────────────────────────────────────────

function M.active(s)
  s = s or State.get()
  return s.active_pheromone
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

-- Strip every hm-pheromones item from a player. The item exists only as the
-- recipe's result and has no in-world function — the recipe completion event
-- is what triggers the burst, not "carrying the item".
--
-- All API touches on the player route through Safe because hive directors
-- run on the god controller, where a few inventory accessors behave
-- differently than character-controller players and have raised in past
-- versions.
local function strip_pheromone_items(player)
  if not (player and player.valid) then return end
  Safe.call("pheromone.cursor_strip", function()
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == shared.items.pheromones then
      cursor.clear()
    end
  end)
  Safe.call("pheromone.inventory_strip", function()
    local inv = player.get_main_inventory()
    if inv then
      local n = inv.get_item_count(shared.items.pheromones)
      if n and n > 0 then
        inv.remove({name = shared.items.pheromones, count = n})
      end
    end
  end)
end

local function start(s, surface_index, position)
  s.active_pheromone = {
    surface_index = surface_index,
    position      = {x = position.x, y = position.y},
    target_size   = target_size_now(),
    gather_count  = 0,
    seen_units    = {},
    started_tick  = game.tick,
    disgorged     = false
  }
end

-- on_player_crafted_item handler. Only `hm-pheromones` matters; other crafts
-- are ignored. Cancels any live instance, starts a fresh one at the player's
-- current position, and consumes the produced item via the event's stack
-- handle (reliable — searching the inventory afterwards races with engine
-- delivery and was the source of the "item stuck in inventory" bug).
function M.on_crafted(event)
  if not event or not event.item_stack then return end
  -- A sibling handler in the on_player_crafted_item dispatcher may have
  -- already cleared the stack; reading .name on an invalid stack raises.
  -- Bail out cleanly if so.
  if not event.item_stack.valid_for_read then return end
  if event.item_stack.name ~= shared.items.pheromones then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid and player.surface and player.surface.valid) then return end

  -- Wipe the just-crafted stack before it ever lands in the player's inv,
  -- and then sweep any leftovers (e.g. from earlier broken builds where the
  -- item lingered).
  if event.item_stack.valid_for_read then event.item_stack.clear() end
  strip_pheromone_items(player)

  local s = State.get()
  start(s, player.surface.index, player.position)
end

-- Cleanup hook: clear any active burst and strip leftover items from joined
-- players. Call from on_init / on_configuration_changed so save/load and
-- mod updates leave the world in a clean state.
function M.reset()
  local s = State.get()
  s.active_pheromone = nil
  for player_index in pairs(s.joined_players) do
    strip_pheromone_items(game.get_player(player_index))
  end
end

-- ── Disgorge integration ───────────────────────────────────────────────────

-- Returns true the first time it's called for a given burst. Used by
-- creatures.lua to disgorge each hive's stored creatures exactly once when
-- a burst is created, instead of repeating every recruitment scan tick.
function M.consume_disgorge_flag(burst)
  if not burst then return false end
  if burst.disgorged then return false end
  burst.disgorged = true
  return true
end

-- ── Arrival scan + dispatch ────────────────────────────────────────────────

local function dispatch(s)
  local burst = s.active_pheromone
  if not burst then return end
  local surface = game.surfaces and game.surfaces[burst.surface_index]
  if not (surface and surface.valid) then s.active_pheromone = nil; return end

  local hive_force = Force.get_hive()
  if not hive_force then s.active_pheromone = nil; return end

  Telemetry.bump_op("find")
  local in_radius = surface.find_entities_filtered{
    position = burst.position,
    radius   = shared.pheromone_burst.arrival_radius,
    force    = hive_force,
    type     = "unit"
  }

  local group = surface.create_unit_group{
    position = burst.position,
    force    = hive_force
  }
  if group then
    if in_radius then
      for _, unit in pairs(in_radius) do
        if unit.valid and unit.name ~= shared.entities.hive_worker then
          group.add_member(unit)
        end
      end
    end
    group.start_moving()
    Telemetry.bump_op("dispatch")
  end

  s.active_pheromone = nil
end

function M.tick()
  local s = State.get()

  -- One-shot migration: saves made under earlier broken builds may have
  -- stranded hm-pheromones items in joined players' inventories. Runs
  -- exactly once after the fix loads (gated on a storage flag) so it
  -- doesn't re-scan every tick. Routed through Safe so a controller-
  -- specific inventory quirk can't bring the mod down.
  if not s.pheromone_v2_migrated then
    Safe.call("pheromone.v2_migration", function()
      for player_index in pairs(s.joined_players) do
        strip_pheromone_items(game.get_player(player_index))
      end
    end)
    s.pheromone_v2_migrated = true
  end

  local burst = s.active_pheromone
  if not burst then return end

  -- Hard timeout. Catches stale records (post-load with corrupt timer or a
  -- spot with no biters in attack range) so a burst can never trap
  -- recruitment indefinitely.
  local timeout = shared.pheromone_burst.timeout_ticks or (30 * 60)
  if (game.tick - (burst.started_tick or 0)) > timeout then
    s.active_pheromone = nil
    return
  end

  local surface = game.surfaces and game.surfaces[burst.surface_index]
  if not (surface and surface.valid) then s.active_pheromone = nil; return end

  local hive_force = Force.get_hive()
  if not hive_force then return end

  local found = surface.find_entities_filtered{
    position = burst.position,
    radius   = shared.pheromone_burst.arrival_radius,
    force    = hive_force,
    type     = "unit"
  }
  if found then
    burst.seen_units = burst.seen_units or {}
    for _, unit in pairs(found) do
      if unit.valid then
        local id = unit.unit_number
        if id and not burst.seen_units[id] and unit.name ~= shared.entities.hive_worker then
          burst.seen_units[id] = true
          burst.gather_count = (burst.gather_count or 0) + 1
        end
      end
    end
  end

  if (burst.gather_count or 0) >= (burst.target_size or 1) then
    dispatch(s)
  end
end

return M
