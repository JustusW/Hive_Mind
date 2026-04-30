-- Unified per-member scan with work-spread (0.9.0).
--
-- Replaces the old per-system cadences (`intervals.recruit = 120`,
-- `intervals.absorb = 30`) with a single `intervals.scan = 60`-tick cadence
-- that processes a fraction of network members each tick. Each member's
-- effective cadence is still 60 ticks; per-tick scan count is constant
-- relative to network size — no moloch supertick.
--
-- A "member" is a hive or hive node on the hive force. Members are sorted
-- deterministically by `unit_number` so the rotating cursor is stable across
-- save / load.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Hive      = require("script.hive")
local Creatures = require("script.creatures")
local Telemetry = require("script.telemetry")
local Vent      = require("script.vent")
local Anchor    = require("script.anchor")

local M = {}

-- Build the deterministic list of network members for this tick.
local function all_members()
  local s = State.get()
  local list = {}

  for _, hive in pairs(Hive.all()) do
    if hive and hive.valid then
      list[#list + 1] = { entity = hive, kind = "hive" }
    end
  end
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data and node_data.entity
    if node and node.valid then
      list[#list + 1] = { entity = node, kind = "hive_node" }
    end
  end

  table.sort(list, function(a, b)
    return a.entity.unit_number < b.entity.unit_number
  end)
  return list
end

function M.tick(tick)
  local members = all_members()
  local N = #members
  if N == 0 then return end

  local T = shared.intervals.scan
  if T <= 0 then T = 1 end
  local per_tick = math.ceil(N / T)

  local s = State.get()
  s.scan_cursor = s.scan_cursor or 0

  -- Set up shared recruitment context once per tick — pheromone resolution,
  -- force fetching, and Hive.all() are a fixed cost regardless of how many
  -- members we process.
  local ctx = Creatures.recruit_setup_tick()
  if not ctx then return end

  -- Pause absorption while a player pheromone burst is live (was the old
  -- ctx.pheromone_player rule; ctx.pheromone_burst is the new singleton).
  local absorb_paused = ctx.pheromone_burst ~= nil

  -- Anchor 30s construction: skip recruit + absorb for any hive whose
  -- storage record still has a building_until_tick in the future. The hive
  -- is inert during construction.
  for i = 0, per_tick - 1 do
    local idx = (s.scan_cursor + i) % N + 1
    local m = members[idx]
    if m and m.entity and m.entity.valid then
      local skip_for_construction = false
      if m.kind == "hive" then
        local record = Hive.get_storage(m.entity)
        if Anchor.is_building(record) then skip_for_construction = true end
      end

      if not skip_for_construction then
        Telemetry.bump_scanned(1)
        Telemetry.measure("recruit", function()
          Creatures.recruit_at_member(m.entity, m.kind, ctx)
        end)
        if not absorb_paused then
          if m.kind == "hive" then
            Telemetry.measure("absorb", function()
              Creatures.absorb_at_hive(m.entity)
            end)
          elseif m.kind == "hive_node" then
            Telemetry.measure("absorb", function()
              Creatures.absorb_at_node(m.entity, ctx)
            end)
          end
        end
      end
    end
  end

  s.scan_cursor = (s.scan_cursor + per_tick) % N

  -- Pheromone-vent arrival scan rides the same scan cadence and work-spread.
  Telemetry.measure("recruit", function() Vent.tick(tick) end)
end

return M
