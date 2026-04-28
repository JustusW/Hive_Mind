local shared = require("shared")

local roboport = data.raw["roboport"]["roboport"]
local lab = data.raw["lab"]["lab"]
local automation_science = data.raw["tool"]["automation-science-pack"]

local pollution_science = table.deepcopy(automation_science)
pollution_science.name = shared.items.pollution_science_pack
pollution_science.localised_name = {"item-name." .. shared.items.pollution_science_pack}
pollution_science.localised_description = {"item-description." .. shared.items.pollution_science_pack}
pollution_science.order = "z[hive]-a[pollution-science]"
pollution_science.icons =
{
  {
    icon = automation_science.icon,
    icon_size = automation_science.icon_size,
    tint = {r = 1, g = 0.45, b = 0.2, a = 1}
  }
}

data:extend(
{
  {
    type = "item",
    name = shared.items.hive,
    icon = roboport.icon,
    icon_size = roboport.icon_size,
    subgroup = "defensive-structure",
    order = "z[hive]-a[hive]",
    place_result = shared.entities.hive,
    stack_size = 10
  },
  {
    type = "item",
    name = shared.items.hive_node,
    icon = roboport.icon,
    icon_size = roboport.icon_size,
    subgroup = "defensive-structure",
    order = "z[hive]-b[hive-node]",
    place_result = shared.entities.hive_node,
    stack_size = 20
  },
  {
    type = "item",
    name = shared.items.hive_lab,
    icon = lab.icon,
    icon_size = lab.icon_size,
    subgroup = "production-machine",
    order = "z[hive]-c[hive-lab]",
    place_result = shared.entities.hive_lab,
    stack_size = 20
  },
  {
    type = "item",
    name = shared.items.pheromones,
    icon = automation_science.icon,
    icon_size = automation_science.icon_size,
    subgroup = "intermediate-product",
    order = "z[hive]-d[pheromones]",
    stack_size = 1
  },
  {
    type = "item",
    name = shared.items.pollution,
    icon = automation_science.icon,
    icon_size = automation_science.icon_size,
    hidden = true,
    hidden_in_factoriopedia = true,
    stack_size = 2147483647
  },
  pollution_science
})
