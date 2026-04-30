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

local M = {}

local timings = {}
local scanned = 0

-- Per-flush counters for the [recruit] line.
local recruit_counts = { group = 0, trickle = 0, skipped = 0 }

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

-- Wrap a call so its wallclock cost is added to `category`.
function M.measure(category, fn, ...)
  if not fn then return end
  local t0 = os and os.clock and os.clock() or 0
  local result = fn(...)
  if os and os.clock then
    local dt = os.clock() - t0
    timings[category] = (timings[category] or 0) + dt
  end
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

-- Append a [recruit] telemetry line and reset the per-flush counters. Reads
-- the current bucket state directly from `state.recruit_buckets` so the line
-- always reflects ground truth at flush time.
function M.flush_recruit(tick)
  local State = require("script.state")
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
    Rs[#Rs + 1] = (b.spawner_count or 0) * (require("shared").recruit.per_spawner_per_second)
  end

  local line = string.format(
    "[recruit] tick=%d networks=%d tokens=%s R=%s spawners=%s group=%d trickle=%d skipped=%d",
    tick,
    #keys,
    arr_to_str(tokens),
    arr_to_str(Rs),
    arr_to_str(spawners),
    recruit_counts.group   or 0,
    recruit_counts.trickle or 0,
    recruit_counts.skipped or 0
  )
  helpers.write_file("hm-debug.txt", line .. "\n", true)

  recruit_counts.group   = 0
  recruit_counts.trickle = 0
  recruit_counts.skipped = 0
end

-- Append a [perf] line for the cadence window and reset accumulators.
function M.flush_perf(tick)
  local total = 0
  for _, v in pairs(timings) do total = total + v end

  -- Stable column order so the line is greppable.
  local cols = {"recruit", "absorb", "supremacy", "workers", "creep"}
  local parts = {}
  for _, k in ipairs(cols) do
    parts[#parts + 1] = k .. "_ms=" .. fmt_ms(timings[k])
  end

  local line = string.format(
    "[perf] tick=%d scanned=%d %s total_ms=%s",
    tick,
    scanned,
    table.concat(parts, " "),
    fmt_ms(total)
  )
  helpers.write_file("hm-debug.txt", line .. "\n", true)

  timings = {}
  scanned = 0
end

return M
