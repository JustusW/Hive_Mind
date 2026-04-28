local shared = require("shared")
local util = require("__Hive_Mind__/data/tf_util/tf_util")

local growth_node_prefix = shared.growth_node_prefix
local growth_progress_item_name = shared.growth_progress_item
local growth_recipe_prefix = shared.growth_recipe_prefix
local growth_cancel_recipe = shared.growth_cancel_recipe

local spawner = util.copy(data.raw["unit-spawner"]["biter-spawner"])
local base_machine = util.copy(data.raw["assembling-machine"]["assembling-machine-1"])
local spawner_animation = util.copy(((spawner.graphics_set and spawner.graphics_set.animations) or spawner.animations)[1])

util.recursive_hack_scale(spawner_animation, 1 / 5)
util.recursive_hack_tint(spawner_animation, {r = 0.4, g = 1, b = 0.4})

local category =
{
  type = "recipe-category",
  name = shared.growth_node
}

local growth_progress_item =
{
  type = "item",
  name = growth_progress_item_name,
  icon = spawner.icon,
  icon_size = spawner.icon_size,
  hidden = true,
  stack_size = 5000
}

local get_target_prototype = function(target_name)
  local types =
  {
    "assembling-machine",
    "simple-entity-with-force",
    "lab",
    "mining-drill",
    "turret"
  }

  for _, type_name in pairs(types) do
    local bucket = data.raw[type_name]
    if bucket and bucket[target_name] then
      return bucket[target_name]
    end
  end
end

local entities = {}
local recipes = {}

recipes[#recipes + 1] =
{
  type = "recipe",
  name = growth_cancel_recipe,
  localised_name = {"cancel-growth"},
  icon = spawner.icon,
  icon_size = spawner.icon_size,
  enabled = true,
  allow_as_intermediate = false,
  allow_decomposition = false,
  category = shared.growth_node,
  ingredients = {{type = "item", name = growth_progress_item_name, amount = 1}},
  results = {{type = "item", name = growth_progress_item_name, amount = 1}},
  energy_required = 1
}

for target_name, pollution_cost in pairs(shared.required_pollution) do
  local target = get_target_prototype(target_name)
  if target then
    local entity = util.copy(base_machine)
    entity.name = growth_node_prefix .. target_name
    entity.localised_name = {"entity-name." .. shared.growth_node}
    entity.localised_description = {"", {"entity-name." .. target_name}, " ", {"growth-node-description"}}
    entity.icons =
    {
      {
        icon = spawner.icon,
        icon_size = spawner.icon_size,
        tint = {r = 0.55, g = 1, b = 0.55}
      }
    }
    entity.flags = {"player-creation", "not-blueprintable"}
    entity.max_health = math.max(20, math.floor((target.max_health or 50) * 0.5))
    entity.corpse = nil
    entity.dying_explosion = target.dying_explosion or spawner.dying_explosion
    entity.collision_box = util.copy(target.collision_box) or {{-0.48, -0.48}, {0.48, 0.48}}
    entity.selection_box = util.copy(target.selection_box) or entity.collision_box
    entity.collision_mask = util.copy(target.collision_mask) or util.mask({"water-tile", "player-layer", "train-layer"})
    entity.alert_when_damaged = false
    entity.allow_copy_paste = false
    entity.selectable_in_game = true
    entity.minable = nil
    entity.destructible = true
    entity.fast_replaceable_group = nil
    entity.next_upgrade = nil
    entity.fluid_boxes_off_when_no_fluid_recipe = true
    entity.crafting_categories = {shared.growth_node}
    entity.crafting_speed = 1
    entity.energy_source = {type = "void"}
    entity.energy_usage = "1W"
    entity.ingredient_count = 1
    entity.module_slots = 0
    entity.allowed_effects = {}
    entity.open_sound = nil
    entity.close_sound = nil
    entity.vehicle_impact_sound = nil
    entity.working_sound = nil
    entity.icon_draw_specification = {scale = 0}
    entity.circuit_connector = nil
    entity.circuit_wire_max_distance = 0
    entity.default_recipe_finished_signal = nil
    entity.draw_entity_info_icon_background = false
    entity.return_ingredients_on_change = false
    entity.show_recipe_icon = false
    entity.show_recipe_icon_on_map = false
    entity.operable = true
    entity.graphics_set =
    {
      animation = util.copy(spawner_animation)
    }
    entities[#entities + 1] = entity

    recipes[#recipes + 1] =
    {
      type = "recipe",
      name = growth_recipe_prefix .. target_name,
      localised_name = {"entity-name." .. target_name},
      hidden = true,
      enabled = false,
      allow_as_intermediate = false,
      allow_decomposition = false,
      category = shared.growth_node,
      ingredients = {{type = "item", name = growth_progress_item_name, amount = pollution_cost * shared.pollution_cost_multiplier}},
      results = {{type = "item", name = growth_progress_item_name, amount = 1}},
      energy_required = 1
    }
  end
end

data:extend({category, growth_progress_item})
data:extend(entities)
data:extend(recipes)
