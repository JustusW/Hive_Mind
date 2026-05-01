-- Anchor placement: starter hive lifecycle.
--
-- The hive force is endless: each player who joined the hive should always
-- have a path back to placing an anchor. Anchor.ensure_hive_available(player)
-- is the single entry point for handing out the hm-hive item; it is
-- idempotent (the player gets at most one item at any moment) and is called
-- from both Director.join (initial grant) and the network-collapse handler
-- (re-grant after the player has lost all their hives).
--
-- Placement starts a 30-second timer (shared.anchor.construction_ticks); the
-- hive is treated as inert until the timer elapses, at which point it locks
-- (entity.minable = false) and goes live (recruitment, creep, recipe
-- auto-unlocks). During construction the player may mine the in-progress
-- hive to refund the item — that's the escape hatch for picking the wrong
-- spot. Once the timer elapses there is no escape: the anchor is permanent
-- for that hive's lifetime. Combat-destroyed anchors trigger network
-- collapse, after which the player gets another hive item via
-- ensure_hive_available.
--
-- State at `state.pending_anchor_constructions[unit_number] = {
--   entity, owner_player_index, deadline_tick }`. Survives save/load — the
-- deadline_tick is absolute against game.tick.
--
-- Wiring:
--   * Anchor.ensure_hive_available(player)            - idempotent item handout
--   * Anchor.start_construction(entity, player_index) - flag + warning message
--   * Anchor.tick()                                   - completes any expired constructions
--   * Anchor.cancel(entity)                           - drop pending record (called on mine/death)
--   * Anchor.is_building(record)                      - hive-storage record query for scan/creep gates

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")
local Safe   = require("script.safe")

local M = {}

-- ── Item handout ───────────────────────────────────────────────────────────

-- True if the player currently has any path to a hive — the item itself, a
-- live hive entity (anchor or promoted), or an in-flight 30s construction.
local function player_has_hive_path(s, player)
  if not (player and player.valid) then return false end

  local inv = player.get_main_inventory()
  if inv and inv.get_item_count(shared.items.hive) > 0 then return true end

  local bucket = s.hives_by_player[player.index]
  if bucket then
    for _, hd in pairs(bucket) do
      if hd.entity and hd.entity.valid then return true end
    end
  end

  for _, record in pairs(s.pending_anchor_constructions) do
    if record.owner_player_index == player.index
       and record.entity and record.entity.valid then
      return true
    end
  end

  return false
end

-- Idempotent: insert exactly one hm-hive item into the player's main
-- inventory only if they have no other path to a hive. Called from
-- Director.join (initial grant) and from the network-collapse handler
-- (re-grant after total wipeout). Safe to call as often as you like.
function M.ensure_hive_available(player)
  if not (player and player.valid) then return end
  local s = State.get()
  if player_has_hive_path(s, player) then return end

  local inv = player.get_main_inventory()
  if inv then
    inv.insert({name = shared.items.hive, count = 1})
  end
end

-- ── Construction lifecycle ─────────────────────────────────────────────────

-- Called from Build.on_built when the player places their starter hive.
-- The hive entity already exists; we flag it as in-construction, schedule the
-- completion deadline, and warn the player. Returns nothing.
function M.start_construction(entity, player_index, hive_record)
  if not (entity and entity.valid and hive_record) then return end

  local deadline = game.tick + (shared.anchor.construction_ticks or (30 * 60))
  hive_record.building_until_tick = deadline

  local s = State.get()
  s.pending_anchor_constructions[entity.unit_number] =
  {
    entity              = entity,
    owner_player_index  = player_index,
    deadline_tick       = deadline
  }

  if player_index then
    local player = game.get_player(player_index)
    if player and player.valid then
      player.print({"message.hm-anchor-construction-started"})
    end
  end
end

-- Drop a pending construction record without doing the lock-in pass. Called
-- when the in-progress entity is mined (refund handled by Build) or destroyed.
function M.cancel(entity_or_unit_number)
  local s = State.get()
  local key = entity_or_unit_number
  if type(key) == "table" and key.unit_number then key = key.unit_number end
  if not key then return end
  s.pending_anchor_constructions[key] = nil
end

-- True if a hive storage record indicates the hive is still in its 30-second
-- construction window. Used by the recruitment scan and creep growth to skip
-- the hive until it goes live.
function M.is_building(hive_record)
  if not hive_record then return false end
  local until_tick = hive_record.building_until_tick
  if not until_tick then return false end
  return game.tick < until_tick
end

-- ── Completion ─────────────────────────────────────────────────────────────

-- Run by main.on_tick. Walks pending records and completes any whose
-- deadline has passed. Cheap (table is small — at most one entry per player
-- in flight, usually zero).
local function complete(entity, hive_record)
  if not (entity and entity.valid) then return end
  if hive_record then hive_record.building_until_tick = nil end
  -- Anchor lock-in: cannot be mined any further. The director permission
  -- group already blocks mining for hive players, so this is a defence in
  -- depth against scripted mining or any future code path that bypasses
  -- the permission gate. Routed through Safe because LuaEntity.minable
  -- is writable in 2.0 but historically had quirks across versions.
  Safe.call("anchor.minable_lock", function() entity.minable = false end)

  -- Trigger the same gameplay-event unlocks the original on_hive_placed
  -- ran at placement time, but now that the hive is "live". Recipe enables
  -- are belt-and-braces alongside Force.configure's tech-driven matrix.
  local force = entity.force
  local tech  = force.technologies[shared.technologies.hive_spawners]
  if tech and not tech.researched then tech.researched = true end
  for _, rname in pairs({
    shared.recipes.hive_node,
    shared.recipes.hive_spawner,
    shared.recipes.hive_spitter_spawner,
    shared.recipes.promote_node
  }) do
    local recipe = force.recipes[rname]
    if recipe then recipe.enabled = true end
  end
end

function M.tick()
  local s = State.get()
  if not s.pending_anchor_constructions then return end

  local now = game.tick
  local to_finish
  for unit_number, record in pairs(s.pending_anchor_constructions) do
    if not (record.entity and record.entity.valid) then
      s.pending_anchor_constructions[unit_number] = nil
    elseif now >= (record.deadline_tick or 0) then
      to_finish = to_finish or {}
      to_finish[#to_finish + 1] = unit_number
    end
  end

  if not to_finish then return end
  for _, unit_number in ipairs(to_finish) do
    local record = s.pending_anchor_constructions[unit_number]
    if record then
      complete(record.entity, Hive.get_storage(record.entity))
      s.pending_anchor_constructions[unit_number] = nil
    end
  end
end

return M
