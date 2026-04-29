local shared = require("shared")

local science_proto  = data.raw["tool"]["automation-science-pack"]
local robot_proto    = data.raw["construction-robot"]["construction-robot"]
local biter_proto    = data.raw["unit"]["small-biter"]
local spawner_proto  = data.raw["unit-spawner"]["biter-spawner"]
local behemoth_proto = data.raw["unit"]["behemoth-biter"]

-- Worm-icon source per tier; falls back to small-worm-turret prototype if a
-- specific tier isn't loaded for any reason.
local function worm_icon_proto(tier)
  return data.raw["turret"][tier .. "-worm-turret"]
      or data.raw["unit"][tier .. "-worm-turret"]
      or spawner_proto
end

local prototypes =
{
  {
    type = "item",
    name = shared.items.hive,
    localised_name = {"item-name." .. shared.items.hive},
    icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
              tint = {r=0.90, g=0.35, b=0.05, a=1}}},
    subgroup = "defensive-structure",
    order = "z[hive]-a[hive]",
    place_result = shared.entities.hive,
    stack_size = 1
  },
  {
    type = "item",
    name = shared.items.hive_node,
    localised_name = {"item-name." .. shared.items.hive_node},
    icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
              tint = {r=0.10, g=0.75, b=0.45, a=1}}},
    subgroup = "defensive-structure",
    order = "z[hive]-b[hive-node]",
    place_result = shared.entities.hive_node,
    stack_size = 10
  },
  {
    type = "item",
    name = shared.items.hive_lab,
    localised_name = {"item-name." .. shared.items.hive_lab},
    icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
              tint = {r=0.55, g=0.10, b=0.85, a=1}}},
    subgroup = "production-machine",
    order = "z[hive]-c[hive-lab]",
    place_result = shared.entities.hive_lab,
    stack_size = 10
  },
  {
    type = "item",
    name = shared.items.pheromones,
    localised_name = {"item-name." .. shared.items.pheromones},
    localised_description = {"item-description." .. shared.items.pheromones},
    icon = biter_proto.icon,
    icon_size = biter_proto.icon_size,
    subgroup = "intermediate-product",
    order = "z[hive]-d[pheromones]",
    stack_size = 1
  },
  -- Spawner item — places the proxy ghost; on_robot_built_entity swaps it for
  -- a real biter-spawner.
  {
    type = "item",
    name = shared.items.hive_spawner,
    localised_name = {"item-name." .. shared.items.hive_spawner},
    icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
              tint = {r=0.90, g=0.35, b=0.05, a=1}}},
    subgroup = "defensive-structure",
    order = "z[hive]-e[spawner]",
    place_result = shared.entities.spawner_ghost,
    stack_size = 10
  },
  -- Pollution generator (debug).
  {
    type = "item",
    name = shared.items.pollution_generator,
    localised_name = {"item-name." .. shared.items.pollution_generator},
    icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
              tint = {r=0.9, g=0.2, b=0.0, a=1}}},
    subgroup = "defensive-structure",
    order = "z[hive]-z[pollution-gen]",
    place_result = shared.entities.pollution_generator,
    stack_size = 10
  },
  -- Construction robot item — hidden, inserted into hives by script.
  {
    type = "item",
    name = shared.items.construction_robot,
    localised_name = {"entity-name." .. shared.entities.construction_robot},
    icon = robot_proto.icon,
    icon_size = robot_proto.icon_size,
    hidden = true,
    hidden_in_factoriopedia = true,
    subgroup = "intermediate-product",
    order = "z[hive]-z[robot]",
    place_result = shared.entities.construction_robot,
    stack_size = 100
  }
}

-- Worm tier items: place_result is the proxy ghost for that tier.
for tier_index, tier in pairs(shared.worm_tiers) do
  local w = shared.worm[tier]
  local proto = worm_icon_proto(tier)
  prototypes[#prototypes + 1] =
  {
    type = "item",
    name = w.item,
    localised_name = {"item-name." .. w.item},
    icons = {{icon = proto.icon, icon_size = proto.icon_size,
              tint = {r=0.55, g=0.10, b=0.85, a=1}}},
    subgroup = "defensive-structure",
    order = ("z[hive]-f[worm-%d-%s]"):format(tier_index, tier),
    place_result = w.ghost,
    stack_size = 10
  }
end

-- Pollution Science Pack
local pollution_science = table.deepcopy(science_proto)
pollution_science.name = shared.items.pollution_science_pack
pollution_science.localised_name = {"item-name." .. shared.items.pollution_science_pack}
pollution_science.localised_description = {"item-description." .. shared.items.pollution_science_pack}
pollution_science.order = "z[hive]-g[pollution-science]"
pollution_science.icons =
{
  {
    icon = science_proto.icon,
    icon_size = science_proto.icon_size,
    tint = {r = 0.3, g = 0.7, b = 0.2, a = 1}
  }
}
prototypes[#prototypes + 1] = pollution_science

-- One hidden item per unit type — creature storage in hive chests.
for unit_name, unit in pairs(data.raw.unit) do
  local creature_item =
  {
    type = "item",
    name = shared.creature_item_name(unit_name),
    subgroup = "intermediate-product",
    order = "z[hive]-u[" .. unit_name .. "]",
    hidden = true,
    hidden_in_factoriopedia = true,
    stack_size = 1000
  }
  if unit.icons then
    creature_item.icons = table.deepcopy(unit.icons)
    creature_item.icon_size = unit.icon_size or (unit.icons[1] and unit.icons[1].icon_size) or 64
  else
    creature_item.icon = unit.icon
    creature_item.icon_size = unit.icon_size
  end
  prototypes[#prototypes + 1] = creature_item
end

-- Pollution: hidden currency, produced on demand from stored creatures.
prototypes[#prototypes + 1] =
{
  type = "item",
  name = shared.items.pollution,
  localised_name = {"item-name." .. shared.items.pollution},
  localised_description = {"item-description." .. shared.items.pollution},
  icons = {{icon = spawner_proto.icon, icon_size = spawner_proto.icon_size,
            tint = {r=0.45, g=0.60, b=0.10, a=1}}},
  subgroup = "intermediate-product",
  order = "z[hive]-h[pollution]",
  hidden = true,
  hidden_in_factoriopedia = true,
  stack_size = 10000
}

data:extend(prototypes)
