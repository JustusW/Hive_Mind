-- Hive Mind Reworked — runtime orchestrator.
--
-- This file does no work itself. It wires up:
--   * lifecycle hooks (on_init / on_configuration_changed)
--   * the shared on_tick scheduler
--   * the event → handler routing table
--   * the remote interface
--
-- All real logic lives in the focused modules under script/.

local shared    = require("shared")

local State     = require("script.state")
local Force     = require("script.force")
local Director  = require("script.director")
local Hive      = require("script.hive")
local Creatures = require("script.creatures")
local Build     = require("script.build")
local Death     = require("script.death")
local Creep     = require("script.creep")
local Lab       = require("script.lab")
local Labels    = require("script.labels")
local Workers   = require("script.workers")
local Supremacy = require("script.supremacy")
local Debug     = require("script.debug")
local Telemetry = require("script.telemetry")
local Scan      = require("script.scan")
local Pheromone = require("script.pheromone")
local Anchor    = require("script.anchor")
local Promote   = require("script.promote")

-- ── Tick scheduler ───────────────────────────────────────────────────────────

local function on_tick(event)
  Telemetry.measure("restore_mined", Director.restore_mined_entities)

  local tick = event.tick
  -- Unified per-member scan replaces the old intervals.recruit + intervals.absorb
  -- cadences; recruit and absorb fire from inside Scan.tick on a work-spread
  -- rotation. The wrapper time covers the dispatcher overhead — recruit_ms
  -- and absorb_ms inside it cover the bulk work separately.
  Telemetry.measure("scan", Scan.tick, tick)

  if tick % shared.intervals.supply    == 0 then Telemetry.measure("supply",    Lab.tick_supply)             end
  if tick % shared.intervals.workers   == 0 then Telemetry.measure("workers",   Workers.tick)                end
  if tick % shared.intervals.creep     == 0 then Telemetry.measure("creep",     Creep.tick)                  end
  if tick % shared.intervals.labels    == 0 then Telemetry.measure("labels",    Labels.tick)                 end
  if tick % shared.intervals.loadout   == 0 then Telemetry.measure("loadout",   Director.refill_all_loadouts) end
  if tick % shared.intervals.supremacy == 0 then Telemetry.measure("supremacy", Supremacy.tick)              end
  if tick % shared.intervals.scan      == 0 then Telemetry.measure("pheromone", Pheromone.tick)              end
  -- Anchor construction completion: 1 Hz check is plenty (the 30s window
  -- has 30 chances to land within ±1 tick of the deadline). Not on the
  -- scan cadence because Anchor.tick is independent of recruit timing.
  if tick % 60                         == 0 then Telemetry.measure("anchor",    Anchor.tick)                 end

  Telemetry.measure("debug", Debug.tick)

  -- Flush perf + recruit lines on the unified scan cadence.
  if tick % shared.intervals.scan == 0 then
    Telemetry.flush_recruit(tick)
    Telemetry.flush_perf(tick)
  end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

script.on_init(function()
  State.get()
  Force.configure(Force.get_hive())
  Force.get_permission_group()
  Director.update_all_hive_buttons()
  Pheromone.reset()
  Labels.cleanup_legacy_labels()
  Hive.invalidate_cache()
end)

script.on_configuration_changed(function()
  local s = State.get()
  Force.configure(Force.get_hive())
  Force.get_permission_group()
  Director.update_all_hive_buttons()

  -- Snap any joined player back to the god controller in case a config change
  -- knocked them off it.
  for player_index in pairs(s.joined_players) do
    local player = game.get_player(player_index)
    if player and player.valid and player.controller_type ~= defines.controllers.god then
      player.set_controller({type = defines.controllers.god})
    end
  end

  -- Re-create any hive storage chest the migration lost.
  for _, hive in pairs(Hive.all()) do
    local record = Hive.get_storage(hive)
    if record and not (record.chest and record.chest.valid) then
      Hive.create_chest(hive)
    end
  end

  -- Defensive cleanup for the pheromone-burst rework: clear any in-flight
  -- record (a stale started_tick from an earlier broken build would otherwise
  -- be picked up as still-active) and strip stranded hm-pheromones items
  -- left in joined players' inventories by the un-consumed-item bug.
  Pheromone.reset()

  -- Clean up the previous version's per-hive render-object labels. The
  -- pollution read-out is now a per-player GUI element (see labels.lua).
  Labels.cleanup_legacy_labels()
end)

-- ── Remote interface ─────────────────────────────────────────────────────────

remote.add_interface("hive_reboot",
{
  register_creature_role   = Creatures.register_role,
  unregister_creature_role = Creatures.unregister_role,
  join_hive = function(player_index)
    local player = game.get_player(player_index)
    if player then Director.join(player) end
  end
})

-- Custom command for flipping the runtime-global telemetry setting from
-- the in-game console. The Mod-settings GUI in multiplayer often greys out
-- runtime-global toggles for non-host clients — this command is a
-- guaranteed-working alternative usable by anyone with admin rights (in
-- single-player and the host always have admin).
--
-- Usage: /hm-telemetry on | off | status
commands.add_command(
  "hm-telemetry",
  "Toggle Hive Mind Reworked debug telemetry. Usage: /hm-telemetry on|off|status",
  function(event)
    -- No admin gate: this is a tuning knob, not a griefing vector. Anyone
    -- in the session can flip it. The previous admin check made the
    -- command useless in the typical dev setup (headless server has no
    -- admins, connecting dev client wasn't promoted).
    local player = event.player_index and game.get_player(event.player_index) or nil
    local function reply(msg)
      if player then player.print(msg) else print(msg) end
    end
    local arg = (event.parameter or ""):lower():gsub("%s+", "")
    local current = (settings.global["hm-debug-telemetry"] or {}).value == true
    if arg == "" or arg == "status" then
      reply("/hm-telemetry: telemetry is currently " .. (current and "ON" or "OFF") .. ".")
      return
    end
    local target
    if arg == "on" or arg == "true" or arg == "1" then
      target = true
    elseif arg == "off" or arg == "false" or arg == "0" then
      target = false
    else
      reply("/hm-telemetry: unknown argument '" .. arg .. "' (use on / off / status).")
      return
    end
    settings.global["hm-debug-telemetry"] = {value = target}
    reply("/hm-telemetry: telemetry " .. (target and "enabled" or "disabled") .. ".")
  end
)

-- ── Event routing ────────────────────────────────────────────────────────────

local e = defines.events

-- Tiny helper: wrap an event handler so its time accumulates under
-- `category` in the perf log. The handler is called with the original
-- event verbatim.
local function timed(category, handler)
  return function(ev) Telemetry.measure(category, handler, ev) end
end

script.on_event(e.on_tick, on_tick)

-- Player lifecycle / GUI / mining lockdown
script.on_event(e.on_player_created,      timed("on_player_created",   Director.on_player_created))
script.on_event(e.on_player_respawned,    timed("on_player_respawned", Director.on_player_respawned))
script.on_event(e.on_gui_click,           timed("on_gui_click",        Director.on_gui_click))
script.on_event(e.on_gui_opened,          timed("on_gui_opened",       Director.on_gui_opened))
script.on_event(e.on_player_mined_entity, timed("on_player_mined_entity", Director.on_player_mined_entity))
script.on_event(e.on_player_mined_item,   timed("on_player_mined_item",   Director.on_player_mined_item))
-- Deconstruction is blocked at the prototype level via the
-- "not-deconstructable" flag (data/prototypes/entities.lua → lock_decon).
-- No script handler needed.

-- Forbidden-inventory clearing (gun / ammo / armor are never allowed).
local function clear_forbidden(event, inventory_id)
  Director.clear_forbidden_inventory(game.get_player(event.player_index), inventory_id)
end
script.on_event(e.on_player_gun_inventory_changed,
  timed("on_gun_inv",   function(ev) clear_forbidden(ev, defines.inventory.character_guns)  end))
script.on_event(e.on_player_ammo_inventory_changed,
  timed("on_ammo_inv",  function(ev) clear_forbidden(ev, defines.inventory.character_ammo)  end))
script.on_event(e.on_player_armor_inventory_changed,
  timed("on_armor_inv", function(ev) clear_forbidden(ev, defines.inventory.character_armor) end))

-- on_player_crafted_item fan-out. Each handler filters by the recipe's
-- result item and ignores everything else.
local function on_crafted_dispatch(event)
  Pheromone.on_crafted(event)
  Promote.on_crafted(event)
end
script.on_event(e.on_player_crafted_item, timed("on_crafted", on_crafted_dispatch))

-- Build pipeline. Worker materialisations come back through script_raised_built
-- with player_index = nil; Build.on_built no-ops the cost branches in that
-- case. on_robot_built_entity is no longer hooked — there are no
-- construction-robots in the hive, ghosts are fulfilled by the Workers
-- dispatcher instead.
script.on_event(e.on_built_entity,     timed("on_built",           Build.on_built))
script.on_event(e.script_raised_built, timed("on_script_built",    Build.on_built))

-- Removal pipeline. Worker deaths route into Workers so the dispatcher can
-- requeue an in-flight job whose unit got killed.
local function on_removed(event)
  Workers.on_worker_died(event.entity)
  Death.on_removed(event)
end
script.on_event(e.on_entity_died,        timed("on_entity_died",      on_removed))
script.on_event(e.on_robot_mined_entity, timed("on_robot_mined",      on_removed))
script.on_event(e.script_raised_destroy, timed("on_script_destroy",   on_removed))
