-- Pheromone Vent (0.9.0).
--
-- A vent is a destination in the recruitment system, not a recruiter. It has
-- no recruitment range of its own. When a vent exists on the network and
-- isn't yet at threshold, it diverts the network's incoming biter stream to
-- itself — same way a pheromone player would, but anchored to the vent.
--
-- Each vent is owned by the player who placed it. Network membership is
-- resolved dynamically from the placer's current hive: hiveless placement
-- destroys the vent on the spot; placer-hive-loss orphans the vent (handled
-- by the network-collapse pass).
--
-- Default mode only in v1; mode markers are TODO.
--
-- Lifecycle:
--   Vent.on_built(entity, player_index)  → register or kill on hiveless
--   Vent.on_destroyed(entity)            → clear state + cleanup
--   Vent.tick(tick)                      → arrival scan + dispatch (work-spread)

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Hive      = require("script.hive")
local Network   = require("script.network")

local M = {}

-- ── Network resolution ──────────────────────────────────────────────────────

-- Resolve the placer's current hive (if any). Returns nil if the placer is
-- gone or has no hive. Used both at placement time and at recruitment-
-- destination time.
local function placer_hive(player_index)
  if not player_index then return nil end
  local s = State.get()
  local bucket = s.hives_by_player[player_index]
  if not bucket then return nil end
  for _, hive_data in pairs(bucket) do
    if hive_data.entity and hive_data.entity.valid then
      return hive_data.entity
    end
  end
  return nil
end

function M.placer_hive(player_index)
  return placer_hive(player_index)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function M.on_built(entity, player_index)
  if not (entity and entity.valid) then return end
  if entity.name ~= shared.entities.pheromone_vent then return end

  if not player_index then
    -- Script-driven creation (worker materialisation): just register, no
    -- hiveless check (a worker cannot build a vent for a player who has no
    -- hive — there'd be no worker).
    local s = State.get()
    s.pheromone_vents[entity.unit_number] = {
      entity              = entity,
      placer_player_index = nil,
      gather_count        = 0,
      seen_units          = {},
      mode                = "default"
    }
    return
  end

  local hive = placer_hive(player_index)
  if not hive then
    local player = game.get_player(player_index)
    if player and player.valid then
      player.print({"message.hm-pheromone-vent-no-hive"})
    end
    entity.destroy({raise_destroy = false})
    return
  end

  local s = State.get()
  s.pheromone_vents[entity.unit_number] = {
    entity              = entity,
    placer_player_index = player_index,
    gather_count        = 0,
    seen_units          = {},
    mode                = "default"
  }
end

function M.on_destroyed(entity)
  if not (entity and entity.valid) then return end
  if entity.name ~= shared.entities.pheromone_vent then return end
  local s = State.get()
  s.pheromone_vents[entity.unit_number] = nil
end

-- ── Sizing ──────────────────────────────────────────────────────────────────

local function tech_adjusted_base()
  local force = Force.get_hive()
  local base  = shared.pheromone_vent.base_size
  if not force then return base end
  local tech = force.technologies[shared.technologies.attack_group_size]
  if not tech then return base end
  local levels = tech.level - 1
  if levels < 0 then levels = 0 end
  return base + shared.pheromone_vent.tech_increment * levels
end

local function attack_group_size_for(record)
  local mode_factor = shared.pheromone_vent.mode_factor[record.mode or "default"] or 1.0
  return math.max(1, math.floor(tech_adjusted_base() * mode_factor + 0.5))
end

M.attack_group_size_for = attack_group_size_for

-- ── Destination resolution ─────────────────────────────────────────────────

-- Closest non-full vent on `network` to `unit`. Returns the vent entity
-- or nil. `network` is a Network.resolve_at result (or nil).
function M.closest_non_full_for_unit(unit, network)
  if not (unit and unit.valid and network and network.key) then return nil end
  local s = State.get()
  local best, best_d
  for _, record in pairs(s.pheromone_vents) do
    local entity = record.entity
    if entity and entity.valid then
      -- Only consider vents whose placer's hive resolves into THIS network.
      local hive = placer_hive(record.placer_player_index)
      if hive and hive.valid and hive.surface == unit.surface then
        local placer_net = Network.resolve_at(hive.surface, hive.position)
        if placer_net and placer_net.key == network.key then
          local size = attack_group_size_for(record)
          if (record.gather_count or 0) < size then
            local dx = entity.position.x - unit.position.x
            local dy = entity.position.y - unit.position.y
            local d2 = dx * dx + dy * dy
            if not best_d or d2 < best_d then
              best_d = d2
              best   = entity
            end
          end
        end
      end
    end
  end
  return best
end

-- ── Arrival scan + dispatch (work-spread) ───────────────────────────────────

local function dispatch(record)
  local entity = record.entity
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  local hive_force = Force.get_hive()
  if not hive_force then return end

  local in_radius = surface.find_entities_filtered{
    position = entity.position,
    radius   = shared.pheromone_vent.arrival_radius,
    force    = hive_force,
    type     = "unit"
  }
  if not in_radius or #in_radius == 0 then
    record.gather_count = 0
    record.seen_units   = {}
    return
  end

  local group = surface.create_unit_group{
    position = entity.position,
    force    = hive_force
  }
  if not group then return end

  for _, unit in pairs(in_radius) do
    if unit.valid and unit.name ~= shared.entities.hive_worker then
      group.add_member(unit)
    end
  end
  group.start_moving()

  record.gather_count = 0
  record.seen_units   = {}
end

local function scan_one_vent(record)
  local entity = record.entity
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  local hive_force = Force.get_hive()
  if not hive_force then return end

  local found = surface.find_entities_filtered{
    position = entity.position,
    radius   = shared.pheromone_vent.arrival_radius,
    force    = hive_force,
    type     = "unit"
  }
  if not found then return end

  record.seen_units = record.seen_units or {}
  for _, unit in pairs(found) do
    if unit.valid then
      local id = unit.unit_number
      if id and not record.seen_units[id] and unit.name ~= shared.entities.hive_worker then
        record.seen_units[id] = true
        record.gather_count = (record.gather_count or 0) + 1
      end
    end
  end

  local size = attack_group_size_for(record)
  if (record.gather_count or 0) >= size then
    dispatch(record)
  end
end

function M.tick(tick)
  local s = State.get()
  -- Clear stale records (entity died externally).
  for unit_number, record in pairs(s.pheromone_vents) do
    if not (record.entity and record.entity.valid) then
      s.pheromone_vents[unit_number] = nil
    end
  end

  -- Build the deterministic list of vents.
  local vents = {}
  for _, record in pairs(s.pheromone_vents) do
    vents[#vents + 1] = record
  end
  if #vents == 0 then return end
  table.sort(vents, function(a, b)
    return (a.entity.unit_number or 0) < (b.entity.unit_number or 0)
  end)

  local V = #vents
  local T = shared.intervals.scan
  if T <= 0 then T = 1 end
  local per_tick = math.ceil(V / T)

  s.vent_cursor = s.vent_cursor or 0
  for i = 0, per_tick - 1 do
    local idx = (s.vent_cursor + i) % V + 1
    local record = vents[idx]
    if record then scan_one_vent(record) end
  end
  s.vent_cursor = (s.vent_cursor + per_tick) % V
end

return M
