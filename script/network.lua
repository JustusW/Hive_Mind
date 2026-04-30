-- Spatial network resolver.
--
-- A "network" is the set of hive + hive-node entities whose construction
-- radii overlap, scoped to a single force and surface. Cost reads/writes
-- treat the union of all member chests as one virtual inventory.
--
-- This module is pure spatial + chest-iteration logic. Pollution arithmetic
-- and creature-conversion live in cost.lua.

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")

local M = {}

-- Every hive-side structure on `surface`, with its build/visibility radius
-- and kind. `kind` distinguishes "hive" (has a chest) from "node".
function M.all_structures(surface)
  local s = State.get()
  local list = {}
  for _, bucket in pairs(s.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      local e = hive_data.entity
      if e and e.valid and e.surface == surface then
        list[#list + 1] = {entity = e, range = shared.ranges.hive, kind = "hive"}
      end
    end
  end
  for _, node_data in pairs(s.hive_nodes) do
    local e = node_data.entity
    if e and e.valid and e.surface == surface then
      list[#list + 1] = {entity = e, range = shared.ranges.hive_node, kind = "node"}
    end
  end
  return list
end

-- Return the list of hive entities (chests, not nodes) in the network whose
-- combined construction radii cover `position`. nil if no member reaches it.
--
-- Algorithm: seed with anything covering the position, then expand by overlap
-- until stable. Two structures "overlap" when their ranges touch.
--
-- `reach` (optional, default 0) extends the seed check: a structure counts as
-- covering `position` when `dist <= s.range + reach`. This lets the caller
-- ask "would a new entity placed here, with its own range = reach, connect
-- to the network?" — used for hive-node placement so the player can chain
-- nodes outward without each new node having to land inside the previous
-- one's box.
function M.hives_for_position(surface, position, reach)
  reach = reach or 0
  local structs = M.all_structures(surface)
  if #structs == 0 then return nil end

  local in_net = {}
  for i, s in ipairs(structs) do
    local dx = s.entity.position.x - position.x
    local dy = s.entity.position.y - position.y
    local seed = s.range + reach
    if dx * dx + dy * dy <= seed * seed then
      in_net[i] = true
    end
  end
  if not next(in_net) then return nil end

  local changed = true
  while changed do
    changed = false
    for i, s in ipairs(structs) do
      if not in_net[i] then
        for j in pairs(in_net) do
          local m = structs[j]
          local dx = s.entity.position.x - m.entity.position.x
          local dy = s.entity.position.y - m.entity.position.y
          local touch = s.range + m.range
          if dx * dx + dy * dy <= touch * touch then
            in_net[i] = true
            changed = true
            break
          end
        end
      end
    end
  end

  local hives = {}
  for i in pairs(in_net) do
    if structs[i].kind == "hive" then
      hives[#hives + 1] = structs[i].entity
    end
  end
  return (#hives > 0) and hives or nil
end

-- Sum of `item_name` across all chests in `hives`.
function M.item_count(hives, item_name)
  local total = 0
  for _, hive in pairs(hives) do
    local chest = Hive.get_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv then total = total + inv.get_item_count(item_name) end
    end
  end
  return total
end

-- Insert `item_stack` into the first chest in the network covering
-- `position` that can accept it. Returns true on success. Uses the
-- default reach (the position must already be inside the network).
function M.insert(surface, position, item_stack)
  local hives = M.hives_for_position(surface, position, 0)
  if not hives then return false end
  for _, hive in pairs(hives) do
    local chest = Hive.get_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv and inv.can_insert(item_stack) then
        inv.insert(item_stack)
        return true
      end
    end
  end
  return false
end

return M
