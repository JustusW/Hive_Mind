local shared = require("shared")
local space_age_assets = require("data.prototypes.space_age_assets")

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

-- Return a deep-copied Animation from `proto`'s spawner-shaped graphics.
-- Handles both 2.0 (graphics_set.animations) and the older (animations)
-- prototype shapes, and picks the first variant.
local function animation_from(proto)
  local source = (proto.graphics_set and proto.graphics_set.animations)
              or proto.animations
  if source and source[1] then return table.deepcopy(source[1]) end
  return table.deepcopy(source)
end

local function spawner_animation()
  return animation_from(spawner_proto)
end

-- Recursively multiply the `scale` field of every leaf in a sprite tree.
-- Mirrors tint_sprite's traversal so all the same shapes are covered.
local function rescale_sprite(t, factor)
  if type(t) ~= "table" then return end
  if t.scale then t.scale = t.scale * factor end
  if t.hr_version then rescale_sprite(t.hr_version, factor) end
  if t.layers then for _, l in pairs(t.layers) do rescale_sprite(l, factor) end end
  if t.sheets then for _, s in pairs(t.sheets) do rescale_sprite(s, factor) end end
  if t.sheet  then rescale_sprite(t.sheet, factor) end
  for _, dir in pairs{"north","south","east","west"} do
    if t[dir] then rescale_sprite(t[dir], factor) end
  end
end

local function tinted_spawner_anim(tint)
  local anim = spawner_animation()
  tint_sprite(anim, tint)
  return anim
end

-- Optionally rescaled animation for the hive (egg raft). Uses vendored Space
-- Age art in its original colors so the hive looks the same without a Space
-- Age dependency.
local function gleba_spawner_anim(scale)
  local anim = space_age_assets.gleba_spawner_animation()
  if scale and scale ~= 1 then rescale_sprite(anim, scale) end
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

-- ── Hive ─────────────────────────────────────────────────────────────────────
-- Roboport mechanics. Visual: scaled-up egg raft (gleba-spawner).

local hive = table.deepcopy(roboport_proto)
hive.name                  = shared.entities.hive
hive.localised_name        = {"entity-name."        .. shared.entities.hive}
hive.localised_description = {"entity-description." .. shared.entities.hive}
hive.minable               = {mining_time = 0.5, result = shared.items.hive}
hive.max_health            = 2000
hive.logistics_radius      = shared.ranges.hive
hive.construction_radius   = shared.ranges.hive
-- The hive is shaped like a roboport for its construction-radius / charting
-- behaviour, but it does not run a logistic-bot pipeline. Workers are units
-- spawned on demand by the dispatcher (see script/workers.lua).
hive.robot_slots_count     = 0
hive.material_slots_count  = 0
hive.energy_source         = {type = "void"}
hive.energy_usage          = "1W"
hive.charging_energy       = "10MW"
hive.recharge_minimum      = "1MJ"
hive.icon                  = space_age_assets.gleba_spawner_icon
hive.icon_size             = space_age_assets.icon_size
hive.icons                 = nil
-- Sprite swap: hide every roboport-shaped visual, then overlay a scaled-up
-- egg raft (gleba-spawner). 2× scale gives a sprite that visibly
-- dominates the 4×4 roboport footprint without poking past the construction
-- ring.
hide_sprite(hive.base)
hide_sprite(hive.base_patch)
hide_sprite(hive.door_animation_up)
hide_sprite(hive.door_animation_down)
hide_sprite(hive.recharging_animation)
hive.recharging_light      = nil
hive.base_animation        = gleba_spawner_anim(2.0)

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
hive_node.icon                  = space_age_assets.gleba_spawner_small_icon
hive_node.icon_size             = space_age_assets.icon_size
hive_node.icons                 = nil
hide_sprite(hive_node.base)
hide_sprite(hive_node.base_patch)
hide_sprite(hive_node.door_animation_up)
hide_sprite(hive_node.door_animation_down)
hide_sprite(hive_node.recharging_animation)
hive_node.recharging_light      = nil
hive_node.base_animation        = space_age_assets.gleba_spawner_small_animation()

-- ── Pheromone Vent ───────────────────────────────────────────────────────────
-- A recoloured Hive Node that diverts the network's incoming biter stream to
-- itself, gathers biters, and dispatches them as an autonomous attack group.
-- No creep growth, no recruitment range, no storage, no construction zone.
-- Buildable anywhere; build flow charges no pollution and skips placement-
-- zone checks.

local pheromone_vent_tint = {r = 0.85, g = 0.10, b = 0.10, a = 1}

local pheromone_vent = table.deepcopy(roboport_proto)
pheromone_vent.name                  = shared.entities.pheromone_vent
pheromone_vent.localised_name        = {"entity-name."        .. shared.entities.pheromone_vent}
pheromone_vent.localised_description = {"entity-description." .. shared.entities.pheromone_vent}
pheromone_vent.minable               = nil
pheromone_vent.max_health            = 1000
pheromone_vent.logistics_radius      = 0
pheromone_vent.construction_radius   = 0
pheromone_vent.robot_slots_count     = 0
pheromone_vent.material_slots_count  = 0
pheromone_vent.energy_source         = {type = "void"}
pheromone_vent.energy_usage          = "1W"
pheromone_vent.charging_energy       = "1MW"
pheromone_vent.recharge_minimum      = "1MJ"
pheromone_vent.icon                  = space_age_assets.gleba_spawner_small_icon
pheromone_vent.icon_size             = space_age_assets.icon_size
pheromone_vent.icons                 = nil
hide_sprite(pheromone_vent.base)
hide_sprite(pheromone_vent.base_patch)
hide_sprite(pheromone_vent.door_animation_up)
hide_sprite(pheromone_vent.door_animation_down)
hide_sprite(pheromone_vent.recharging_animation)
pheromone_vent.recharging_light      = nil
do
  local anim = space_age_assets.gleba_spawner_small_animation()
  tint_sprite(anim, pheromone_vent_tint)
  pheromone_vent.base_animation      = anim
end

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
hive_lab.icon                  = space_age_assets.biolab_icon
hive_lab.icon_size             = space_age_assets.icon_size
hive_lab.icons                 = nil
hive_lab.on_animation          = space_age_assets.biolab_on_animation()
hive_lab.off_animation         = space_age_assets.biolab_off_animation()
hive_lab.entity_info_icon_shift = nil
if hive_lab.working_visualisations then hive_lab.working_visualisations = nil end
if hive_lab.light                  then hive_lab.light = nil end

-- ── Hive Worker ───────────────────────────────────────────────────────────────
-- A unit commanded by the script-side dispatcher in script/workers.lua. It
-- walks to a ghost, materialises it, and dies on arrival. No flying, no
-- logistic-bot AI — just a unit with go_to_location commands, so pathfinding
-- and animation are handled by the engine.
--
-- Behaviour comes from the real Space Age small wriggler when present, falling
-- back to a base unit when Space Age is not loaded. Visuals/sounds are vendored
-- so the worker still looks like a wriggler in base-only profiles.
local worker_base = data.raw["unit"]["small-wriggler-pentapod"]
                 or data.raw["unit"]["small-biter"]

local hive_worker = table.deepcopy(worker_base)
hive_worker.name                    = shared.entities.hive_worker
hive_worker.localised_name          = {"entity-name."        .. shared.entities.hive_worker}
hive_worker.localised_description   = {"entity-description." .. shared.entities.hive_worker}
hive_worker.minable                 = nil
hive_worker.max_health              = 100
hive_worker.movement_speed          = (hive_worker.movement_speed or 0.05) * 1.5
hive_worker.distraction_cooldown    = 0
hive_worker.pollution_to_join_attack = nil
hive_worker.spawning_time_modifier  = nil
space_age_assets.apply_wriggler_unit(hive_worker)

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
-- Build.on_built handler swaps each proxy for the real entity.
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

-- Spitter spawner proxy: shaped like the biter spawner ghost (so the build
-- footprint matches the eventual real entity) but tinted lime to read as
-- "spitter" at a glance during the brief proxy phase before the swap.
local col_spitter = {r = 0.45, g = 0.85, b = 0.20, a = 1}
local spitter_spawner_ghost = make_proxy(
  shared.entities.spitter_spawner_ghost,
  col_spitter,
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
  hive_worker, hive_storage, pollution_gen,
  spawner_ghost, spitter_spawner_ghost,
  pheromone_vent
}
for _, w in pairs(worm_proxies) do
  entities[#entities + 1] = w
end

data:extend(entities)
