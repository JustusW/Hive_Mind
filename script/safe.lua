-- Defensive API wrappers.
--
-- A handful of Factorio API calls have raised on past engine versions or
-- behave differently across controller types (entity.minable writes,
-- player.cursor_stack on the god controller, prototype.max_health on
-- certain entity types, surface.create_entity edge cases). Historically
-- each call site wrapped itself in a fresh `pcall(function() ... end)`,
-- which works but makes failures invisible — the call silently no-ops
-- and the bug never surfaces in a log.
--
-- This module centralises that pattern: every defensive call goes
-- through `safe.call(label, fn, ...)`, which runs `pcall(fn, ...)` and,
-- on failure, emits a `[safe]` telemetry line so the problem is visible
-- when telemetry is on.
--
-- Usage:
--   safe.call("anchor.minable_lock", function() entity.minable = false end)
--   local hp = safe.call("supremacy.max_health", function() return proto.max_health end)
--   safe.call("director.restore_mined", surface.create_entity, {name = ...})
--
-- The `label` is a stable string per call site. Keep it short and
-- specific so a `[safe]` line points at the offending wrapper without
-- having to grep the source.

local Telemetry = require("script.telemetry")

local M = {}

-- pcall(fn, ...). On success: returns whatever fn returned (single value;
-- multi-return is collapsed to first return for now). On failure: returns
-- nil and emits a [safe] telemetry line.
function M.call(label, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    Telemetry.log_safe(label, tostring(result))
    return nil
  end
  return result
end

return M
