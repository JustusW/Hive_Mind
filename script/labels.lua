-- Floating pollution label above each hive.
--
-- Each hive renders a small text label showing the pollution currently
-- available to its network (existing pollution items + the value of every
-- stored creature, summed across all chests in the network covering the
-- hive's position). The label is recoloured by status: green for healthy,
-- amber for low, red for empty.
--
-- Render object ids are persisted on the hive's storage record so the same
-- label survives save/load. If the persisted id no longer resolves (e.g.
-- the world was edited or the render object was cleared), the next tick
-- recreates the label.

local shared  = require("shared")
local Hive    = require("script.hive")
local Network = require("script.network")
local Cost    = require("script.cost")

local M = {}

local LABEL_OFFSET  = {0, -2.7}
local LABEL_SCALE   = 1.6
local COLOR_HEALTHY = {r = 0.65, g = 1.00, b = 0.40, a = 1}
local COLOR_LOW     = {r = 1.00, g = 0.65, b = 0.20, a = 1}
local COLOR_EMPTY   = {r = 1.00, g = 0.35, b = 0.35, a = 1}
local THRESHOLD_LOW = 100

local function color_for(cap)
  if cap <= 0           then return COLOR_EMPTY end
  if cap < THRESHOLD_LOW then return COLOR_LOW end
  return COLOR_HEALTHY
end

local function fetch_label(label_id)
  if not label_id then return nil end
  local obj = rendering.get_object_by_id(label_id)
  if obj and obj.valid then return obj end
  return nil
end

local function ensure_label(record, hive)
  local existing = fetch_label(record.label_id)
  if existing then return existing end
  local obj = rendering.draw_text{
    text          = "",
    surface       = hive.surface,
    target        = {entity = hive, offset = LABEL_OFFSET},
    color         = COLOR_HEALTHY,
    alignment     = "center",
    scale         = LABEL_SCALE,
    use_rich_text = true
  }
  record.label_id = obj.id
  return obj
end

local function format_text(cap)
  return "[item=" .. shared.items.pollution .. "] " .. tostring(cap)
end

function M.tick()
  for _, hive in pairs(Hive.all()) do
    local record = Hive.get_storage(hive)
    if record then
      local hives = Network.hives_for_position(hive.surface, hive.position) or {hive}
      local cap   = Cost.pollution_capacity(hives)
      local obj   = ensure_label(record, hive)
      if obj and obj.valid then
        obj.text  = format_text(cap)
        obj.color = color_for(cap)
      end
    end
  end
end

return M
