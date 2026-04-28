local shared = {}

shared.prefix = "hm-"
shared.force_name = "hivemind"
shared.gui =
{
  join_button = "hm-join-hive-button"
}

shared.entities =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab"
}

shared.items =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab",
  pheromones = "hm-pheromones",
  pollution = "hm-hidden-pollution",
  pollution_science_pack = "hm-pollution-science-pack"
}

shared.recipes =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab",
  pheromones = "hm-pheromones"
}

shared.technologies =
{
  hive_spawners = "hm-hive-spawners",
  hive_labs = "hm-hive-labs",
  worms_small = "hm-worms-small",
  worms_medium = "hm-worms-medium",
  worms_big = "hm-worms-big",
  worms_behemoth = "hm-worms-behemoth"
}

shared.ranges =
{
  hive = 1000,
  hive_node = 500
}

shared.intervals =
{
  recruit = 120,
  absorb = 30,
  pheromones = 60
}

shared.costs =
{
  pheromones_duration_ticks = 60 * 60
}

shared.build_costs =
{
  [shared.entities.hive_node] = 100,
  [shared.entities.hive_lab] = 150
}

shared.science =
{
  pollution_per_pack = 25
}

shared.creature_roles =
{
  attract = "attract",
  store = "store",
  consume = "consume"
}

return shared
