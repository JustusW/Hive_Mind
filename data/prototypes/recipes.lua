local shared = require("shared")

local subgroup_pheromones = "production-machine"
local subgroup_other = "intermediate-product"

-- All hive-tier recipes are zero-ingredient cursor stamps. The pollution cost
-- is charged from the hive network at placement time (script/main.lua →
-- consume_network_pollution), not from the player. See design.md §
-- "Cost charging".

local recipes =
{
  -- Hive: free starter. Always available.
  {
    type = "recipe",
    name = shared.recipes.hive,
    localised_name = {"recipe-name." .. shared.recipes.hive},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.hive, amount = 1}}
  },
  -- Hive Node: gated by hm-hive-spawners (auto-completed on first hive placement).
  {
    type = "recipe",
    name = shared.recipes.hive_node,
    localised_name = {"recipe-name." .. shared.recipes.hive_node},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.hive_node, amount = 1}}
  },
  -- Hive Lab: gated by hm-hive-labs (auto-completed when creep first spreads).
  {
    type = "recipe",
    name = shared.recipes.hive_lab,
    localised_name = {"recipe-name." .. shared.recipes.hive_lab},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.hive_lab, amount = 1}}
  },
  -- Biter spawner: gated by hm-hive-spawners. Player item places a proxy ghost;
  -- the worker dispatcher materialises the proxy and Build.on_built swaps it
  -- for a real biter-spawner.
  {
    type = "recipe",
    name = shared.recipes.hive_spawner,
    localised_name = {"recipe-name." .. shared.recipes.hive_spawner},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.hive_spawner, amount = 1}}
  },
  -- Spitter spawner: gated by hm-hive-spawners alongside the biter version.
  {
    type = "recipe",
    name = shared.recipes.hive_spitter_spawner,
    localised_name = {"recipe-name." .. shared.recipes.hive_spitter_spawner},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.hive_spitter_spawner, amount = 1}}
  },
  -- Debug pollution generator: free, always enabled. Gate behind a startup
  -- setting before shipping (see design.md "Debug fixtures").
  {
    type = "recipe",
    name = shared.recipes.pollution_generator,
    localised_name = {"recipe-name." .. shared.recipes.pollution_generator},
    subgroup = subgroup_other,
    enabled = true,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.pollution_generator, amount = 1}}
  },
  -- Pheromones on: produces the lure item. Toggle the hive→player attraction.
  {
    type = "recipe",
    name = shared.recipes.pheromones_on,
    localised_name = {"recipe-name." .. shared.recipes.pheromones_on},
    subgroup = subgroup_pheromones,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = shared.items.pheromones, amount = 1}}
  },
  -- Pheromones off: consumes the lure item. No result; icon must be set
  -- explicitly because Factorio cannot derive one from an empty result list.
  {
    type = "recipe",
    name = shared.recipes.pheromones_off,
    localised_name = {"recipe-name." .. shared.recipes.pheromones_off},
    icon = data.raw["item"][shared.items.pheromones].icon,
    icon_size = data.raw["item"][shared.items.pheromones].icon_size,
    subgroup = subgroup_pheromones,
    enabled = false,
    energy_required = 0.5,
    ingredients = {{type = "item", name = shared.items.pheromones, amount = 1}},
    results = {},
    allow_decomposition = false,
    allow_as_intermediate = false
  }
}

-- Worm tier recipes: one per tier, gated by the matching tech.
for _, tier in pairs(shared.worm_tiers) do
  local w = shared.worm[tier]
  recipes[#recipes + 1] =
  {
    type = "recipe",
    name = w.recipe,
    localised_name = {"recipe-name." .. w.recipe},
    subgroup = subgroup_other,
    enabled = false,
    energy_required = 0.5,
    ingredients = {},
    results = {{type = "item", name = w.item, amount = 1}}
  }
end

data:extend(recipes)
