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

-- Cached deterministic list of network members.
--
-- Built once on first access after invalidation; reused thereafter on a flat
-- valid-filter pass. Members are sorted by entity.unit_number — but since
-- unit_numbers are issued monotonically and cache appends happen at build /
-- promote time, an "add" always lands at the tail of an already-sorted list.
-- Removals filter in place. So the list stays sorted without ever calling
-- `table.sort` after the first build.
--
-- Invalidation: Hive.invalidate_members_cache(), called from Hive.track,
-- Hive.untrack, Hive.track_node, Hive.untrack_node, Promote.swap_node_for_hive,
-- and the lifecycle hooks (on_init, on_configuration_changed). Invalidation
-- here is module-local to scan.lua; the Hive module exposes a hook so the
-- mutator (Hive.track etc.) doesn't have to know about scan.
local cached_members = nil

function M.invalidate_members_cache()
  cached_members = nil
end

-- Subscribe to hive-side topology changes (built, destroyed, node built,
-- node destroyed, promote) so the cache flushes on every event that could
-- change membership. Hive.on_topology_change runs registered functions
-- inside Hive.track/untrack/track_node/untrack_node, so by the time a
-- subsequent Scan.tick fires the cache is already cold.
Hive.on_topology_change(function() cached_members = nil end)

local function rebuild_members()
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

local function all_members()
  if cached_members then
    -- Filter in place. Most ticks every member is still valid and this is a
    -- straight copy.
    local fresh = {}
    for _, m in ipairs(cached_members) do
      if m and m.entity and m.entity.valid then fresh[#fresh + 1] = m end
    end
    cached_members = fresh
    return cached_members
  end
  cached_members = rebuild_members()
  return cached_members
end

-- Public read-only view of the cached members list. Used by the reconciler
-- watchdog to capture the cached state before forcing a rebuild for drift
-- detection. If the cache is cold this populates it; the reconciler
-- expects this and the populate-on-peek behaviour matches all_members().
function M.peek_members()
  return all_members()
end

function M.tick(tick)
  -- Sub-measure each phase so the perf log shows where Scan.tick time goes.
  -- recruit/absorb are still measured separately inside the loop — they're
  -- nested inside scan_ms but the dispatcher-only cost is
  --   scan - (scan.members + scan.setup + scan.loop_overhead) = noise
  -- and the three new buckets sum to roughly scan minus the inner work.
  local members = Telemetry.measure("scan.members", all_members)
  local N = #members
  if N == 0 then return end

  local T = shared.intervals.scan
  if T <= 0 then T = 1 end
  local per_tick = math.ceil(N / T)

  local s = State.get()
  s.scan_cursor = s.scan_cursor or 0

  local ctx = Telemetry.measure("scan.setup", Creatures.recruit_setup_tick)
  if not ctx then return end

  local absorb_paused = ctx.pheromone_burst ~= nil

  Telemetry.measure("scan.loop", function()
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
  end)

  s.scan_cursor = (s.scan_cursor + per_tick) % N

  -- Pheromone-vent arrival scan rides the same scan cadence and work-spread.
  Telemetry.measure("recruit", function() Vent.tick(tick) end)
end

return M
