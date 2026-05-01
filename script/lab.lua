-- Lab supply tick.
--
-- Each hive lab is kept stocked with pollution science packs by charging the
-- network (creature → pollution conversion as needed). Threshold and per-pack
-- pollution cost come from shared.science.
--
-- Lab list source: `Hive.labs()` returns the cached lab list. The cache is
-- populated lazily and invalidated by Hive.track_lab / Hive.untrack_lab,
-- so this tick costs O(labs) inventory reads + O(labs) Cost.consume calls
-- and nothing per surface or per non-lab entity. The reconciler watchdog
-- verifies the cache against a fresh world scan every 600 ticks × N caches.

local shared = require("shared")
local Cost   = require("script.cost")
local Hive   = require("script.hive")

local M = {}

local SCIENCE_PACK_THRESHOLD = 10

function M.tick_supply()
  for _, lab in pairs(Hive.labs()) do
    if lab and lab.valid then
      local lab_inv = lab.get_inventory(defines.inventory.lab_input)
      if lab_inv
         and lab_inv.get_item_count(shared.items.pollution_science_pack) < SCIENCE_PACK_THRESHOLD then
        if Cost.consume(lab.surface, lab.position, shared.science.pollution_per_pack) then
          lab_inv.insert{name = shared.items.pollution_science_pack, count = 1}
        end
      end
    end
  end
end

return M
