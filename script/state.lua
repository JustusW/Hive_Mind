-- Persistent storage shape for the mod.
--
--   joined_players       [player_index] = true
--   rejected_players     [player_index] = true   (permanently opted out)
--   worker_jobs          [ghost_unit_number]         = {ghost, worker, ...}
--   hives_by_player      [player_index][unit_number] = {entity}
--   hive_nodes           [unit_number]               = {entity, creep_layer, creep_step}
--   hive_storage         [unit_number]               = {entity, chest, creep_layer, creep_step}
--   pollution_generators [unit_number]               = entity
--   hive_roles           [entity_name][role]         = true
--   scan_cursor          number (rotating index for the unified scan, 0.9.0)
--
-- All state lives under storage.hive_reboot. `storage` is the Factorio 2.0
-- name; `global` is kept as a fallback for older runtimes.

local M = {}

function M.get()
  local s = storage or global
  if not s.hive_reboot then
    s.hive_reboot =
    {
      joined_players       = {},
      rejected_players     = {},
      worker_jobs          = {},
      hives_by_player      = {},
      hive_nodes           = {},
      hive_storage         = {},
      pollution_generators = {},
      hive_roles           = {}
    }
  end
  local state = s.hive_reboot
  -- Backfill fields added in later versions.
  if not state.pollution_generators then state.pollution_generators = {} end
  if not state.hive_roles            then state.hive_roles            = {} end
  if not state.rejected_players      then state.rejected_players      = {} end
  if not state.worker_jobs           then state.worker_jobs           = {} end
  if not state.hives_by_player       then state.hives_by_player       = {} end
  if not state.hive_nodes            then state.hive_nodes            = {} end
  if not state.hive_storage          then state.hive_storage          = {} end
  if state.scan_cursor               == nil then state.scan_cursor    = 0  end
  return state
end

return M
