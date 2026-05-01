-- Per-player pollution read-out.
--
-- Earlier versions of the mod hovered a render-object label above every
-- hive showing the network's pollution capacity. That was an MP cost
-- multiplier: render objects are world-state and every property write
-- (text + color, twice per second per hive) was broadcast to every client
-- in lockstep. Players also disliked the visual clutter on the hive sprite.
--
-- This module replaces it with a per-player GUI element living in
-- player.gui.top alongside the hive buttons. Per-player GUI elements
-- only sync to the owning client, and we dirty-check the value+color so
-- unchanged frames don't write at all.
--
-- Cadence: same as before — `shared.intervals.labels` ticks. Cost per
-- tick is one Network.hives_for_position + one Cost.pollution_capacity
-- per joined hive player (was: per hive in the world, regardless of who
-- needed to see it).

local shared  = require("shared")
local State   = require("script.state")
local Hive    = require("script.hive")
local Network = require("script.network")
local Cost    = require("script.cost")

local M = {}

local FLOW_NAME    = "hm-button-flow"   -- shared with director.lua
local LABEL_NAME   = "hm-pollution-readout"
local THRESHOLD_LOW = 100

local COLOR_HEALTHY = {r = 0.65, g = 1.00, b = 0.40, a = 1}
local COLOR_LOW     = {r = 1.00, g = 0.65, b = 0.20, a = 1}
local COLOR_EMPTY   = {r = 1.00, g = 0.35, b = 0.35, a = 1}

local function color_band(cap)
  if cap <= 0            then return "empty",   COLOR_EMPTY   end
  if cap < THRESHOLD_LOW then return "low",     COLOR_LOW     end
  return "healthy", COLOR_HEALTHY
end

local function format_text(cap)
  return "[item=" .. shared.items.pollution .. "] " .. tostring(cap)
end

local function get_flow(player)
  if not (player and player.valid and player.gui and player.gui.top) then return nil end
  return player.gui.top[FLOW_NAME]
end

local function ensure_label(player)
  local flow = get_flow(player)
  if not flow then
    -- Create the flow on demand. The Director module also creates this
    -- flow for its buttons; we share the parent so a hive director sees
    -- both buttons (during onboarding) and read-out (after joining) in
    -- the same horizontal strip.
    if not (player and player.valid and player.gui and player.gui.top) then return nil end
    flow = player.gui.top.add{
      type      = "flow",
      name      = FLOW_NAME,
      direction = "horizontal"
    }
  end
  local label = flow[LABEL_NAME]
  if label and label.valid then return label end
  label = flow.add{
    type    = "label",
    name    = LABEL_NAME,
    caption = ""
  }
  -- 2× default size so the read-out is legible without squinting at the
  -- top bar. heading-1-label is the largest built-in label style; if a
  -- future Factorio version drops it, fall through silently.
  pcall(function() label.style.font = "heading-1-label" end)
  return label
end

local function destroy_label(player)
  local flow = get_flow(player)
  if not flow then return end
  local label = flow[LABEL_NAME]
  if label and label.valid then label.destroy() end
end

-- Find one of `player`'s hives. Returns nil if the player has no hives.
local function any_player_hive(player)
  local s = State.get()
  local bucket = s.hives_by_player[player.index]
  if not bucket then return nil end
  for _, hive_data in pairs(bucket) do
    if hive_data.entity and hive_data.entity.valid then
      return hive_data.entity
    end
  end
  return nil
end

-- One label tick per joined player. Hidden if the player has no hive
-- (nothing meaningful to show); otherwise cap is computed from one of their
-- hives' networks. Dirty-checked: unchanged value+band don't touch the GUI.
local function tick_player(player)
  if not (player and player.valid and player.connected) then return end
  if not State.get().joined_players[player.index] then
    destroy_label(player)
    return
  end

  local hive = any_player_hive(player)
  if not hive then
    destroy_label(player)
    return
  end

  local hives = Network.hives_for_position(hive.surface, hive.position) or {hive}
  local cap   = Cost.pollution_capacity(hives)
  local band, color = color_band(cap)

  local label = ensure_label(player)
  if not (label and label.valid) then return end

  -- Dirty-check: we keep the last rendered cap + band on the LuaGuiElement's
  -- `tags` so the check survives save/load without us touching storage.
  local tags = label.tags or {}
  if tags.cap ~= cap then
    label.caption = format_text(cap)
    tags.cap = cap
  end
  if tags.band ~= band then
    label.style.font_color = color
    tags.band = band
  end
  label.tags = tags
end

function M.tick()
  for _, player in pairs(game.connected_players) do
    tick_player(player)
  end
end

-- Cleanup hook for legacy installs: wipes the old per-hive render-object
-- labels (if any) and the hive_storage.label_id field. Idempotent.
function M.cleanup_legacy_labels()
  if not (rendering and rendering.get_object_by_id) then return end
  local s = State.get()
  for _, record in pairs(s.hive_storage or {}) do
    local id = record.label_id
    if id then
      local obj = rendering.get_object_by_id(id)
      if obj and obj.valid then obj.destroy() end
      record.label_id = nil
    end
  end
end

return M
