local shared = require("shared")

-- ── Sprite helpers ────────────────────────────────────────────────────────────

-- Recursively apply `tint` to every filename-bearing leaf in a sprite/animation
-- table.  Handles layers, sheets, hr_version, and Sprite4Way style tables.
local function tint_sprite(t, tint)
  if type(t) ~= "table" then return end
  if t.filename or t.filenames then
    t.tint = tint
  end
  if t.hr_version then tint_sprite(t.hr_version, tint) end
  if t.layers then for _, l in pairs(t.layers) do tint_sprite(l, tint) end end
  if t.sheets then for _, s in pairs(t.sheets) do tint_sprite(s, tint) end end
  if t.sheet  then tint_sprite(t.sheet, tint) end
  for _, dir in pairs{"north","south","east","west"} do
    if t[dir] then tint_sprite(t[dir], tint) end
  end
end

-- Hide any sprite/animation field by tinting all leaves fully transparent.
-- Keeps the field shape valid so prototype validation passes.
local invisible_tint = {r = 0, g = 0, b = 0, a = 0}
local function hide_sprite(t)
  tint_sprite(t, invisible_tint)
end

-- ── Source prototypes ─────────────────────────────────────────────────────────

local spawner_proto  = data.raw["unit-spawner"]["biter-spawner"]
local roboport_proto = data.raw["roboport"]["roboport"]
local lab_proto      = data.raw["lab"]["lab"]
local chest_proto    = data.raw["logistic-container"]["passive-provider-chest"]

-- Return a deep-copied biter-spawner Animation suitable for assignment to any
-- Animation field. Handles both 2.0 (graphics_set.animations) and the older
-- (animations) prototype shapes.
local function spawner_animation()
  local source = (spawner_proto.graphics_set and spawner_proto.graphics_set.animations)
              or spawner_proto.animations
  -- AnimationVariations is an array of Animations. Take the first variant.
  if source and source[1] then return table.deepcopy(source[1]) end
  return table.deepcopy(source)
end

local function tinted_spawner_anim(tint)
  local anim = spawner_animation()
  tint_sprite(anim, tint)
  return anim
end

-- Same animation but expressed as a Sprite (no animation cycle). Used for
-- prototypes whose required visual field is a static Sprite.
local function spawner_sprite(tint)
  -- An Animation can be coerced to a Sprite by pointing at the first frame
  -- only. The simplest reliable way is to deep-copy the animation and force
  -- frame_count = 1.
  local sprite = spawner_animation()
  sprite.frame_count = 1
  if sprite.layers then
    for _, layer in pairs(sprite.layers) do
      layer.frame_count = 1
    end
  end
  if tint then tint_sprite(sprite, tint) end
  return sprite
end

-- Colours.
local col_hive = {r = 0.90, g = 0.35, b = 0.05, a = 1}
local col_node = {r = 0.10, g = 0.75, b = 0.45, a = 1}
local col_lab  = {r = 0.55, g = 0.10, b = 0.85, a = 1}

-- ── Hive ─────────────────────────────────────────────────────────────────────
-- Roboport mechanics. Visual: tinted biter-spawner.

local hive = table.deepcopy(roboport_proto)
hive.name                  = shared.entities.hive
hive.localised_name        = {"entity-name."        .. shared.entities.hive}
hive.localised_description = {"entity-description." .. shared.entities.hive}
hive.minable               = {mining_time = 0.5, result = shared.items.hive}
hive.max_health            = 2000
hive.logistics_radius      = shared.ranges.hive
hive.construction_radius   = shared.ranges.hive
hive.robot_slots_count     = shared.hive_robot_count
hive.material_slots_count  = 200
hive.energy_source         = {type = "void"}
hive.energy_usage          = "1W"
hive.charging_energy       = "10MW"
hive.recharge_minimum      = "1MJ"
hive.icon                  = spawner_proto.icon
hive.icon_size             = spawner_proto.icon_size
hive.icons                 = nil
-- Sprite swap: hide every roboport-shaped visual, then overlay a tinted spawner.
hide_sprite(hive.base)
hide_sprite(hive.base_patch)
hide_sprite(hive.door_animation_up)
hide_sprite(hive.door_animation_down)
hide_sprite(hive.recharging_animation)
hive.recharging_light      = nil
hive.base_animation        = tinted_spawner_anim(col_hive)

-- ── Hive Node ─────────────────────────────────────────────────────────────────

local hive_node = table.deepcopy(roboport_proto)
hive_node.name                  = shared.entities.hive_node
hive_node.localised_name        = {"entity-name."        .. shared.entities.hive_node}
hive_node.localised_description = {"entity-description." .. shared.entities.hive_node}
hive_node.minable               = {mining_time = 0.5, result = shared.items.hive_node}
hive_node.max_health            = 1000
hive_node.logistics_radius      = shared.ranges.hive_node
hive_node.construction_radius   = shared.ranges.hive_node
hive_node.robot_slots_count     = 0
hive_node.material_slots_count  = 0
hive_node.energy_source         = {type = "void"}
hive_node.energy_usage          = "1W"
hive_node.charging_energy       = "1MW"
hive_node.recharge_minimum      = "1MJ"
hive_node.icon                  = spawner_proto.icon
hive_node.icon_size             = spawner_proto.icon_size
hive_node.icons                 = nil
hide_sprite(hive_node.base)
hide_sprite(hive_node.base_patch)
hide_sprite(hive_node.door_animation_up)
hide_sprite(hive_node.door_animation_down)
hide_sprite(hive_node.recharging_animation)
hive_node.recharging_light      = nil
hive_node.base_animation        = tinted_spawner_anim(col_node)

-- ── Hive Lab ──────────────────────────────────────────────────────────────────

local hive_lab = table.deepcopy(lab_proto)
hive_lab.name                  = shared.entities.hive_lab
hive_lab.localised_name        = {"entity-name."        .. shared.entities.hive_lab}
hive_lab.localised_description = {"entity-description." .. shared.entities.hive_lab}
hive_lab.minable               = {mining_time = 0.5, result = shared.items.hive_lab}
hive_lab.inputs                = {shared.items.pollution_science_pack}
hive_lab.energy_source         = {type = "void"}
hive_lab.energy_usage          = "1W"
hive_lab.researching_speed     = 1
hive_lab.icon                  = spawner_proto.icon
hive_lab.icon_size             = spawner_proto.icon_size
hive_lab.icons                 = nil
hive_lab.on_animation          = tinted_spawner_anim(col_lab)
hive_lab.off_animation         = tinted_spawner_anim(col_lab)
hive_lab.entity_info_icon_shift = nil
if hive_lab.working_visualisations then hive_lab.working_visualisations = nil end
if hive_lab.light                  then hive_lab.light = nil end

-- ── Construction Robot (visible biter) ────────────────────────────────────────

local biter_scale = 0.25
local biter_anim =
{
  filenames =
  {
    "__base__/graphics/entity/biter/biter-run-1.png",
    "__base__/graphics/entity/biter/biter-run-2.png",
    "__base__/graphics/entity/biter/biter-run-3.png",
    "__base__/graphics/entity/biter/biter-run-4.png"
  },
  width           = 398,
  height          = 310,
  shift           = {-1/32, -5/32},
  line_length     = 8,
  lines_per_file  = 8,
  frame_count     = 16,
  direction_count = 16,
  scale           = biter_scale,
  allow_forced_downscale = true
}
local biter_shadow =
{
  filenames =
  {
    "__base__/graphics/entity/biter/biter-run-shadow-1.png",
    "__base__/graphics/entity/biter/biter-run-shadow-2.png",
    "__base__/graphics/entity/biter/biter-run-shadow-3.png",
    "__base__/graphics/entity/biter/biter-run-shadow-4.png"
  },
  width           = 432,
  height          = 292,
  shift           = {8/32, -1/32},
  line_length     = 8,
  lines_per_file  = 8,
  frame_count     = 16,
  direction_count = 16,
  scale           = biter_scale,
  allow_forced_downscale = true,
  draw_as_shadow  = true
}

local construction_robot = table.deepcopy(data.raw["construction-robot"]["construction-robot"])
construction_robot.name                         = shared.entities.construction_robot
construction_robot.localised_name               = {"entity-name."        .. shared.entities.construction_robot}
construction_robot.localised_description        = {"entity-description." .. shared.entities.construction_robot}
construction_robot.minable                      = nil
construction_robot.max_health                   = 10
construction_robot.max_energy                   = "100MJ"
construction_robot.energy_per_move              = "0.001J"
construction_robot.energy_per_tick              = "0J"
construction_robot.speed                        = 0.18
construction_robot.construction_vector          = {0, -0.4}
construction_robot.idle                         = biter_anim
construction_robot.in_motion                    = biter_anim
construction_robot.idle_with_cargo              = biter_anim
construction_robot.in_motion_with_cargo         = biter_anim
construction_robot.working                      = biter_anim
construction_robot.shadow_idle                  = biter_shadow
construction_robot.shadow_in_motion             = biter_shadow
construction_robot.shadow_idle_with_cargo       = biter_shadow
construction_robot.shadow_in_motion_with_cargo  = biter_shadow
construction_robot.shadow_working               = biter_shadow

-- ── Hive Storage Chest (invisible) ────────────────────────────────────────────
-- Functional passive-provider chest placed beside every hive. The visible hive
-- is the spawner-shaped roboport above; this chest renders as nothing so the
-- player only sees one structure per hive.

local hive_storage = table.deepcopy(chest_proto)
hive_storage.name                  = shared.entities.hive_storage
hive_storage.localised_name        = {"entity-name."        .. shared.entities.hive_storage}
hive_storage.localised_description = {"entity-description." .. shared.entities.hive_storage}
hive_storage.minable               = nil
hive_storage.inventory_size        = 200
hive_storage.flags                 = {"not-blueprintable", "not-deconstructable"}
hive_storage.icon                  = spawner_proto.icon
hive_storage.icon_size             = spawner_proto.icon_size
hive_storage.icons                 = nil
if hive_storage.picture   then hide_sprite(hive_storage.picture)   end
if hive_storage.animation then hide_sprite(hive_storage.animation) end
hive_storage.circuit_connector     = nil
hive_storage.circuit_wire_max_distance = 0
hive_storage.selectable_in_game    = true   -- still inspectable by players

-- ── Pollution Generator (debug) ───────────────────────────────────────────────

local pollution_gen = table.deepcopy(data.raw["container"]["iron-chest"])
pollution_gen.name                  = shared.entities.pollution_generator
pollution_gen.localised_name        = {"entity-name."        .. shared.entities.pollution_generator}
pollution_gen.localised_description = {"entity-description." .. shared.entities.pollution_generator}
pollution_gen.minable               = {mining_time = 0.5, result = shared.items.pollution_generator}
pollution_gen.inventory_size        = 1
pollution_gen.icon                  = spawner_proto.icon
pollution_gen.icon_size             = spawner_proto.icon_size
pollution_gen.icons                 = nil
tint_sprite(pollution_gen.picture, {r = 0.9, g = 0.2, b = 0.0, a = 1})

-- ── Spawner / Worm proxy ghosts ───────────────────────────────────────────────
-- god-controller can't place unit-spawner / turret entities directly on the
-- enemy force, so the player's item places a lab-shaped proxy. The script's
-- on_robot_built_entity handler swaps each proxy for the real entity.
--
-- Visually the proxy is a tinted spawner so the build-site briefly looks right
-- before the real entity replaces it.

local function make_proxy(name, color, footprint, selection)
  local proxy = table.deepcopy(lab_proto)
  proxy.name                  = name
  proxy.localised_name        = {"entity-name."        .. name}
  proxy.localised_description = {"entity-description." .. name}
  proxy.minable               = nil
  proxy.flags                 = {"not-deconstructable", "not-rotatable", "placeable-neutral", "player-creation"}
  proxy.collision_box         = footprint
  proxy.selection_box         = selection
  proxy.inputs                = {}
  proxy.energy_source         = {type = "void"}
  proxy.energy_usage          = "1W"
  proxy.icon                  = spawner_proto.icon
  proxy.icon_size             = spawner_proto.icon_size
  proxy.icons                 = nil
  proxy.on_animation          = tinted_spawner_anim(color)
  proxy.off_animation         = tinted_spawner_anim(color)
  if proxy.working_visualisations then proxy.working_visualisations = nil end
  if proxy.light                  then proxy.light = nil end
  return proxy
end

local spawner_ghost = make_proxy(
  shared.entities.spawner_ghost,
  col_hive,
  {{-2.2, -2.2}, {2.2, 2.2}},
  {{-2.5, -2.5}, {2.5, 2.5}}
)

-- Worm proxies — one per tier. Visually distinct purple shades so players can
-- tell which tier they're placing during the brief proxy phase.
local worm_colors =
{
  small    = {r = 0.50, g = 0.20, b = 0.60, a = 1},
  medium   = {r = 0.55, g = 0.10, b = 0.65, a = 1},
  big      = {r = 0.65, g = 0.08, b = 0.75, a = 1},
  behemoth = {r = 0.80, g = 0.05, b = 0.85, a = 1}
}

local worm_proxies = {}
for _, tier in pairs(shared.worm_tiers) do
  local w = shared.worm[tier]
  -- All worm tiers fit roughly the same footprint.
  worm_proxies[#worm_proxies + 1] = make_proxy(
    w.ghost,
    worm_colors[tier],
    {{-1.4, -1.4}, {1.4, 1.4}},
    {{-1.5, -1.5}, {1.5, 1.5}}
  )
end

-- ── Extend ────────────────────────────────────────────────────────────────────

local entities =
{
  hive, hive_node, hive_lab,
  construction_robot, hive_storage, pollution_gen, spawner_ghost
}
for _, w in pairs(worm_proxies) do
  entities[#entities + 1] = w
end

data:extend(entities)
