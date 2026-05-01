-- Persistent storage shape for the mod.
--
--   joined_players       [player_index] = true
--   rejected_players     [player_index] = true   (permanently opted out)
--   worker_jobs          [ghost_unit_number]         = {ghost, worker, ...}
--   hives_by_player      [player_index][unit_number] = {entity}
--   hive_nodes           [unit_number]               = {entity, creep_layer, creep_step}
--   hive_storage         [unit_number]               = {entity, chest, creep_layer, creep_step}
--   hive_labs            [unit_number]               = {entity}
--   pollution_generators [unit_number]               = entity
--   hive_roles           [entity_name][role]         = true
--   scan_cursor          number (rotating index for the unified scan, 0.9.0)
--   reconcile_cursor     number (round-robin index over registered caches; reconciler watchdog)
--   supremacy_candidates [member_unit_number] = { last_scan_tick, entries[entity_unit_number] = {...} }
--   recruit_buckets      [network_key]        = { tokens, last_tick, spawner_count, spawner_count_tick }
--   pheromone_vents      [unit_number]        = { entity, placer_player_index, gather_count, seen_units, mode }
--   vent_cursor          number (rotating index for the per-tick vent arrival scan, 0.9.0)
--   active_pheromone     nil | { surface_index, position, target_size, gather_count, seen_units, started_tick }
--   pending_anchor_constructions [unit_number] = { entity, owner_player_index, deadline_tick }
--   telemetry_recruit    transient counters reset on scan flush
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
      hive_labs            = {},
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
  if not state.hive_labs             then state.hive_labs             = {} end
  if state.scan_cursor               == nil then state.scan_cursor      = 0  end
  if state.reconcile_cursor          == nil then state.reconcile_cursor = 0  end
  if not state.supremacy_candidates  then state.supremacy_candidates  = {} end
  if not state.recruit_buckets       then state.recruit_buckets       = {} end
  if not state.pheromone_vents       then state.pheromone_vents       = {} end
  if state.vent_cursor               == nil then state.vent_cursor    = 0  end
  if not state.pending_anchor_constructions then state.pending_anchor_constructions = {} end
  return state
end

return M
