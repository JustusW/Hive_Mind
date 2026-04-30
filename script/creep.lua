-- Creep growth: deterministic Chebyshev-ring fill.
--
-- The previous Eden boundary-accretion algorithm produced a circular blob
-- with the spikey/fingered edges that are characteristic of Eden growth on
-- KPZ-class dynamics. We don't want that: the hive's footprint is an axis-
-- aligned box (creep_radius == build/visibility radius), so creep should
-- fill the same box and stop, with no offshoots beyond it.
--
-- Algorithm:
--   * Each hive/node holds a (creep_layer, creep_step) cursor in storage.
--   * Layer N is the Chebyshev ring at distance N from the centre. Ring 0
--     is the single centre tile; ring N (N >= 1) has 8*N tiles wrapping
--     the previous square.
--   * Per tick we consume up to `attempts` cursor steps. For each step we
--     compute (dx, dy) for the current ring index and (if the tile is a
--     valid substrate) place a creep tile there. The cursor then advances
--     to the next index; when a ring is complete we move to the next.
--   * Within a ring we visit indices via a prime-stride permutation
--     (`step * RING_STRIDE mod ring_size`). The stride is coprime to every
--     ring size in range, so it visits each index exactly once — but the
--     visit order looks scattered rather than a clockwise sweep, which
--     reads as organic without breaking the rectangular bound.
--
-- When a hive's creep first spreads we also flip the hive-labs tech to
-- researched (gameplay event unlocking the lab recipe).

local shared = require("shared")
local State  = require("script.state")
local Hive   = require("script.hive")
local Anchor = require("script.anchor")

local M = {}

-- Coprime to every ring size 8*L for L in 1..max sensible radius. 1009 is
-- prime and far larger than 8 * 50 (our biggest hive ring), so the modular
-- step always traces a full permutation of the ring.
local RING_STRIDE = 1009

local function is_blocked(name)
  return name:find("water", 1, true) ~= nil
      or name:find("void",  1, true) ~= nil
end

-- Deterministic per-tile noise in [0, 1). Pure function of world (tx, ty),
-- so save/load reproduces the exact same edge silhouette and creep growth
-- doesn't drift between sessions.
local function tile_noise(tx, ty)
  local h = (tx * 73856093 + ty * 19349663) % 1000003
  if h < 0 then h = h + 1000003 end
  return h / 1000003
end

-- Edge fuzzing: probability that a tile at `layer` (Chebyshev distance from
-- the centre) gets placed, given max_radius. Inside tiles (layer well below
-- max) always place. The outermost two rings get progressively patchier,
-- and a single ring beyond max_radius gets a sparse extension. Pure
-- function of layer + tile position so the silhouette is stable.
local function pass_edge_noise(layer, max_radius, tx, ty)
  if layer <= max_radius - 2 then return true end
  local n = tile_noise(tx, ty)
  if layer == max_radius - 1 then return n > 0.10 end  -- 90% placed
  if layer == max_radius     then return n > 0.35 end  -- ~65% placed
  if layer == max_radius + 1 then return n > 0.70 end  -- ~30% placed (extension)
  return false
end

-- Map a (layer, raw_step) cursor to a (dx, dy) offset on the ring. The
-- raw_step is mapped through the prime stride to scatter the visit order.
local function ring_offset(layer, step)
  if layer == 0 then return 0, 0 end
  local size = 8 * layer
  local idx  = (step * RING_STRIDE) % size

  -- Walk the ring: top edge L→R, right edge T→B, bottom edge R→L, left edge B→T.
  -- Each edge contributes 2*layer tiles (corners shared with the next edge).
  local l = layer
  if idx < 2 * l then
    return -l + idx, -l
  elseif idx < 4 * l then
    return l, -l + (idx - 2 * l)
  elseif idx < 6 * l then
    return l - (idx - 4 * l), l
  else
    return -l, l - (idx - 6 * l)
  end
end

local function place_organic_creep(entity, record, max_radius, attempts)
  local surface = entity.surface
  local cx = math.floor(entity.position.x + 0.5)
  local cy = math.floor(entity.position.y + 0.5)
  local placed = 0
  local tiles  = {}

  local layer = record.creep_layer or 0
  local step  = record.creep_step  or 0

  for _ = 1, attempts do
    -- Stop one ring beyond max_radius — the extension ring is sparse and
    -- gives the silhouette its irregular edge. Anything further would
    -- look like fingers.
    if layer > max_radius + 1 then break end

    local dx, dy = ring_offset(layer, step)
    local tx, ty = cx + dx, cy + dy
    local tile = surface.get_tile(tx, ty)
    if tile and tile.valid then
      local name = tile.name
      if not shared.is_creep_tile(name) and not is_blocked(name)
         and pass_edge_noise(layer, max_radius, tx, ty) then
        tiles[#tiles + 1] = {name = shared.creep_tile, position = {tx, ty}}
        placed = placed + 1
      end
    end

    -- Advance cursor. Layer 0 is a single tile (the centre); after placing
    -- it we jump straight to layer 1.
    if layer == 0 then
      layer = 1
      step  = 0
    else
      step = step + 1
      if step >= 8 * layer then
        layer = layer + 1
        step  = 0
      end
    end
  end

  record.creep_layer = layer
  record.creep_step  = step

  if #tiles > 0 then surface.set_tiles(tiles, true) end
  return placed > 0
end

function M.tick()
  local hive_attempts = shared.creep_tiles_per_call.hive
  local node_attempts = shared.creep_tiles_per_call.hive_node
  local hive_r        = shared.creep_radius.hive
  local node_r        = shared.creep_radius.hive_node

  for _, hive in pairs(Hive.all()) do
    local record = Hive.get_storage(hive)
    -- Skip hives still in their 30-second anchor construction window. Creep
    -- doesn't spread until the hive is "live"; this gives the player a
    -- visual cue that the construction has completed.
    if record and not Anchor.is_building(record) then
      local placed = place_organic_creep(hive, record, hive_r, hive_attempts)
      if placed then
        local tech = hive.force.technologies[shared.technologies.hive_labs]
        if tech and not tech.researched then
          tech.researched = true
          local recipe = hive.force.recipes[shared.recipes.hive_lab]
          if recipe then recipe.enabled = true end
        end
      end
    end
  end

  local s = State.get()
  for _, node_data in pairs(s.hive_nodes) do
    local node = node_data.entity
    if node and node.valid then
      place_organic_creep(node, node_data, node_r, node_attempts)
    end
  end
end

return M
