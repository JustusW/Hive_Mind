local shared = require("shared")

data:extend(
{
  {
    type = "recipe",
    name = shared.recipes.hive,
    localised_name = {"recipe-name." .. shared.recipes.hive},
    enabled = false,
    energy_required = 1,
    results =
    {
      {type = "item", name = shared.items.hive, amount = 1}
    }
  },
  {
    type = "recipe",
    name = shared.recipes.hive_node,
    localised_name = {"recipe-name." .. shared.recipes.hive_node},
    enabled = false,
    energy_required = 1,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 10}
    },
    results =
    {
      {type = "item", name = shared.items.hive_node, amount = 1}
    }
  },
  {
    type = "recipe",
    name = shared.recipes.hive_lab,
    localised_name = {"recipe-name." .. shared.recipes.hive_lab},
    enabled = false,
    energy_required = 1,
    ingredients =
    {
      {type = "item", name = "electronic-circuit", amount = 10},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "transport-belt", amount = 4}
    },
    results =
    {
      {type = "item", name = shared.items.hive_lab, amount = 1}
    }
  },
  {
    type = "recipe",
    name = shared.recipes.pheromones,
    localised_name = {"recipe-name." .. shared.recipes.pheromones},
    enabled = false,
    energy_required = 1,
    results =
    {
      {type = "item", name = shared.items.pheromones, amount = 1}
    }
  },
  {
    type = "recipe",
    name = shared.recipes.use_pheromones,
    localised_name = {"recipe-name." .. shared.recipes.use_pheromones},
    enabled = false,
    energy_required = 1,
    ingredients =
    {
      {type = "item", name = shared.items.pheromones, amount = 1}
    },
    results =
    {
      {type = "item", name = shared.items.pheromone_burst, amount = 1}
    },
    allow_decomposition = false,
    allow_as_intermediate = false,
    allow_intermediates = false
  }
})
