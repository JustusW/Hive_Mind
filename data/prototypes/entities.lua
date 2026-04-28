local shared = require("shared")

local base_hive = table.deepcopy(data.raw["container"]["steel-chest"])
base_hive.name = shared.entities.hive
base_hive.localised_name = {"entity-name." .. shared.entities.hive}
base_hive.localised_description = {"entity-description." .. shared.entities.hive}
base_hive.minable = {mining_time = 0.5, result = shared.items.hive}
base_hive.max_health = 1500
base_hive.inventory_size = 200
base_hive.picture = table.deepcopy(data.raw["container"]["steel-chest"].picture)

local hive_node = table.deepcopy(data.raw["roboport"]["roboport"])
hive_node.name = shared.entities.hive_node
hive_node.localised_name = {"entity-name." .. shared.entities.hive_node}
hive_node.localised_description = {"entity-description." .. shared.entities.hive_node}
hive_node.minable = {mining_time = 0.5, result = shared.items.hive_node}
hive_node.max_health = 1000
hive_node.logistics_radius = shared.ranges.hive_node
hive_node.construction_radius = shared.ranges.hive_node
hive_node.robot_slots_count = 0
hive_node.material_slots_count = 0
hive_node.charging_station_count = 0
hive_node.charging_offsets = {}
hive_node.energy_source =
{
  type = "void"
}
hive_node.energy_usage = "1MW"
hive_node.recharge_minimum = "1MJ"
hive_node.charging_energy = "1MW"

local hive_lab = table.deepcopy(data.raw["lab"]["lab"])
hive_lab.name = shared.entities.hive_lab
hive_lab.localised_name = {"entity-name." .. shared.entities.hive_lab}
hive_lab.localised_description = {"entity-description." .. shared.entities.hive_lab}
hive_lab.minable = {mining_time = 0.5, result = shared.items.hive_lab}
hive_lab.inputs = {shared.items.pollution_science_pack}
hive_lab.energy_source =
{
  type = "void"
}
hive_lab.energy_usage = "1W"
hive_lab.researching_speed = 1

local director_body = table.deepcopy(data.raw["character"]["character"])
director_body.name = shared.entities.director_body
director_body.localised_name = {"entity-name.character"}
director_body.inventory_size = 20
director_body.build_distance = 125
director_body.drop_item_distance = 0
director_body.reach_distance = 125
director_body.reach_resource_distance = 0
director_body.item_pickup_distance = 0
director_body.loot_pickup_distance = 0
director_body.enter_vehicle_distance = 0
director_body.mining_speed = 0
director_body.running_speed = 0.25
director_body.collision_box = {{0, 0}, {0, 0}}
director_body.selection_box = {{-0.1, -0.1}, {0.1, 0.1}}
director_body.collision_mask = {layers = {}}
director_body.character_corpse = nil
director_body.light = nil
director_body.max_health = 1000000
director_body.healing_per_tick = 1000

data:extend({base_hive, hive_node, hive_lab, director_body})
