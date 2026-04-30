local shared = {}

shared.force_name = "hivemind"
shared.permission_group = "hm-hive-director"
shared.creature_item_prefix = "hm-creature-"

shared.gui =
{
  join_button   = "hm-join-hive-button",
  reject_button = "hm-reject-hive-button"
}

-- Worm tier list, ordered small -> behemoth. Each tier produces a player item,
-- a ghost-proxy entity, and a tech that unlocks the recipe.
shared.worm_tiers = {"small", "medium", "big", "behemoth"}

local function worm_real(tier)  return tier .. "-worm-turret" end
local function worm_item(tier)  return "hm-" .. tier .. "-worm" end
local function worm_ghost(tier) return "hm-" .. tier .. "-worm-ghost" end
local function worm_recipe(tier) return "hm-" .. tier .. "-worm" end
local function worm_tech(tier)  return "hm-worms-" .. tier end

shared.entities =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab",
  hive_storage = "hm-hive-storage",
  hive_worker = "hm-hive-worker",
  pollution_generator = "hm-pollution-generator",
  spawner_ghost = "hm-spawner-ghost",
  spitter_spawner_ghost = "hm-spitter-spawner-ghost"
}

shared.items =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab",
  hive_spawner = "hm-biter-spawner",
  hive_spitter_spawner = "hm-spitter-spawner",
  pheromones = "hm-pheromones",
  pollution = "hm-pollution",
  pollution_science_pack = "hm-pollution-science-pack",
  pollution_generator = "hm-pollution-generator"
}

shared.recipes =
{
  hive = "hm-hive",
  hive_node = "hm-hive-node",
  hive_lab = "hm-hive-lab",
  hive_spawner = "hm-biter-spawner",
  hive_spitter_spawner = "hm-spitter-spawner",
  pheromones_on = "hm-pheromones-on",
  pheromones_off = "hm-pheromones-off",
  pollution_generator = "hm-pollution-generator"
}

shared.technologies =
{
  hive_spawners = "hm-hive-spawners",
  hive_labs = "hm-hive-labs",
  worms_small = "hm-worms-small",
  worms_medium = "hm-worms-medium",
  worms_big = "hm-worms-big",
  worms_behemoth = "hm-worms-behemoth",
  attraction_reach = "hm-attraction-reach",
  hive_supremacy = "hm-hive-supremacy"
}

-- Infinite attraction-reach tech: each level adds this fraction to the
-- recruitment radius, applied additively (level N => radius * (1 + N * step)).
shared.attraction_reach_step = 0.1

-- Helpers + per-tier name lookups for worms.
shared.worm = {}
for _, tier in pairs(shared.worm_tiers) do
  shared.worm[tier] =
  {
    real   = worm_real(tier),
    item   = worm_item(tier),
    ghost  = worm_ghost(tier),
    recipe = worm_recipe(tier),
    tech   = worm_tech(tier)
  }
end

-- Construction radius and recruitment radius are now distinct concepts.
-- `hive` and `hive_node` are construction / visibility radii (used by roboport
-- prototype + chart_area). `recruit` is the long-range scan for absorbable units.
-- All values are radii (half-extents). A radius of 50 gives a 100x100 box.
-- Each hive and each hive node also recruits within its own range, scaled
-- by the hm-attraction-reach tech (see script/creatures.lua).
shared.ranges =
{
  hive      = 50,    -- 100x100 build / visibility / recruit box
  hive_node = 25     -- 50x50  build / visibility / recruit box
}

shared.intervals =
{
  recruit   = 120,
  absorb    = 30,
  supply    = 60,
  workers   = 6,    -- ghost-fulfilment dispatcher
  creep     = 3,
  labels    = 30,   -- pollution-display refresh on each hive
  loadout   = 60,   -- inventory + quickbar watchdog for hive directors
  supremacy = 60,   -- creep-damage scan once per second
  scan      = 60    -- unified per-hive scan + telemetry flush cadence (0.9.0)
}

-- Maximum simultaneously-in-flight workers per hive. Workers are spawned on
-- demand by the dispatcher; exceeding this would queue jobs. There is no
-- "stocked" worker pool — workers don't exist until the dispatcher needs one.
shared.hive_workers_per_hive = 5
-- Distance (tiles) at which a worker is considered to have arrived at its
-- target ghost.
shared.workers_arrival_radius = 2
-- Ticks before a worker that hasn't reached its target is abandoned and the
-- job is requeued. ~60s at 60 UPS.
shared.workers_timeout_ticks = 60 * 60
-- Maximum requeue attempts before we give up on a ghost (its cost stays
-- charged; the ghost is destroyed silently so the queue doesn't spin).
shared.workers_max_attempts = 3

-- Pollution cost to build hive-tier structures via ghost placement.
-- Anything not listed here uses the recipe-derived formula in script/main.lua.
shared.build_costs =
{
  [shared.entities.hive_node]            = 100,
  [shared.entities.hive_lab]             = 150,
  [shared.entities.spawner_ghost]        = 500,
  [shared.entities.spitter_spawner_ghost] = 500
}
for _, tier in pairs(shared.worm_tiers) do
  -- Cost ramps small -> behemoth. Tunable.
  local tier_cost = ({small = 200, medium = 350, big = 600, behemoth = 1000})[tier]
  shared.build_costs[shared.worm[tier].ghost] = tier_cost
end

-- Maps ghost / proxy entity name -> player-facing item name when they differ.
shared.ghost_items =
{
  [shared.entities.spawner_ghost]         = shared.items.hive_spawner,
  [shared.entities.spitter_spawner_ghost] = shared.items.hive_spitter_spawner
}
for _, tier in pairs(shared.worm_tiers) do
  shared.ghost_items[shared.worm[tier].ghost] = shared.worm[tier].item
end

-- Per-item pollution factor used by the recipe-derived cost formula.
-- Unknown items fall through to `default_item_pollution_factor`.
shared.item_pollution_factors =
{
  ["wood"]                      = 1,
  ["coal"]                      = 1,
  ["stone"]                     = 1,
  ["iron-ore"]                  = 1,
  ["copper-ore"]                = 1,
  ["iron-plate"]                = 1,
  ["copper-plate"]              = 1,
  ["steel-plate"]               = 5,
  ["iron-stick"]                = 1,
  ["iron-gear-wheel"]           = 2,
  ["copper-cable"]              = 1,
  ["electronic-circuit"]        = 5,
  ["advanced-circuit"]          = 15,
  ["processing-unit"]           = 50,
  ["plastic-bar"]               = 3,
  ["sulfur"]                    = 2,
  ["battery"]                   = 5,
  ["explosives"]                = 5,
  ["pipe"]                      = 1,
  ["engine-unit"]               = 10,
  ["electric-engine-unit"]      = 25,
  ["flying-robot-frame"]        = 50,
  ["low-density-structure"]     = 30,
  ["lubricant"]                 = 1,
  ["water"]                     = 0,
  ["concrete"]                  = 1,
  ["refined-concrete"]          = 2,
  ["stone-brick"]               = 1
}
shared.default_item_pollution_factor = 2
shared.fallback_build_cost = 100

-- Debug pollution generator: emits equivalent of 1000 active coal miners.
shared.pollution_generator_per_tick = 10000 / 3600

shared.science =
{
  pollution_per_pack = 25
}

-- Hive Supremacy: damage applied to non-hive entities standing on creep,
-- once researched. Lifetimes in seconds (the scan runs every
-- shared.intervals.supremacy ticks); damage per tick is computed from each
-- entity's max_health so a tree dies in ~tree_lifetime seconds and a building
-- in ~building_lifetime seconds regardless of prototype hp.
shared.supremacy =
{
  tree_lifetime         = 30,
  building_lifetime     = 60,
  -- Pollution burst released into the world when a tree dies on creep, used
  -- as a fallback when the tree prototype lacks emissions / pollution data.
  tree_pollution_default = 50,
  -- Tech research cost (Pollution Science Packs).
  research_packs        = 200,
  -- Candidate cache rebuild cadence (ticks per hive). Damage tick still runs
  -- every shared.intervals.supremacy ticks, but the candidate find is amortised
  -- across this much wider window — most ticks are pure cache walk + damage.
  candidate_scan        = 600
}

shared.creep_tile = "hm-creep"

-- Creep matches build/visibility: hive 100x100 box, hive_node 50x50.
shared.creep_radius =
{
  hive      = 50,
  hive_node = 25
}

-- Placement attempts per creep call (every shared.intervals.creep ticks).
-- Each attempt picks a random direction + radius; failed attempts (already
-- creep, water, void) are silently dropped.
shared.creep_tiles_per_call =
{
  hive      = 12,
  hive_node = 4
}

shared.creature_roles =
{
  attract = "attract",
  store = "store",
  consume = "consume"
}

function shared.creature_item_name(unit_name)
  return shared.creature_item_prefix .. unit_name
end

function shared.creature_unit_name(item_name)
  if type(item_name) ~= "string" then return nil end
  if item_name:sub(1, #shared.creature_item_prefix) ~= shared.creature_item_prefix then return nil end
  return item_name:sub(#shared.creature_item_prefix + 1)
end

-- True if the given tile name is the mod's creep tile.
function shared.is_creep_tile(tile_name)
  return tile_name == shared.creep_tile
end

return shared
