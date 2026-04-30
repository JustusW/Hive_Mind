-- Player ↔ hive director state.
--
-- A "hive player" is a player that has joined the hive. They are switched to
-- the god controller, assigned to the hivemind force, and locked into a
-- permission group that blocks mining, dropping, and inventory transfers.
--
-- This module also owns the join button GUI and the mining/decon interception
-- handlers that keep the director from manipulating the world by hand.

local shared    = require("shared")
local State     = require("script.state")
local Force     = require("script.force")
local Hive      = require("script.hive")
local Creatures = require("script.creatures")

local M = {}

-- ── Player state ─────────────────────────────────────────────────────────────

function M.is_player(player)
  if not (player and player.valid) then return false end
  return State.get().joined_players[player.index] == true
end

function M.is_rejected(player)
  if not (player and player.valid) then return false end
  return State.get().rejected_players[player.index] == true
end

-- ── Hive buttons ─────────────────────────────────────────────────────────────
--
-- Two sibling buttons — "Join the Hive" and "Reject the Hive" — live inside
-- a private horizontal flow under `player.gui.top`. We avoid mod-gui's shared
-- frame so that once the player commits either way and we tear the buttons
-- down, the entire container goes with them and no empty bordered box is
-- left behind. Rejection is persisted in `rejected_players` and survives
-- save/load.

local FLOW_NAME = "hm-button-flow"

local function get_flow(player, create)
  local existing = player.gui.top[FLOW_NAME]
  if existing then return existing end
  if not create then return nil end
  return player.gui.top.add{
    type      = "flow",
    name      = FLOW_NAME,
    direction = "horizontal"
  }
end

-- Recursively destroy any element whose name matches one of the hive
-- buttons. Used to evict leftover buttons that older versions parked in
-- mod_gui's shared frame, so a config-change cleanup doesn't double-show.
local function purge_legacy_buttons(element)
  if not (element and element.valid) then return end
  if element.name == shared.gui.join_button
     or element.name == shared.gui.reject_button then
    element.destroy()
    return
  end
  if element.children then
    for _, child in pairs(element.children) do purge_legacy_buttons(child) end
  end
end

function M.update_hive_buttons(player)
  if not (player and player.valid) then return end
  -- Remove any stray buttons sitting outside our owned flow (e.g. ones
  -- placed by an older version of this mod into mod_gui's frame).
  for _, root_name in pairs({"top", "left", "screen"}) do
    local root = player.gui[root_name]
    if root and root.valid then
      for _, child in pairs(root.children) do
        if child.name ~= FLOW_NAME then purge_legacy_buttons(child) end
      end
    end
  end
  if M.is_player(player) or M.is_rejected(player) then
    local existing = get_flow(player, false)
    if existing then existing.destroy() end
    return
  end
  local flow = get_flow(player, true)
  if not flow[shared.gui.join_button] then
    flow.add{
      type    = "button",
      name    = shared.gui.join_button,
      caption = {"gui.hm-join-hive"}
    }
  end
  if not flow[shared.gui.reject_button] then
    flow.add{
      type    = "button",
      name    = shared.gui.reject_button,
      caption = {"gui.hm-reject-hive"}
    }
  end
end

function M.update_all_hive_buttons()
  for _, player in pairs(game.players) do M.update_hive_buttons(player) end
end

-- ── Director state ───────────────────────────────────────────────────────────

-- Move `player` onto the hive force as a god-controller and clear their
-- inventory + cursor. Idempotent.
function M.apply(player)
  local force = Force.get_hive()
  Force.configure(force)
  player.force = force
  player.permission_group = Force.get_permission_group()
  if player.controller_type ~= defines.controllers.god then
    player.set_controller({type = defines.controllers.god})
  end
  local inv = player.get_main_inventory()
  if inv then inv.clear() end
  player.clear_cursor()
end

-- ── Director loadout ────────────────────────────────────────────────────────
--
-- The director can never carry vanilla items: the only way they interact with
-- the world is by placing hive structures. We keep one of every currently-
-- buildable item in their inventory at all times and pin the same items to
-- the quickbar in a stable order so the player can pick them with hotkeys
-- without having to rummage through the inventory window.
--
-- "Currently buildable" means the gating recipe is enabled on the hive force.
-- A new building unlocked by research therefore appears in the loadout on
-- the next watchdog tick (or immediately on join / respawn).

local buildable_items =
{
  {item = shared.items.hive,                 recipe = shared.recipes.hive},
  {item = shared.items.hive_node,            recipe = shared.recipes.hive_node},
  {item = shared.items.hive_lab,             recipe = shared.recipes.hive_lab},
  {item = shared.items.hive_spawner,         recipe = shared.recipes.hive_spawner},
  {item = shared.items.hive_spitter_spawner, recipe = shared.recipes.hive_spitter_spawner},
  {item = shared.items.pollution_generator,  recipe = shared.recipes.pollution_generator}
}
for _, tier in pairs(shared.worm_tiers) do
  buildable_items[#buildable_items + 1] =
    {item = shared.worm[tier].item, recipe = shared.worm[tier].recipe}
end

-- Count how many of `item_name` the player is currently holding in either
-- their main inventory or the cursor. Auto-refund-on-place puts the item
-- into the cursor, so checking only the main inventory makes the watchdog
-- think the player has none and re-issue another copy on every tick.
local function holding_count(player, item_name)
  local count = 0
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == item_name then
    count = count + cursor.count
  end
  local inv = player.get_main_inventory()
  if inv then count = count + inv.get_item_count(item_name) end
  return count
end

local function refill_loadout(player)
  if not (player and player.valid and M.is_player(player)) then return end
  local inv = player.get_main_inventory()
  if not inv then return end
  local force = player.force

  local quickbar = {}
  for _, entry in ipairs(buildable_items) do
    local recipe = force.recipes[entry.recipe]
    if recipe and recipe.enabled then
      if holding_count(player, entry.item) < 1 then
        inv.insert{name = entry.item, count = 1}
      end
      quickbar[#quickbar + 1] = entry.item
    end
  end

  for slot, item_name in ipairs(quickbar) do
    local current = player.get_quick_bar_slot(slot)
    if not (current and current.name == item_name) then
      player.set_quick_bar_slot(slot, item_name)
    end
  end
end

function M.refill_all_loadouts()
  for _, player in pairs(game.players) do refill_loadout(player) end
end

-- Mark `player` as joined and apply the director state. No-op if already joined.
function M.join(player)
  if M.is_player(player) then return end
  State.get().joined_players[player.index] = true
  M.apply(player)
  refill_loadout(player)
  M.update_hive_buttons(player)
  player.print({"gui.hm-hive-joined"})
end

-- Mark `player` as having permanently refused the hive. Idempotent. Hides the
-- buttons and prints the obituary line. The player keeps their normal body
-- and force; the only effect is that the GUI never offers them the hive again.
function M.reject(player)
  if not (player and player.valid) then return end
  if M.is_player(player) or M.is_rejected(player) then return end
  State.get().rejected_players[player.index] = true
  M.update_hive_buttons(player)
  player.print({"gui.hm-hive-rejected"})
end

-- ── Inventory lockdown ───────────────────────────────────────────────────────

-- Clear `inventory_id` on a hive player. Used as the gun/ammo/armor inventory
-- handler — directors can never have any of that gear.
function M.clear_forbidden_inventory(player, inventory_id)
  if not M.is_player(player) then return end
  local inv = player.get_inventory(inventory_id)
  if inv then inv.clear() end
end

-- ── Mining lockdown ──────────────────────────────────────────────────────────
--
-- The permission group blocks mining at the input layer, but a few engine
-- paths can still slip through (script-driven mining, etc.). When a hive
-- player does mine an entity, queue it for re-creation on the next tick
-- and clear the produced item from their inventory.

local queued_restorations = {}

function M.on_player_mined_entity(event)
  local player = game.get_player(event.player_index)
  if not M.is_player(player) then return end
  if event.buffer then event.buffer.clear() end
  local entity = event.entity
  if entity and entity.valid then
    queued_restorations[#queued_restorations + 1] =
    {
      name          = entity.name,
      position      = {x = entity.position.x, y = entity.position.y},
      direction     = entity.direction,
      surface_index = entity.surface.index,
      force_name    = entity.force and entity.force.name
    }
  end
  player.print({"message.hm-no-mining"})
end

function M.on_player_mined_item(event)
  local player = game.get_player(event.player_index)
  if not M.is_player(player) then return end
  local inv = player.get_main_inventory()
  if inv and event.item_stack then
    inv.remove{name = event.item_stack.name, count = event.item_stack.count}
  end
end

-- Drain the restoration queue. Called from on_tick.
function M.restore_mined_entities()
  if #queued_restorations == 0 then return end
  local pending = queued_restorations
  queued_restorations = {}
  for _, r in pairs(pending) do
    local surface = game.surfaces[r.surface_index]
    if surface then
      pcall(function()
        surface.create_entity{
          name      = r.name,
          position  = r.position,
          direction = r.direction,
          force     = r.force_name
        }
      end)
    end
  end
end

-- ── Deconstruction lockdown ──────────────────────────────────────────────────

-- The hive does not deconstruct. Cancel any deconstruction order keyed to
-- the hive force regardless of how it got there: a hive player pressing the
-- decon shortcut, or the engine auto-marking a tree when a director ghosts a
-- building on top of it. Player-initiated marks also get the explanatory
-- chat message; engine-driven marks (no player_index) are just cancelled
-- silently so the player isn't spammed during routine placement.
function M.on_marked_for_deconstruction(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local hive_force = Force.get_hive()
  if hive_force then
    entity.cancel_deconstruction(hive_force)
  end
  if event.player_index then
    local player = game.get_player(event.player_index)
    if M.is_player(player) then
      player.print({"message.hm-no-deconstruction"})
    end
  end
end

-- ── Player lifecycle ─────────────────────────────────────────────────────────

function M.on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then M.update_hive_buttons(player) end
end

function M.on_player_respawned(event)
  local player = game.get_player(event.player_index)
  if not M.is_player(player) then return end
  M.apply(player)
  refill_loadout(player)
end

-- ── GUI events ───────────────────────────────────────────────────────────────

function M.on_gui_click(event)
  local name = event.element.name
  if name ~= shared.gui.join_button and name ~= shared.gui.reject_button then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if name == shared.gui.join_button then
    M.join(player)
  else
    M.reject(player)
  end
end

local allowed_entity_gui =
{
  [shared.entities.hive]         = true,
  [shared.entities.hive_node]    = true,
  [shared.entities.hive_lab]     = true,
  [shared.entities.hive_storage] = true
}

-- Block hive directors from opening any GUI that isn't whitelisted, and
-- redirect the click on a hive to its hidden storage chest so the player
-- doesn't see the empty roboport interface.
function M.on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not M.is_player(player) then return end
  if event.gui_type == defines.gui_type.controller then return end
  if event.gui_type == defines.gui_type.crafting   then return end
  if event.gui_type == defines.gui_type.none       then return end
  if event.gui_type == defines.gui_type.entity
     and event.entity and event.entity.valid then
    if event.entity.name == shared.entities.hive then
      local chest = Hive.get_chest(event.entity)
      if chest and chest.valid then
        player.opened = chest
        return
      end
    end
    -- Hive nodes have no chest of their own. Route the click to the chest
    -- of the nearest hive on the surface so the player can inspect storage
    -- from any node in the network.
    if event.entity.name == shared.entities.hive_node then
      local hive = Creatures.cached_nearest_hive(event.entity, Hive.all())
      if hive and hive.valid then
        local chest = Hive.get_chest(hive)
        if chest and chest.valid then
          player.opened = chest
          return
        end
      end
    end
    if allowed_entity_gui[event.entity.name] then return end
  end
  player.opened = nil
end

return M
