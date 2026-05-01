-- Spatial network resolver.
--
-- A "network" is the set of hive + hive-node entities whose construction
-- radii overlap, scoped to a single force and surface. Cost reads/writes
-- route through the network's primary chest — the only chest in the network
-- after the storage invariant landed (see design.md → Storage).
--
-- This module is pure spatial + chest-routing logic. Pollution arithmetic
-- and creature-conversion live in cost.lua.

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")

local M = {}

-- ── Per-member network cache ────────────────────────────────────────────────
--
-- `bucket_for_member` (creatures.lua) calls Network.resolve_at on every
-- recruit, every tick. Resolution walks the full member list and runs a
-- transitive-closure overlap pass — O(N²) on big networks. The result is
-- stable as long as no hive-side topology event happens, so cache it.
--
-- Important: enemy biter expansion landing inside the bbox does NOT change
-- network identity. Networks are defined purely by hive-side overlap
-- (hives + hive_nodes). Expansion only affects the recruit bucket's
-- spawner_count, which is a different scalar refreshed via a separate
-- find_entities_filtered{type = "unit-spawner"} per anchor pass.
--
-- Invalidation triggers (via Hive.on_topology_change):
--   * Hive.track / untrack
--   * Hive.track_node / untrack_node
--   * Promotion (handled by track for the new hive + untrack_node for the
--     old node — the topology event fires twice, no extra wiring needed).
--
-- The cache also self-heals on a hit by re-validating every member of the
-- cached network table; if any are stale the entry is dropped and the next
-- access re-resolves.
local cached_networks = {}

local function flush_networks_cache()
  cached_networks = {}
end

Hive.on_topology_change(flush_networks_cache)

-- Public: drop a single member's cached network without flushing the rest.
-- Used by callers that detect a stale resolution mid-tick.
function M.invalidate_member(member)
  if member and member.valid and member.unit_number then
    cached_networks[member.unit_number] = nil
  end
end

-- Public: drop everything. Hooked into on_init / on_configuration_changed
-- via Hive.invalidate_caches() in main.lua.
function M.invalidate_cache()
  flush_networks_cache()
end

-- Boxes (not circles) overlap iff their x-extents AND y-extents both
-- overlap. Hive / node ranges are axis-aligned half-extents, so the right
-- containment test is Chebyshev:
--   covers(c, p, range) ⇔ |c.x - p.x| <= range  AND  |c.y - p.y| <= range
-- and two boxes touch iff their separations along BOTH axes are <= sum of
-- the two ranges. Earlier code used Euclidean (dx*dx + dy*dy <= r*r), which
-- is the inscribed circle and falsely rejects positions in the four corner
-- regions of each box.
local function abs(x) if x < 0 then return -x end return x end

local function covers(center, position, range)
  return abs(center.x - position.x) <= range
     and abs(center.y - position.y) <= range
end

local function boxes_touch(a, b, touch)
  return abs(a.x - b.x) <= touch
     and abs(a.y - b.y) <= touch
end

-- Every hive-side structure on `surface`, with its build/visibility radius
-- and kind. `kind` distinguishes "hive" (has a chest) from "node".
function M.all_structures(surface)
  local s = State.get()
  local list = {}
  for _, bucket in pairs(s.hives_by_player) do
    for _, hive_data in pairs(bucket) do
      local e = hive_data.entity
      if e and e.valid and e.surface == surface then
        list[#list + 1] = {entity = e, range = shared.ranges.hive, kind = "hive"}
      end
    end
  end
  for _, node_data in pairs(s.hive_nodes) do
    local e = node_data.entity
    if e and e.valid and e.surface == surface then
      list[#list + 1] = {entity = e, range = shared.ranges.hive_node, kind = "node"}
    end
  end
  return list
end

-- Return the list of hive entities (chests, not nodes) in the network whose
-- combined construction radii cover `position`. nil if no member reaches it.
--
-- Algorithm: seed with anything covering the position, then expand by overlap
-- until stable. Two structures "overlap" when their ranges touch.
--
-- `reach` (optional, default 0) extends the seed check: a structure counts as
-- covering `position` when `dist <= s.range + reach`. This lets the caller
-- ask "would a new entity placed here, with its own range = reach, connect
-- to the network?" — used for hive-node placement so the player can chain
-- nodes outward without each new node having to land inside the previous
-- one's box.
function M.hives_for_position(surface, position, reach)
  reach = reach or 0
  local structs = M.all_structures(surface)
  if #structs == 0 then return nil end

  local in_net = {}
  for i, s in ipairs(structs) do
    if covers(s.entity.position, position, s.range + reach) then
      in_net[i] = true
    end
  end
  if not next(in_net) then return nil end

  local changed = true
  while changed do
    changed = false
    for i, s in ipairs(structs) do
      if not in_net[i] then
        for j in pairs(in_net) do
          local m = structs[j]
          if boxes_touch(s.entity.position, m.entity.position, s.range + m.range) then
            in_net[i] = true
            changed = true
            break
          end
        end
      end
    end
  end

  local hives = {}
  for i in pairs(in_net) do
    if structs[i].kind == "hive" then
      hives[#hives + 1] = structs[i].entity
    end
  end
  return (#hives > 0) and hives or nil
end

-- Smallest-unit_number hive in `any_member`'s network. Returns nil if
-- there is no resolved network at the member's position. Used by the
-- chest-invariant code (one chest per network, owned by the primary) and
-- by primary_chest.
function M.primary_hive(any_member)
  if not (any_member and any_member.valid) then return nil end
  local network = M.resolve_at(any_member.surface, any_member.position)
  if not network or not network.hives or #network.hives == 0 then
    return any_member.name == shared.entities.hive and any_member or nil
  end
  local primary, primary_id
  for _, h in pairs(network.hives) do
    if h and h.valid then
      local id = h.unit_number
      if id and (not primary_id or id < primary_id) then
        primary_id = id
        primary    = h
      end
    end
  end
  return primary
end

-- Primary chest for a network. The network has one shared inventory; the
-- chest the player actually sees is the one belonging to the smallest-
-- unit_number hive in the network. After the storage invariant landed
-- (only the primary holds a chest), this is the only chest in the
-- network. Writes (absorption, disgorge reads) and the GUI click on any
-- hive route here so the player never sees per-hive content splits.
--
-- Reads via the iterating helpers (item_count, pollution_capacity) walk
-- network.hives but only the primary holds anything, so the sum is correct.
function M.primary_chest(hive)
  if not (hive and hive.valid) then return nil end
  local primary = M.primary_hive(hive)
  if primary then return Hive.get_chest(primary) end
  return Hive.get_chest(hive)
end

-- Enforce the storage invariant on `any_member`'s network: exactly one
-- valid chest, owned by the network's primary hive. Called whenever
-- network topology shifts (hive built, hive destroyed-with-survivor,
-- promote node → hive). Idempotent.
--
-- Behaviour:
--   1. Resolve the network. If unresolvable (e.g. orphan hive) and the
--      member is a hive, just ensure it has its own chest (solo network).
--   2. Find the primary (smallest unit_number hive in the network).
--   3. Ensure the primary has a chest. If not, create one.
--   4. Walk the rest of the network's hives. Anything else holding a
--      chest is a leftover from before the invariant landed (or a network
--      split that consolidated): drain its contents into the primary's
--      chest, destroy it, clear its record.chest.
function M.ensure_chest_at_primary(any_member)
  if not (any_member and any_member.valid) then return end
  local network = M.resolve_at(any_member.surface, any_member.position)
  if not network or not network.hives or #network.hives == 0 then
    if any_member.name == shared.entities.hive and not Hive.get_chest(any_member) then
      Hive.create_chest(any_member)
    end
    return
  end

  local primary = M.primary_hive(any_member)
  if not primary then return end

  if not Hive.get_chest(primary) then
    Hive.create_chest(primary)
  end

  for _, h in pairs(network.hives) do
    if h and h.valid and h ~= primary and Hive.get_chest(h) then
      Hive.move_chest_contents(h, primary)
      local old_chest = Hive.get_chest(h)
      if old_chest and old_chest.valid then old_chest.destroy() end
      local r = Hive.get_storage(h)
      if r then r.chest = nil end
    end
  end
end

-- Sum of `item_name` across all chests in `hives`.
function M.item_count(hives, item_name)
  local total = 0
  for _, hive in pairs(hives) do
    local chest = Hive.get_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv then total = total + inv.get_item_count(item_name) end
    end
  end
  return total
end

-- Insert `item_stack` into the first chest in the network covering
-- `position` that can accept it. Returns true on success. Uses the
-- default reach (the position must already be inside the network).
function M.insert(surface, position, item_stack)
  local hives = M.hives_for_position(surface, position, 0)
  if not hives then return false end
  for _, hive in pairs(hives) do
    local chest = Hive.get_chest(hive)
    if chest then
      local inv = chest.get_inventory(defines.inventory.chest)
      if inv and inv.can_insert(item_stack) then
        inv.insert(item_stack)
        return true
      end
    end
  end
  return false
end

-- Resolve the full network at `position` on `surface`. Returns a table with:
--   key         number — smallest unit_number among hive + node members (stable).
--   hives       LuaEntity[]
--   nodes       LuaEntity[]
--   members     {entity, range, kind}[]  — same shape as all_structures.
--   bbox        {{x_min, y_min}, {x_max, y_max}}  — recruit-box union.
-- Or nil if no member's range covers the position.
function M.resolve_at(surface, position)
  local structs = M.all_structures(surface)
  if #structs == 0 then return nil end

  local in_net = {}
  for i, st in ipairs(structs) do
    if covers(st.entity.position, position, st.range) then
      in_net[i] = true
    end
  end
  if not next(in_net) then return nil end

  local changed = true
  while changed do
    changed = false
    for i, st in ipairs(structs) do
      if not in_net[i] then
        for j in pairs(in_net) do
          local m = structs[j]
          if boxes_touch(st.entity.position, m.entity.position, st.range + m.range) then
            in_net[i] = true
            changed = true
            break
          end
        end
      end
    end
  end

  local hives, nodes, members = {}, {}, {}
  local x_min, y_min, x_max, y_max
  for i in pairs(in_net) do
    local st = structs[i]
    members[#members + 1] = st
    if st.kind == "hive" then
      hives[#hives + 1] = st.entity
    else
      nodes[#nodes + 1] = st.entity
    end
    local px, py = st.entity.position.x, st.entity.position.y
    local r = st.range
    if not x_min then
      x_min, y_min, x_max, y_max = px - r, py - r, px + r, py + r
    else
      if px - r < x_min then x_min = px - r end
      if py - r < y_min then y_min = py - r end
      if px + r > x_max then x_max = px + r end
      if py + r > y_max then y_max = py + r end
    end
  end

  -- Stable network key: smallest unit_number among hive + node members.
  local key
  for _, m in ipairs(members) do
    local id = m.entity.unit_number
    if id and (not key or id < key) then key = id end
  end

  return {
    key     = key,
    hives   = hives,
    nodes   = nodes,
    members = members,
    bbox    = {{x_min, y_min}, {x_max, y_max}}
  }
end

-- Cached network resolution keyed off `member.unit_number`. Callers that
-- repeatedly resolve at the same member's position (recruitment scan,
-- bucket lookup) hit the cache; callers resolving at arbitrary positions
-- (build placement reach checks, vent placer hive lookup) keep using
-- resolve_at directly.
--
-- On a cache hit, re-validate every member of the cached network table.
-- If any have become invalid, drop the entry and re-resolve.
function M.cached_for_member(member)
  if not (member and member.valid and member.unit_number) then return nil end
  local key = member.unit_number
  local cached = cached_networks[key]
  if cached then
    local stale = false
    for _, m in ipairs(cached.members) do
      if not (m.entity and m.entity.valid) then stale = true; break end
    end
    if not stale then return cached end
    cached_networks[key] = nil
  end
  local resolved = M.resolve_at(member.surface, member.position)
  if resolved then cached_networks[key] = resolved end
  return resolved
end

return M
