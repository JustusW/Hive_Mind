-- Debug pollution vent.
--
-- A reskinned chest that emits world pollution every tick. Used during
-- development to flood the map with pollution and force vanilla biters to
-- spawn for testing recruitment / absorption / cost.
--
-- Should be gated behind a startup setting before shipping.

local shared = require("shared")
local State  = require("script.state")

local M = {}

function M.tick()
  local s = State.get()
  local amount = shared.pollution_generator_per_tick
  for id, entity in pairs(s.pollution_generators) do
    if entity and entity.valid then
      entity.surface.pollute(entity.position, amount)
    else
      s.pollution_generators[id] = nil
    end
  end
end

return M
