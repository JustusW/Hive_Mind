-- Hive Mind Reloaded — runtime orchestrator.
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
local Debug     = require("script.debug")

-- ── Tick scheduler ───────────────────────────────────────────────────────────

local function on_tick(event)
  Director.restore_mined_entities()

  local tick = event.tick
  if tick % shared.intervals.recruit == 0 then Creatures.tick_recruitment() end
  if tick % shared.intervals.absorb  == 0 then Creatures.tick_absorption()  end
  if tick % shared.intervals.supply  == 0 then Lab.tick_supply()            end
  if tick % shared.intervals.robots  == 0 then Hive.tick_robots()           end
  if tick % shared.intervals.creep   == 0 then Creep.tick()                 end
  if tick % shared.intervals.labels  == 0 then Labels.tick()                end

  Debug.tick()
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

script.on_init(function()
  State.get()
  Force.configure(Force.get_hive())
  Force.get_permission_group()
  Director.update_all_hive_buttons()
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

  -- Re-create any hive storage chest the migration lost, and top up robots.
  for _, hive in pairs(Hive.all()) do
    local record = Hive.get_storage(hive)
    if record and not (record.chest and record.chest.valid) then
      Hive.create_chest(hive)
    end
    Hive.init(hive)
  end
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

-- ── Event routing ────────────────────────────────────────────────────────────

local e = defines.events

script.on_event(e.on_tick, on_tick)

-- Player lifecycle / GUI / mining lockdown
script.on_event(e.on_player_created,                Director.on_player_created)
script.on_event(e.on_player_respawned,              Director.on_player_respawned)
script.on_event(e.on_gui_click,                     Director.on_gui_click)
script.on_event(e.on_gui_opened,                    Director.on_gui_opened)
script.on_event(e.on_player_mined_entity,           Director.on_player_mined_entity)
script.on_event(e.on_player_mined_item,             Director.on_player_mined_item)
script.on_event(e.on_marked_for_deconstruction,     Director.on_marked_for_deconstruction)

-- Forbidden-inventory clearing (gun / ammo / armor are never allowed).
local function clear_forbidden(event, inventory_id)
  Director.clear_forbidden_inventory(game.get_player(event.player_index), inventory_id)
end
script.on_event(e.on_player_gun_inventory_changed,   function(ev) clear_forbidden(ev, defines.inventory.character_guns)  end)
script.on_event(e.on_player_ammo_inventory_changed,  function(ev) clear_forbidden(ev, defines.inventory.character_ammo)  end)
script.on_event(e.on_player_armor_inventory_changed, function(ev) clear_forbidden(ev, defines.inventory.character_armor) end)

-- Build pipeline.
script.on_event(e.on_built_entity,        Build.on_built)
script.on_event(e.script_raised_built,    Build.on_built)
script.on_event(e.on_robot_built_entity,  Build.on_robot_built)

-- Removal pipeline.
script.on_event(e.on_entity_died,         Death.on_removed)
script.on_event(e.on_robot_mined_entity,  Death.on_removed)
script.on_event(e.script_raised_destroy,  Death.on_removed)
