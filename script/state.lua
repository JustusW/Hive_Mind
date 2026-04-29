-- Persistent storage shape for the mod.
--
--   joined_players       [player_index] = true
--   rejected_players     [player_index] = true   (permanently opted out)
--   hives_by_player      [player_index][unit_number] = {entity}
--   hive_nodes           [unit_number]               = {entity}
--   hive_storage         [unit_number]               = {entity, chest}
--   pollution_generators [unit_number]               = entity
--   hive_roles           [entity_name][role]         = true
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
  return state
end

return M
