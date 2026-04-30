-- Player pheromone burst.
--
-- A one-shot, building-less pheromone vent. Crafting `hm-pheromones-on`
-- locks a position at the player's location and turns it into a temporary
-- attractor: the network's incoming biter stream (recruited + disgorged) is
-- diverted there until N biters have arrived, at which point they form an
-- engine-routed attack group.
--
-- Singleton: only one instance is ever live. Re-crafting cancels the
-- previous gather (overwrites the singleton). Re-crafting after dispatch
-- (gather complete, group already started_moving) is unrelated to the
-- dispersed group — the dispatched group runs its course on its own.
--
-- State lives at `state.active_pheromone`:
--   { surface_index, position = {x,y}, target_size, gather_count,
--     seen_units = {}, started_tick }
-- or nil.
--
-- Wiring:
--   * Pheromone.on_crafted(event)  → triggered on on_player_crafted_item;
--                                    starts a new burst, consumes the item.
--   * Pheromone.tick()             → arrival scan + dispatch (cheap; one
--                                    find_entities at a fixed point).
--   * Pheromone.active(s)          → returns the live record or nil.
--   * Pheromone.position_for(s, surface) → returns {x,y} if a burst is live
--                                          on this surface, else nil.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Telemetry = require("script.telemetry")

local M = {}

-- ── Sizing ─────────────────────────────────────────────────────────────────

-- X = same as a default-mode Pheromone Vent's attack_group_size, scaled by
-- the Attack Group Size tech. Mode multiplier is fixed at 1.0 (default).
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

-- Returns the burst position table {x,y} if a burst is live on this surface,
-- else nil. Used by recruitment destination resolution.
function M.position_for(s, surface)
  s = s or State.get()
  local p = s.active_pheromone
  if not p then return nil end
  if not (surface and surface.valid) then return nil end
  if p.surface_index ~= surface.index then return nil end
  return p.position
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

local function consume_item(player)
  if not (player and player.valid) then return end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == shared.items.pheromones then
    local n = cursor.count
    if n <= 1 then cursor.clear() else cursor.count = n - 1 end
    return
  end
  local inv = player.get_main_inventory()
  if inv then inv.remove({name = shared.items.pheromones, count = 1}) end
end

local function start(s, surface_index, position)
  s.active_pheromone = {
    surface_index = surface_index,
    position      = {x = position.x, y = position.y},
    target_size   = target_size_now(),
    gather_count  = 0,
    seen_units    = {},
    started_tick  = game.tick
  }
end

-- on_player_crafted_item handler. We only act on `hm-pheromones`; other
-- crafts are ignored. Cancels any live instance and starts a fresh one at
-- the player's current position.
function M.on_crafted(event)
  if not event or not event.item_stack then return end
  if event.item_stack.name ~= shared.items.pheromones then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid and player.surface and player.surface.valid) then return end

  local s = State.get()
  -- Re-craft during gather phase: the new craft overwrites the previous
  -- singleton (effective cancellation). Re-craft during berserk phase: the
  -- previous instance is already dispatched and cleared from the singleton,
  -- so nothing to overwrite — the dispersed group runs to completion.
  start(s, player.surface.index, player.position)
  consume_item(player)
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
    radius   = shared.pheromone_vent.arrival_radius,
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
  local burst = s.active_pheromone
  if not burst then return end

  local surface = game.surfaces and game.surfaces[burst.surface_index]
  if not (surface and surface.valid) then s.active_pheromone = nil; return end

  local hive_force = Force.get_hive()
  if not hive_force then return end

  local found = surface.find_entities_filtered{
    position = burst.position,
    radius   = shared.pheromone_vent.arrival_radius,
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
