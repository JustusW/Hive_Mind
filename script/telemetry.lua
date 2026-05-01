-- Telemetry: appends [perf] and [recruit] lines to script-output/hm-debug.txt
-- so we can tune cadences and rates from logs rather than guessing.
--
-- Usage:
--   Telemetry.measure("recruit", fn, ...)   -- wraps the call, accumulates ms
--   Telemetry.bump_scanned(n)               -- counts hives/nodes processed
--   Telemetry.recruit{...}                  -- writes a [recruit] line
--   Telemetry.flush_perf(tick)              -- writes a [perf] line, resets accumulators
--
-- Both lines are gated on the existing Debug enable concept (today: always on
-- for the active dev profile). Wrap behind a startup setting before shipping.

local shared = require("shared")
local State  = require("script.state")

local M = {}

local timings = {}
local scanned = 0

-- Per-flush counters for the [recruit] line.
local recruit_counts = { group = 0, trickle = 0, skipped = 0 }

-- Per-flush operation counters for the [perf] line. Complement to ms timings,
-- which are zero-floored under ~15 ms on Windows os.clock granularity. Op
-- counts give us shape data even when ms is 0.
local op_counts = {
  find         = 0,  -- find_entities_filtered calls
  recruit      = 0,  -- units force-flipped this window
  absorb       = 0,  -- units absorbed (hive + node)
  damage       = 0,  -- supremacy damage applications
  dispatch     = 0,  -- pheromone-vent dispatches
}

-- Probe counters for the attack-group bypass. Tells us whether the
-- commandable.unit_group / commandable.group property ever resolves on the
-- current Factorio build.
local probe_counts = {
  ag_unit_group_hit = 0,  -- c.unit_group returned a valid group
  ag_group_hit      = 0,  -- c.unit_group failed/nil; c.group returned a valid group
  ag_miss           = 0,  -- neither resolved (most defenders)
  ag_pcall_err      = 0   -- both raised — engine doesn't expose either
}

-- Per-flush supremacy probes. Lets us see whether the cache is being filled,
-- whether damage calls actually run, and whether they kill anything. Helps
-- diagnose "nothing is taking damage" without extra logging.
local supremacy_counts = {
  cache_size      = 0,  -- total entries across all members at flush
  rebuild_calls   = 0,  -- how many candidate-scan rebuilds ran this window
  rebuild_added   = 0,  -- entities added to cache by rebuilds
  damage_calls    = 0,  -- entity.damage invocations
  damage_killed   = 0,  -- entries that became invalid post-damage
  on_creep_skip   = 0,  -- candidates skipped because tile wasn't creep
  no_unit_number  = 0   -- candidates skipped because entity.unit_number was nil
}

local function fmt_ms(seconds)
  return string.format("%.3f", (seconds or 0) * 1000)
end

local function arr_to_str(arr)
  if not arr or #arr == 0 then return "[]" end
  local parts = {}
  for i, v in ipairs(arr) do
    if type(v) == "number" and v % 1 ~= 0 then
      parts[i] = string.format("%.2f", v)
    else
      parts[i] = tostring(v)
    end
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

-- LuaProfiler in 2.0 has no `start`, only `reset` / `restart` / `stop` /
-- `add` / `divide`. To accumulate per-call elapsed time into a category
-- bucket we keep two profilers per measurement:
--   * `scratch` (single, shared) — restart()ed before each fn call, stopped
--     after, so its value holds JUST that call's duration.
--   * `profilers[category]` — a stopped accumulator created at value 0;
--     we `:add(scratch)` after each call so total elapsed time per
--     category accumulates over the flush window. flush_perf reads them
--     into a localised string and then `:reset()`s them.
local profilers = {}
local scratch_profiler  -- created lazily; one shared instance is enough.

local function ensure_scratch()
  if scratch_profiler then return scratch_profiler end
  if not (helpers and helpers.create_profiler) then return nil end
  scratch_profiler = helpers.create_profiler()  -- running by default; we
                                                -- `:restart()` per call
  return scratch_profiler
end

local function get_accumulator(category)
  local p = profilers[category]
  if p then return p end
  if not (helpers and helpers.create_profiler) then return nil end
  p = helpers.create_profiler(true)  -- stopped, value 0
  profilers[category] = p
  return p
end

-- Wrap a call so its wallclock cost is added to `category`. Falls through
-- transparently if helpers.create_profiler is unavailable for any reason.
function M.measure(category, fn, ...)
  if not fn then return end
  local scratch = ensure_scratch()
  if not scratch then return fn(...) end
  scratch:restart()           -- reset + start; value=0 and running
  local result = fn(...)
  scratch:stop()              -- pause; value = duration of fn
  local accum = get_accumulator(category)
  if accum then accum:add(scratch) end
  return result
end

-- Track how many hives/nodes the unified scan touched this perf-flush window.
function M.bump_scanned(n)
  scanned = scanned + (n or 1)
end

-- Bump a per-flush recruit counter. Categories: "group" / "trickle" / "skipped".
function M.bump_recruit(category)
  if recruit_counts[category] ~= nil then
    recruit_counts[category] = recruit_counts[category] + 1
  end
end

-- Bump an op-count.
function M.bump_op(category, n)
  if op_counts[category] ~= nil then
    op_counts[category] = op_counts[category] + (n or 1)
  end
end

-- Bump an attack-group probe counter.
function M.bump_probe(category)
  if probe_counts[category] ~= nil then
    probe_counts[category] = probe_counts[category] + 1
  end
end

-- Supremacy-specific probe counters. Use bump_supremacy for incremental
-- counters (rebuild_calls, damage_calls, …) and set_supremacy for snapshots
-- (cache_size).
function M.bump_supremacy(category, n)
  if supremacy_counts[category] ~= nil then
    supremacy_counts[category] = supremacy_counts[category] + (n or 1)
  end
end

function M.set_supremacy(category, n)
  if supremacy_counts[category] ~= nil then
    supremacy_counts[category] = n or 0
  end
end

-- Append a [recruit] telemetry line and reset the per-flush counters. Reads
-- the current bucket state directly from `state.recruit_buckets` so the line
-- always reflects ground truth at flush time.
function M.flush_recruit(tick)
  if not shared.feature_enabled("hm-debug-telemetry") then return end
  local s = State.get()
  local buckets = s.recruit_buckets or {}

  -- Stable order: sort by network key so successive lines line up across
  -- ticks even as networks form and dissolve.
  local keys = {}
  for k in pairs(buckets) do keys[#keys + 1] = k end
  table.sort(keys)

  local tokens, Rs, spawners = {}, {}, {}
  for _, k in ipairs(keys) do
    local b = buckets[k]
    tokens[#tokens + 1]   = b.tokens or 0
    spawners[#spawners + 1] = b.spawner_count or 0
    Rs[#Rs + 1] = (b.spawner_count or 0) * shared.recruit.per_spawner_per_second
  end

  local line = string.format(
    "[recruit] tick=%d networks=%d tokens=%s R=%s spawners=%s group=%d trickle=%d skipped=%d ag_ug=%d ag_g=%d ag_miss=%d ag_err=%d",
    tick,
    #keys,
    arr_to_str(tokens),
    arr_to_str(Rs),
    arr_to_str(spawners),
    recruit_counts.group   or 0,
    recruit_counts.trickle or 0,
    recruit_counts.skipped or 0,
    probe_counts.ag_unit_group_hit or 0,
    probe_counts.ag_group_hit      or 0,
    probe_counts.ag_miss           or 0,
    probe_counts.ag_pcall_err      or 0
  )
  helpers.write_file("hm-debug.txt", line .. "\n", true)

  recruit_counts.group   = 0
  recruit_counts.trickle = 0
  recruit_counts.skipped = 0
  probe_counts.ag_unit_group_hit = 0
  probe_counts.ag_group_hit      = 0
  probe_counts.ag_miss           = 0
  probe_counts.ag_pcall_err      = 0
end

-- Reset every profiler so the next flush window starts fresh.
local function reset_profilers()
  for _, p in pairs(profilers) do p:reset() end
end

-- Append a [perf] line for the cadence window and reset accumulators.
-- Uses a LocalisedString so LuaProfiler values render via their built-in
-- formatter (e.g. "145.872 ms" / "32.451 µs"). The unit varies and is
-- printed inline so analysis tools need to handle "value unit" pairs.
function M.flush_perf(tick)
  if not shared.feature_enabled("hm-debug-telemetry") then
    -- Still reset accumulators so disabled telemetry doesn't slowly leak
    -- counters that would suddenly dump in one big number if the user
    -- toggles the setting on mid-session.
    reset_profilers()
    scanned = 0
    for k in pairs(op_counts) do op_counts[k] = 0 end
    for k in pairs(supremacy_counts) do
      if k ~= "cache_size" then supremacy_counts[k] = 0 end
    end
    return
  end

  -- Stable "core" categories first, then any extras alphabetically.
  local core = {"recruit", "absorb", "supremacy", "workers", "creep",
                "labels", "loadout", "supply", "pheromone", "anchor",
                "scan", "debug", "restore_mined"}
  local seen = {}
  for _, k in ipairs(core) do seen[k] = true end
  local extras = {}
  for k in pairs(profilers) do
    if not seen[k] then extras[#extras + 1] = k end
  end
  table.sort(extras)

  -- Build a localised-string list. First element "" means concatenate the
  -- subsequent fragments. Strings are inserted as-is; LuaProfiler instances
  -- get rendered via their __tostring equivalent.
  local line = {""}
  table.insert(line, string.format("[perf] tick=%d scanned=%d", tick, scanned))
  local function emit(category)
    table.insert(line, " " .. category .. "_ms=")
    if profilers[category] then
      table.insert(line, profilers[category])
    else
      table.insert(line, "0")
    end
  end
  for _, k in ipairs(core)   do emit(k) end
  for _, k in ipairs(extras) do emit(k) end
  table.insert(line, string.format(
    " find=%d recruit=%d absorb=%d damage=%d dispatch=%d\n",
    op_counts.find     or 0,
    op_counts.recruit  or 0,
    op_counts.absorb   or 0,
    op_counts.damage   or 0,
    op_counts.dispatch or 0
  ))
  helpers.write_file("hm-debug.txt", line, true)

  -- Supremacy probe line — pure counters, no profilers, plain format.
  local sup = string.format(
    "[supremacy] tick=%d cache=%d rebuilds=%d added=%d damages=%d killed=%d off_creep=%d no_unit_number=%d",
    tick,
    supremacy_counts.cache_size     or 0,
    supremacy_counts.rebuild_calls  or 0,
    supremacy_counts.rebuild_added  or 0,
    supremacy_counts.damage_calls   or 0,
    supremacy_counts.damage_killed  or 0,
    supremacy_counts.on_creep_skip  or 0,
    supremacy_counts.no_unit_number or 0
  )
  helpers.write_file("hm-debug.txt", sup .. "\n", true)

  reset_profilers()
  scanned = 0
  op_counts.find     = 0
  op_counts.recruit  = 0
  op_counts.absorb   = 0
  op_counts.damage   = 0
  op_counts.dispatch = 0
  supremacy_counts.rebuild_calls   = 0
  supremacy_counts.rebuild_added   = 0
  supremacy_counts.damage_calls    = 0
  supremacy_counts.damage_killed   = 0
  supremacy_counts.on_creep_skip   = 0
  supremacy_counts.no_unit_number  = 0
  -- cache_size is a snapshot, set by Supremacy.tick on each pass; leave it.
end

return M
