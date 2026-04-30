-- Hive worker dispatcher.
--
-- Replaces the old roboport + construction-robot pipeline. Workers are real
-- units (small-biter clones) commanded by this module. Each pending ghost
-- gets one worker assigned at the closest in-network hive; the worker walks
-- to the ghost, materialises it via surface.create_entity{raise_built=true}
-- (so existing on-built handlers still run for tracking / proxy swap), and
-- dies with a small-biter corpse.
--
-- Job state lives on `state.worker_jobs[ghost_unit_number]`:
--   {
--     ghost         = LuaEntity (entity-ghost),
--     player_index  = uint? — who placed the ghost (informational),
--     worker        = LuaEntity? — assigned unit or nil,
--     deadline      = uint? — game.tick at which we abandon this worker,
--     attempts      = uint  — how many workers we've burned so far,
--   }

local shared  = require("shared")
local State   = require("script.state")
local Force   = require("script.force")
local Hive    = require("script.hive")

local M = {}

local function jobs()
  return State.get().worker_jobs
end

local function dist2(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

-- Pick the nearest hive on `ghost`'s surface that still has worker capacity
-- (number of in-flight workers attached to this hive < the per-hive cap).
local function pick_hive(ghost, hives, in_flight_per_hive)
  local cap = shared.hive_workers_per_hive
  local best, best_d
  for _, hive in pairs(hives) do
    if hive.valid and hive.surface == ghost.surface then
      local count = in_flight_per_hive[hive.unit_number] or 0
      if count < cap then
        local d = dist2(hive.position, ghost.position)
        if not best_d or d < best_d then
          best_d = d
          best   = hive
        end
      end
    end
  end
  return best
end

local function spawn_worker_at(hive, ghost)
  local surface = hive.surface
  local pos = surface.find_non_colliding_position(
    shared.entities.hive_worker, hive.position, 6, 0.25)
  if not pos then pos = hive.position end
  local worker = surface.create_entity{
    name        = shared.entities.hive_worker,
    position    = pos,
    force       = Force.get_hive(),
    raise_built = false
  }
  if not (worker and worker.valid) then return nil end
  local commandable = worker.commandable
  if commandable then
    commandable.set_command{
      type        = defines.command.go_to_location,
      destination = ghost.position,
      distraction = defines.distraction.none,
      radius      = shared.workers_arrival_radius
    }
  end
  return worker
end

local function dispose_worker(worker)
  if not (worker and worker.valid) then return end
  Hive.spawn_worker_corpse(worker)
  worker.destroy()
end

-- Materialise the ghost's eventual entity at the ghost's position. We use
-- raise_built so the existing on-built handlers run (track_node, proxy →
-- real swap, etc) — those handlers no-op the cost path when player_index
-- is nil, which it is for script-driven creation.
local function materialise(ghost)
  if not (ghost and ghost.valid) then return end
  local name    = ghost.ghost_name
  local pos     = ghost.position
  local force   = ghost.force
  local surface = ghost.surface
  ghost.destroy()
  if not (name and prototypes.entity[name]) then return end
  surface.create_entity{
    name        = name,
    position    = pos,
    force       = force,
    raise_built = true
  }
end

-- Public: enqueue a ghost for worker fulfilment. Caller is responsible for
-- having charged the cost; the dispatcher just routes a worker.
function M.queue(ghost, player_index)
  if not (ghost and ghost.valid and ghost.unit_number) then return end
  local q = jobs()
  if q[ghost.unit_number] then return end
  q[ghost.unit_number] = {
    ghost        = ghost,
    player_index = player_index,
    worker       = nil,
    deadline     = nil,
    attempts     = 0
  }
end

-- Public: count outstanding workers per hive (used by tick to enforce caps).
local function in_flight_counts(q)
  local counts = {}
  for _, job in pairs(q) do
    if job.worker and job.worker.valid and job._hive_id then
      counts[job._hive_id] = (counts[job._hive_id] or 0) + 1
    end
  end
  return counts
end

function M.tick()
  local q     = jobs()
  if not next(q) then return end
  local now   = game.tick
  local hives = Hive.all()
  local counts = in_flight_counts(q)

  for ghost_id, job in pairs(q) do
    -- Ghost gone (e.g., engine canceled it) — drop the job, cancel worker.
    if not (job.ghost and job.ghost.valid) then
      if job.worker and job.worker.valid then dispose_worker(job.worker) end
      q[ghost_id] = nil
    elseif job.worker and job.worker.valid then
      -- In-flight: arrival or timeout.
      local r = shared.workers_arrival_radius
      if dist2(job.worker.position, job.ghost.position) <= r * r then
        materialise(job.ghost)
        dispose_worker(job.worker)
        q[ghost_id] = nil
      elseif job.deadline and now > job.deadline then
        dispose_worker(job.worker)
        if job._hive_id then
          counts[job._hive_id] = (counts[job._hive_id] or 1) - 1
        end
        job.worker   = nil
        job.deadline = nil
        job._hive_id = nil
        job.attempts = (job.attempts or 0) + 1
        if job.attempts >= shared.workers_max_attempts then
          if job.ghost and job.ghost.valid then job.ghost.destroy() end
          q[ghost_id] = nil
        end
      end
    else
      -- Unassigned: try to dispatch a worker from the closest in-range hive.
      local hive = pick_hive(job.ghost, hives, counts)
      if hive then
        local worker = spawn_worker_at(hive, job.ghost)
        if worker then
          job.worker   = worker
          job.deadline = now + shared.workers_timeout_ticks
          job._hive_id = hive.unit_number
          counts[hive.unit_number] = (counts[hive.unit_number] or 0) + 1
        end
      end
    end
  end
end

-- A worker died externally (combat, hive destroyed, etc). Clear it from any
-- job so the next tick re-dispatches from a fresh hive.
function M.on_worker_died(entity)
  if not (entity and entity.valid) then return end
  if entity.name ~= shared.entities.hive_worker then return end
  for _, job in pairs(jobs()) do
    if job.worker == entity then
      job.worker   = nil
      job.deadline = nil
      job._hive_id = nil
      break
    end
  end
end

return M
