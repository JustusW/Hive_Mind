local shared = require("shared")

local function make_tech(name, icon_path, order, prerequisites, effects)
  return
  {
    type = "technology",
    name = name,
    localised_name = {"technology-name." .. name},
    localised_description = {"technology-description." .. name},
    icon = icon_path,
    icon_size = 256,
    order = order,
    prerequisites = prerequisites or {},
    effects = effects or {},
    unit =
    {
      count = 50,
      time = 15,
      ingredients = {{shared.items.pollution_science_pack, 1}}
    }
  }
end

local function unlock(recipe_name)
  return {type = "unlock-recipe", recipe = recipe_name}
end

local techs =
{
  -- hm-hive-spawners is auto-completed when the first hive is placed.
  -- It must still grant its recipes via the normal unlock mechanism so the
  -- recipes show up in the player's craft menu.
  make_tech(
    shared.technologies.hive_spawners,
    "__base__/graphics/technology/military.png",
    "z[hive]-a[spawners]",
    {},
    {
      unlock(shared.recipes.hive_node),
      unlock(shared.recipes.hive_spawner),
      unlock(shared.recipes.hive_spitter_spawner)
    }
  ),
  -- hm-hive-labs is auto-completed when creep first spreads.
  make_tech(
    shared.technologies.hive_labs,
    "__base__/graphics/technology/research-speed.png",
    "z[hive]-b[labs]",
    {shared.technologies.hive_spawners},
    {unlock(shared.recipes.hive_lab)}
  )
}

-- Worm tier techs: each unlocks the recipe for its tier and prerequisites the
-- previous tier.
local worm_tech_icons =
{
  small    = "__base__/graphics/technology/stronger-explosives-1.png",
  medium   = "__base__/graphics/technology/stronger-explosives-2.png",
  big      = "__base__/graphics/technology/stronger-explosives-3.png",
  behemoth = "__base__/graphics/technology/stronger-explosives-3.png"
}

local prev_tier_tech = shared.technologies.hive_labs
for tier_index, tier in pairs(shared.worm_tiers) do
  local w = shared.worm[tier]
  techs[#techs + 1] = make_tech(
    w.tech,
    worm_tech_icons[tier],
    ("z[hive]-c[worm-%d-%s]"):format(tier_index, tier),
    {prev_tier_tech},
    {unlock(w.recipe)}
  )
  prev_tier_tech = w.tech
end

-- Infinite tech: each level adds +10% to the hive's attraction radius. The
-- effect is applied at runtime in script/creatures.lua; we use a "nothing"
-- effect here purely to render a description in the research GUI.
techs[#techs + 1] =
{
  type = "technology",
  name = shared.technologies.attraction_reach,
  localised_name = {"technology-name." .. shared.technologies.attraction_reach},
  localised_description = {"technology-description." .. shared.technologies.attraction_reach},
  icon = "__base__/graphics/technology/research-speed.png",
  icon_size = 256,
  order = "z[hive]-d[attraction-reach]",
  max_level = "infinite",
  prerequisites = {shared.technologies.hive_labs},
  effects =
  {
    {
      type = "nothing",
      effect_description = {"effect-description." .. shared.technologies.attraction_reach}
    }
  },
  unit =
  {
    count_formula = "2^(L-1)*100",
    time = 30,
    ingredients = {{shared.items.pollution_science_pack, 1}}
  }
}

data:extend(techs)
