-- Creep tile: a tinted copy of sand-1, placed by hive structures via
-- the script's organic-growth loop. Single colour; deeper variants are
-- intentionally not reintroduced (the boundary growth gives plenty of
-- visual texture on its own).

local shared = require("shared")

local creep = table.deepcopy(data.raw["tile"]["sand-1"])
creep.name = shared.creep_tile
creep.localised_name = {"tile-name.creep"}
creep.autoplace = nil
creep.layer = 127
creep.tint = {r = 0.42, g = 0.08, b = 0.55, a = 1}        -- royal purple
creep.map_color = {r = 0.28, g = 0.06, b = 0.38}
creep.absorptions_per_second = {}
creep.walking_speed_modifier = 1.3
creep.needs_correction = false

-- Creep walking sounds, vendored from the original Hive Mind port.
creep.walking_sound = {}
for k = 1, 8 do
  creep.walking_sound[k] =
  {
    filename = "__Hive_Mind_Reworked__/sound/creep/creep-0" .. k .. ".ogg"
  }
end

data:extend{creep}
