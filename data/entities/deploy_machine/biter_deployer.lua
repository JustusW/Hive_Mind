local util = require("__Hive_Mind__/data/tf_util/tf_util")
local machine = util.copy(data.raw["assembling-machine"]["assembling-machine-2"])
local graphics = util.copy(data.raw["unit-spawner"]["biter-spawner"])
local shared = require("shared")
local animations = (graphics.graphics_set and graphics.graphics_set.animations) or graphics.animations

local set_layer_animation_speed = function(layer)
  layer.animation_speed = 0.5 / shared.deployer_speed_modifier
  if layer.hr_version then
    layer.hr_version.animation_speed = 0.5 / shared.deployer_speed_modifier
  end
end

for k, animation in pairs(animations) do
  if animation.layers then
    for k, layer in pairs(animation.layers) do
      set_layer_animation_speed(layer)
    end
  else
    set_layer_animation_speed(animation)
  end
end

local name = names.deployers.biter_deployer
machine.name = name
machine.localised_name = {name}
machine.localised_description = {"requires-pollution", tostring(shared.required_pollution[name] * shared.pollution_cost_multiplier)}
machine.icon = graphics.icon
machine.icon_size = graphics.icon_size
machine.collision_box = util.area({0,0}, 2.5)
machine.selection_box = util.area({0,0}, 2)
machine.crafting_categories = {name}
machine.crafting_speed = shared.deployer_speed_modifier
machine.ingredient_count = 100
machine.module_specification = nil
machine.minable = {result = name, mining_time = 5}
machine.flags = {--[["placeable-off-grid",]] "placeable-neutral", "player-creation", "no-automated-item-removal"}
machine.is_deployer = true
machine.next_upgrade = nil
machine.dying_sound = graphics.dying_sound
machine.corpse = graphics.corpse
--machine.dying_explosion = graphics.dying_explosion
machine.collision_mask = util.mask({"water-tile", "player-layer", "train-layer"})

machine.open_sound =
{
  {filename = "__base__/sound/creatures/worm-standup-small-1.ogg"},
  {filename = "__base__/sound/creatures/worm-standup-small-2.ogg"},
  {filename = "__base__/sound/creatures/worm-standup-small-3.ogg"},
}
machine.close_sound =
{
  {filename = "__base__/sound/creatures/worm-folding-1.ogg"},
  {filename = "__base__/sound/creatures/worm-folding-2.ogg"},
  {filename = "__base__/sound/creatures/worm-folding-3.ogg"},
}

machine.graphics_set = machine.graphics_set or {}
machine.graphics_set.always_draw_idle_animation = true
machine.graphics_set.animation =
{
  north = animations[1],
  east = animations[2],
  south = animations[3],
  west = animations[4],
}
machine.animation = nil
machine.working_sound = graphics.working_sound
machine.fluid_boxes =
{
  {
    production_type = "output",
    pipe_picture = nil,
    pipe_covers = nil,
    volume = 1000,
    pipe_connections = {{ flow_direction = "output", direction = defines.direction.north, position = {0, -2} }},
  },
}
machine.fluid_boxes_off_when_no_fluid_recipe = false
machine.energy_source = {type = "void"}
machine.create_ghost_on_death = false
machine.friendly_map_color = {g = 1}

local item = {
  type = "item",
  name = name,
  localised_name = {name},
  localised_description = machine.localised_description,
  icon = machine.icon,
  icon_size = machine.icon_size,
  flags = {},
  subgroup = name,
  order = "aa-"..name,
  place_result = name,
  stack_size = 50
}

local category = {
  type = "recipe-category",
  name = name
}

local subgroup =
{
  type = "item-subgroup",
  name = name,
  group = "enemies",
  order = "b"
}
--[[

  local recipe = {
    type = "recipe",
    name = name,
    localised_name = name,
    enabled = true,
    ingredients =
    {
      {names.items.biological_structure, 120},
    },
    energy_required = 100,
    result = name
  }

  ]]


data:extend
{
  machine,
  item,
  category,
  subgroup,
  --recipe
}
