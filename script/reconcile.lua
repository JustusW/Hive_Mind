-- Reconciler watchdog.
--
-- Slow rotating safety net for the event-driven caches. Each reconcile
-- tick (every `intervals.reconcile` ticks, default 600) picks ONE
-- registered probe and runs it. With N probes, each is verified every
-- N × intervals.reconcile ticks — slow enough to be irrelevant per-tick,
-- fast enough that cache drift surfaces in normal sessions.
--
-- A probe captures the cached value, forces a rebuild, compares, and
-- replaces the cache with the fresh value if drift is detected. Drift is
-- always logged through Telemetry as a `[reconcile]` line so a developer
-- knows which event was missed.
--
-- Probes are registered statically here; adding a new cache means adding
-- a probe. Order doesn't matter, but stable order means a given probe
-- runs at the same cursor index across sessions, which makes drift logs
-- easier to compare.
--
-- This module is the source of truth for cache *audits*, not for cache
-- contents. Invalidations remain event-driven (Hive.on_topology_change,
-- direct invalidate_cache calls, etc.). The reconciler exists to catch
-- bugs where an event was missed.

local shared    = require("shared")
local State     = require("script.state")
local Hive      = require("script.hive")
local Network   = require("script.network")
local Telemetry = require("script.telemetry")
local Force     = require("script.force")
local Scan      = require("script.scan")

local M = {}

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- Compare two entity lists by unit_number. Returns add (in after, not in
-- before) and drop (in before, not in after) counts. Used for caches whose
-- value is a flat list of entities (Hive.all, Hive.labs, Scan.members).
local function diff_by_unit_number(before, after, get_unit_number)
  get_unit_number = get_unit_number or function(e) return e.unit_number end

  local before_set = {}
  for _, e in ipairs(before) do
    local n = get_unit_number(e)
    if n then before_set[n] = true end
  end
  local after_set = {}
  for _, e in ipairs(after) do
    local n = get_unit_number(e)
    if n then after_set[n] = true end
  end
  local add, drop = 0, 0
  for n in pairs(after_set) do
    if not before_set[n] then add = add + 1 end
  end
  for n in pairs(before_set) do
    if not after_set[n] then drop = drop + 1 end
  end
  return add, drop
end

local function shallow_copy_list(list)
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  return copy
end

-- ── Probes ──────────────────────────────────────────────────────────────────
--
-- Each probe:
--   * captures the current cached value
--   * forces a rebuild via the cache module's invalidate hook
--   * triggers a fresh access (which re-populates from world scan)
--   * returns add, drop counts
-- Side effect (rebuild) IS the fix — after the probe runs, the cache is
-- guaranteed fresh.

local function probe_hive_all()
  local before = shallow_copy_list(Hive.all())
  Hive.invalidate_cache()
  local after = Hive.all()
  return diff_by_unit_number(before, after)
end

local function probe_hive_labs()
  local before = shallow_copy_list(Hive.labs())
  Hive.invalidate_labs_cache()
  local after = Hive.labs()
  return diff_by_unit_number(before, after)
end

local function probe_scan_members()
  -- Scan.members isn't a public list; the cached state lives in scan.lua's
  -- module local. Use the cache invalidator and a no-op tick to flush.
  -- Comparison is by entity.unit_number on the cached list before vs after.
  local before = shallow_copy_list(Scan.peek_members())
  Scan.invalidate_members_cache()
  local after = Scan.peek_members()
  return diff_by_unit_number(before, after, function(m) return m.entity and m.entity.unit_number end)
end

-- Verify ONE member's network cache per pass. Picks the next member in
-- round-robin via state.reconcile_member_cursor. Bounded cost per pass
-- regardless of network size; whole-cache verification takes
-- N × intervals.reconcile × len(probes) ticks.
local function probe_network_one_member()
  local members = Scan.peek_members()
  local n = #members
  if n == 0 then return 0, 0 end
  local s = State.get()
  s.reconcile_member_cursor = ((s.reconcile_member_cursor or 0) % n) + 1
  local m = members[s.reconcile_member_cursor]
  if not (m and m.entity and m.entity.valid) then return 0, 0 end
  local before = Network.cached_for_member(m.entity)
  Network.invalidate_member(m.entity)
  local after = Network.cached_for_member(m.entity)
  if not (before and after) then
    return (after and not before) and 1 or 0,
           (before and not after) and 1 or 0
  end
  -- Compare member sets of the cached resolved network.
  return diff_by_unit_number(before.members, after.members,
                             function(x) return x.entity and x.entity.unit_number end)
end

-- Storage invariant audit: every network has exactly one chest, owned by
-- the primary hive. Drift counts misplaced or missing chests.
local function probe_storage_invariant()
  local hive_force = Force.get_hive()
  if not hive_force then return 0, 0 end
  local visited = {}
  local drift_misplaced = 0  -- chest exists but on the wrong hive
  local drift_missing   = 0  -- network has no chest
  for _, hive in ipairs(Hive.all()) do
    if hive and hive.valid and not visited[hive.unit_number] then
      local network = Network.resolve_at(hive.surface, hive.position)
      if network and network.hives and #network.hives > 0 then
        for _, h in pairs(network.hives) do
          if h and h.unit_number then visited[h.unit_number] = true end
        end
        local primary = Network.primary_hive(hive)
        local primary_chest = primary and Hive.get_chest(primary)
        if not primary_chest then drift_missing = drift_missing + 1 end
        for _, h in pairs(network.hives) do
          if h and h.valid and h ~= primary and Hive.get_chest(h) then
            drift_misplaced = drift_misplaced + 1
          end
        end
      end
    end
  end
  -- Side-effect fix: only run consolidation if there's drift, since the
  -- pass is O(networks × find_storage). Even with drift, the per-network
  -- ensure_chest_at_primary is cheap.
  if drift_missing > 0 or drift_misplaced > 0 then
    local revisited = {}
    for _, hive in ipairs(Hive.all()) do
      if hive and hive.valid and not revisited[hive.unit_number] then
        local network = Network.resolve_at(hive.surface, hive.position)
        if network and network.hives and #network.hives > 0 then
          for _, h in pairs(network.hives) do
            if h and h.unit_number then revisited[h.unit_number] = true end
          end
          Network.ensure_chest_at_primary(hive)
        end
      end
    end
  end
  return drift_misplaced, drift_missing
end

-- ── Probe registry ──────────────────────────────────────────────────────────

local probes = {
  { name = "hive_all",           fn = probe_hive_all },
  { name = "hive_labs",          fn = probe_hive_labs },
  { name = "scan_members",       fn = probe_scan_members },
  { name = "network_member",     fn = probe_network_one_member },
  { name = "storage_invariant",  fn = probe_storage_invariant }
}

-- ── Tick entry point ─────────────────────────────────────────────────────────

function M.tick()
  if #probes == 0 then return end
  local s = State.get()
  s.reconcile_cursor = (s.reconcile_cursor or 0) % #probes
  local probe = probes[s.reconcile_cursor + 1]
  s.reconcile_cursor = s.reconcile_cursor + 1
  if not probe then return end
  local ok, add, drop = pcall(probe.fn)
  if not ok then
    -- Probe raised — telemetry-log the error and move on. A broken probe
    -- shouldn't take down the on_tick chain.
    Telemetry.log_reconcile(probe.name, -1, -1, tostring(add))
    return
  end
  if (add and add > 0) or (drop and drop > 0) then
    Telemetry.log_reconcile(probe.name, add or 0, drop or 0)
  end
end

return M
