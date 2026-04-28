local shared = require("shared")

local function make_technology(name, icon, order, effects, prerequisites)
  return
  {
    type = "technology",
    name = name,
    icon = icon,
    icon_size = 256,
    order = order,
    effects = effects or {},
    prerequisites = prerequisites or {},
    unit =
    {
      count = 50,
      time = 15,
      ingredients =
      {
        {shared.items.pollution_science_pack, 1}
      }
    }
  }
end

data:extend(
{
  make_technology(
    shared.technologies.hive_spawners,
    "__base__/graphics/technology/military.png",
    "z[hive]-a[spawners]",
    {
      {type = "unlock-recipe", recipe = shared.recipes.hive_node}
    }
  ),
  make_technology(
    shared.technologies.hive_labs,
    "__base__/graphics/technology/research-speed.png",
    "z[hive]-b[labs]",
    {
      {type = "unlock-recipe", recipe = shared.recipes.hive_lab}
    },
    {shared.technologies.hive_spawners}
  ),
  make_technology(
    shared.technologies.worms_small,
    "__base__/graphics/technology/stronger-explosives-1.png",
    "z[hive]-c[worms-small]",
    {},
    {shared.technologies.hive_labs}
  ),
  make_technology(
    shared.technologies.worms_medium,
    "__base__/graphics/technology/stronger-explosives-2.png",
    "z[hive]-d[worms-medium]",
    {},
    {shared.technologies.worms_small}
  ),
  make_technology(
    shared.technologies.worms_big,
    "__base__/graphics/technology/stronger-explosives-3.png",
    "z[hive]-e[worms-big]",
    {},
    {shared.technologies.worms_medium}
  ),
  make_technology(
    shared.technologies.worms_behemoth,
    "__base__/graphics/technology/stronger-explosives-4.png",
    "z[hive]-f[worms-behemoth]",
    {},
    {shared.technologies.worms_big}
  )
})
