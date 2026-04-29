-- Creep tile family: tinted copies of sand-1, placed by hive structures.
-- Multiple shade variants are interleaved at random by the script's tick_creep
-- loop so the result looks organic rather than uniform.
local shared = require("shared")

-- Five shades from deep wine through bright lavender. Indexed by
-- shared.creep_tiles[i].
local shades =
{
  {r = 0.30, g = 0.05, b = 0.40, a = 1},   -- deep wine
  {r = 0.42, g = 0.08, b = 0.55, a = 1},   -- royal purple
  {r = 0.55, g = 0.12, b = 0.70, a = 1},   -- mid purple
  {r = 0.65, g = 0.18, b = 0.78, a = 1}    -- bright magenta
}

local map_shades =
{
  {r = 0.20, g = 0.04, b = 0.30},
  {r = 0.28, g = 0.06, b = 0.38},
  {r = 0.36, g = 0.10, b = 0.48},
  {r = 0.45, g = 0.14, b = 0.55}
}

assert(#shades == shared.creep_tile_count, "creep shade count must match shared.creep_tile_count")

local creep_variants = {}

for i = 1, shared.creep_tile_count do
  local creep = table.deepcopy(data.raw["tile"]["sand-1"])
  creep.name = shared.creep_tiles[i]
  creep.localised_name = {"tile-name.creep"}
  creep.autoplace = nil
  creep.layer = 127
  creep.tint = shades[i]
  creep.map_color = map_shades[i]
  creep.absorptions_per_second = {}
  creep.walking_speed_modifier = 1.3
  creep.needs_correction = false

  -- Reuse the legacy creep walking sounds for now; harmless if missing at runtime.
  creep.walking_sound = {}
  for k = 1, 8 do
    creep.walking_sound[k] =
    {
      filename = "__Hive_Mind__/legacy/hive-mind-2.0-port-reference/data/tiles/creep-0" .. k .. ".ogg"
    }
  end

  creep_variants[#creep_variants + 1] = creep
end

data:extend(creep_variants)
