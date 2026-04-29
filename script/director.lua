-- Player ↔ hive director state.
--
-- A "hive player" is a player that has joined the hive. They are switched to
-- the god controller, assigned to the hivemind force, and locked into a
-- permission group that blocks mining, dropping, and inventory transfers.
--
-- This module also owns the join button GUI and the mining/decon interception
-- handlers that keep the director from manipulating the world by hand.

local shared  = require("shared")
local mod_gui = require("mod-gui")
local State   = require("script.state")
local Force   = require("script.force")

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
-- Two sibling buttons live in the mod-gui flow: "Join the Hive" and "Reject
-- the Hive". Both vanish for good once the player either joins or rejects;
-- rejection is persisted in `rejected_players` and survives save/load.

local function ensure_button(flow, name, caption)
  if flow[name] then return end
  flow.add{
    type    = "button",
    name    = name,
    caption = caption,
    style   = mod_gui.button_style
  }
end

local function destroy_button(flow, name)
  local existing = flow[name]
  if existing then existing.destroy() end
end

function M.update_hive_buttons(player)
  if not (player and player.valid) then return end
  local flow = mod_gui.get_button_flow(player)
  if M.is_player(player) or M.is_rejected(player) then
    destroy_button(flow, shared.gui.join_button)
    destroy_button(flow, shared.gui.reject_button)
    return
  end
  ensure_button(flow, shared.gui.join_button,   {"gui.hm-join-hive"})
  ensure_button(flow, shared.gui.reject_button, {"gui.hm-reject-hive"})
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

-- Mark `player` as joined and apply the director state. No-op if already joined.
function M.join(player)
  if M.is_player(player) then return end
  State.get().joined_players[player.index] = true
  M.apply(player)
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

function M.on_marked_for_deconstruction(event)
  local player = event.player_index and game.get_player(event.player_index)
  if not M.is_player(player) then return end
  local entity = event.entity
  if entity and entity.valid then
    entity.cancel_deconstruction(entity.force, player)
  end
  if player then player.print({"message.hm-no-deconstruction"}) end
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

-- Block hive directors from opening any GUI that isn't whitelisted.
function M.on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not M.is_player(player) then return end
  if event.gui_type == defines.gui_type.controller then return end
  if event.gui_type == defines.gui_type.crafting   then return end
  if event.gui_type == defines.gui_type.none       then return end
  if event.gui_type == defines.gui_type.entity then
    if event.entity and event.entity.valid and allowed_entity_gui[event.entity.name] then
      return
    end
  end
  player.opened = nil
end

return M
