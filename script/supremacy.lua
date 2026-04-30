-- Hive Supremacy: while researched, anything standing on hive creep that isn't
-- on the hive force or a vanilla biter/spitter/spawner/worm takes damage.
--
-- 0.9.0 architecture:
--   * Damage cadence:   shared.intervals.supremacy = 60 ticks (1s).
--   * Candidate scan:   shared.supremacy.candidate_scan = 600 ticks per hive.
--
--   Each hive owns a candidate cache:
--     state.supremacy_candidates[hive_unit_number] = {
--       last_scan_tick = uint?,
--       entries        = { [entity_unit_number] = { entity, lifetime_seconds,
--                                                   is_tree, pollution_burst } }
--     }
--
--   Damage tick walks the cache, drops invalid entries, applies per-tick damage,
--   and releases the tree pollution burst on kill. No per-entity `surface.get_tile`
--   call — the cache filters to in-creep entities at scan time and accepts the
--   small false-positive rate (an entity can move onto natural terrain mid-cycle;
--   that's tolerable because the next 600t scan replaces the cache).
--
--   Hive nodes share the supremacy coverage via a separate cache key indexed
--   by the node's unit_number.
--
-- Force filter `{player, neutral}` excludes hive force and enemy force from
-- find_entities_filtered, so hive-side entities and vanilla biters never appear.

local shared    = require("shared")
local Hive      = require("script.hive")
local Force     = require("script.force")
local State     = require("script.state")
local Telemetry = require("script.telemetry")

local M = {}

local SCAN_FORCES = {"player", "neutral"}
local SKIP_TYPE = {
  ["character"]          = true,
  ["corpse"]             = true,
  ["resource"]           = true,
  ["fish"]               = true,
  ["item-entity"]        = true,
  ["entity-ghost"]       = true,
  ["tile-ghost"]         = true,
  ["highlight-box"]      = true,
  ["flying-text"]        = true,
  ["smoke"]              = true,
  ["smoke-with-trigger"] = true,
  ["sticker"]            = true,
  ["particle"]           = true,
  ["explosion"]          = true,
  ["construction-robot"] = true,
  ["logistic-robot"]     = true,
  ["spider-leg"]         = true,
  -- Decorative scenery and cliffs are genuinely indestructible.
  -- simple-entity (rocks) is intentionally NOT here so rocks DO take damage;
  -- safe_max_health filters out the truly-no-health variants.
  ["decorative"]         = true,
  ["cliff"]              = true
}

-- Read max_health from an entity safely. Returns nil for entities whose
-- prototype doesn't expose the key (rocks, decoratives, anything with a
-- non-health LuaEntityPrototype variant on this engine).
local function safe_max_health(entity)
  local proto = entity.prototype
  if proto then
    local ok, h = pcall(function() return proto.max_health end)
    if ok and h and h > 0 then return h end
  end
  if entity.health and entity.health > 0 then return entity.health end
  return nil
end

local function tree_pollution_amount(entity)
  local proto = entity.prototype
  if not proto then return shared.supremacy.tree_pollution_default end
  local raw = proto.emissions_per_second
  if type(raw) == "table" then
    local total = 0
    for _, v in pairs(raw) do total = total + (tonumber(v) or 0) end
    if total > 0 then return total end
  elseif type(raw) == "number" and raw ~= 0 then
    return math.abs(raw) > 0 and (math.abs(raw) * 60) or shared.supremacy.tree_pollution_default
  end
  return shared.supremacy.tree_pollution_default
end

local function damage_per_tick(max_health, lifetime_seconds)
  if max_health <= 0 then max_health = 50 end
  if lifetime_seconds <= 0 then return max_health end
  -- Convert "lifetime in seconds" to "damage per supremacy tick".
  local ticks_per_call = shared.intervals.supremacy
  local calls_per_second = 60 / ticks_per_call
  local total_calls = lifetime_seconds * calls_per_second
  return max_health / total_calls
end

-- ── Cache helpers ───────────────────────────────────────────────────────────

local function cache_root()
  local s = State.get()
  s.supremacy_candidates = s.supremacy_candidates or {}
  return s.supremacy_candidates
end

local function cache_for_member(unit_number)
  local root = cache_root()
  local rec  = root[unit_number]
  if not rec then
    rec = { last_scan_tick = nil, entries = {} }
    root[unit_number] = rec
  end
  return rec
end

local function rebuild_cache(member, range, hive_force, now)
  local rec = cache_for_member(member.unit_number)
  rec.last_scan_tick = now
  rec.entries = rec.entries or {}

  local x, y = member.position.x, member.position.y
  local area = {{x - range, y - range}, {x + range, y + range}}
  local surface = member.surface
  if not (surface and surface.valid) then return end

  Telemetry.bump_supremacy("rebuild_calls")
  Telemetry.bump_op("find")

  -- Build a dedup set of entities already in the cache so we DON'T reset
  -- their added_tick. Previously the entire entries table was wiped here
  -- every 600 ticks; trees that should have died at 30s kept getting their
  -- timer reset to 0 every 10s and never expired. Drop dead entries while
  -- we walk so the cache also self-prunes.
  local in_cache = {}
  for i = #rec.entries, 1, -1 do
    local e = rec.entries[i]
    if e and e.entity and e.entity.valid then
      in_cache[e.entity.unit_number or e.entity] = true
    else
      table.remove(rec.entries, i)
    end
  end

  local found = surface.find_entities_filtered{ area = area, force = SCAN_FORCES }
  if not found or #found == 0 then return end

  local creep_name = shared.creep_tile
  local added = 0

  for _, entity in ipairs(found) do
    if entity.valid and not SKIP_TYPE[entity.type] then
      local key = entity.unit_number or entity
      if not in_cache[key] then
        local max_hp = safe_max_health(entity)
        if max_hp then
          local pos  = entity.position
          local tile = surface.get_tile(pos.x, pos.y)
          if tile and tile.valid and tile.name == creep_name then
            local is_tree = entity.type == "tree"
            local lifetime = is_tree and shared.supremacy.tree_lifetime
                                      or shared.supremacy.building_lifetime
            rec.entries[#rec.entries + 1] = {
              entity           = entity,
              is_tree          = is_tree,
              max_hp           = max_hp,
              pollution_burst  = is_tree and tree_pollution_amount(entity) or 0,
              added_tick       = now,
              expires_tick     = now + lifetime * 60
            }
            in_cache[key] = true
            added = added + 1
          else
            Telemetry.bump_supremacy("on_creep_skip")
          end
        else
          Telemetry.bump_supremacy("no_unit_number")
        end
      end
    end
  end

  Telemetry.bump_supremacy("rebuild_added", added)
end

-- Wither cache entries by writing entity.health directly. Bypasses the entire
-- damage-resistance pipeline and tree health regeneration, both of which
-- previously stalled trees at low HP forever. On expiry the entity is
-- entity.die()-finished so the on_died handlers (and our pollution burst on
-- trees) still fire.
local function damage_cache(rec, hive_force)
  if not rec or not rec.entries then return end
  local now = game.tick
  for i = #rec.entries, 1, -1 do
    local e = rec.entries[i]
    local entity = e and e.entity
    if not (entity and entity.valid) then
      table.remove(rec.entries, i)
    elseif not e.expires_tick or not e.max_hp then
      -- Cache entry written by an older mod version (pre-0.9.8 had
      -- dmg_per_tick / lifetime_seconds instead). Drop it; the next
      -- candidate scan rewrites the entry in the new shape.
      table.remove(rec.entries, i)
    else
      Telemetry.bump_supremacy("damage_calls")
      Telemetry.bump_op("damage")
      if now >= e.expires_tick then
        local pre_pos = {x = entity.position.x, y = entity.position.y}
        local surface = entity.surface
        entity.die(hive_force)
        Telemetry.bump_supremacy("damage_killed")
        if e.is_tree and e.pollution_burst > 0 and surface and surface.valid then
          surface.pollute(pre_pos, e.pollution_burst)
        end
        table.remove(rec.entries, i)
      else
        -- Linear visual drain. Direct health write — no resistance, no regen.
        local elapsed = now - e.added_tick
        local total   = e.expires_tick - e.added_tick
        if total > 0 then
          local ratio = 1 - (elapsed / total)
          if ratio < 0 then ratio = 0 end
          local target = e.max_hp * ratio
          if target < 1 then target = 1 end
          if entity.health and entity.health > target then
            entity.health = target
          end
        end
      end
    end
  end
end

-- ── Entry point ─────────────────────────────────────────────────────────────

function M.tick()
  local hive_force = Force.get_hive()
  if not hive_force then return end

  local tech = hive_force.technologies[shared.technologies.hive_supremacy]
  if not tech or not tech.researched then return end

  local now            = game.tick
  local scan_interval  = shared.supremacy.candidate_scan or 600

  -- Walk every member (hives + hive_nodes), refreshing their candidate cache
  -- when due, then applying damage from the cache.
  local members = {}
  for _, hive in pairs(Hive.all()) do
    if hive and hive.valid then
      members[#members + 1] = { entity = hive, range = shared.creep_radius.hive }
    end
  end
  local s = State.get()
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data and node_data.entity
    if node and node.valid then
      members[#members + 1] = { entity = node, range = shared.creep_radius.hive_node }
    end
  end

  -- Drop cache entries for members that no longer exist.
  local root = cache_root()
  for unit_number in pairs(root) do
    local present = false
    for _, m in ipairs(members) do
      if m.entity.unit_number == unit_number then present = true; break end
    end
    if not present then root[unit_number] = nil end
  end

  local total_cache = 0
  for _, m in ipairs(members) do
    local rec = cache_for_member(m.entity.unit_number)
    local last = rec.last_scan_tick
    if not last or (now - last) >= scan_interval then
      rebuild_cache(m.entity, m.range, hive_force, now)
    end
    damage_cache(rec, hive_force)
    if rec.entries then
      total_cache = total_cache + #rec.entries
    end
  end
  Telemetry.set_supremacy("cache_size", total_cache)
end

return M
