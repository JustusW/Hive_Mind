-- Lab supply tick.
--
-- Each hive lab is kept stocked with pollution science packs by charging the
-- network (creature → pollution conversion as needed). Threshold and per-pack
-- pollution cost come from shared.science.

local shared = require("shared")
local Force  = require("script.force")
local Cost   = require("script.cost")

local M = {}

local SCIENCE_PACK_THRESHOLD = 10

function M.tick_supply()
  local hive_force = Force.get_hive()
  for _, surface in pairs(game.surfaces) do
    local labs = surface.find_entities_filtered{
      name = shared.entities.hive_lab, force = hive_force
    }
    for _, lab in pairs(labs) do
      if lab.valid then
        local lab_inv = lab.get_inventory(defines.inventory.lab_input)
        if lab_inv
           and lab_inv.get_item_count(shared.items.pollution_science_pack) < SCIENCE_PACK_THRESHOLD then
          if Cost.consume(surface, lab.position, shared.science.pollution_per_pack) then
            lab_inv.insert{name = shared.items.pollution_science_pack, count = 1}
          end
        end
      end
    end
  end
end

return M
