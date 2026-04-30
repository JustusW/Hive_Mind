# Hive Mind Reworked — Working design (0.9.0)

Implementation choices for [working_requirements.md](working_requirements.md). Merge into [design.md](design.md) on release.

## Recruitment buckets

- `state.recruit_buckets[network_key] = { tokens, last_tick, spawner_count, spawner_count_tick }`. Network key = smallest `unit_number` among **hive + hive-node** entities in the network. Pheromone vents are members of the network (resolved via placer player) but do not contribute to the key — they have no recruit range and their lifecycle is tied to the placer's hive, not to network identity.
- **Trickle rate** `R = spawner_count × recruit.per_spawner_per_second`.
  - `spawner_count` = number of `unit-spawner` entities (any force) inside the network's **recruit-box union** = union of hive (`shared.ranges.hive` = 50, i.e. 100×100) and hive-node (`shared.ranges.hive_node` = 25, i.e. 50×50) boxes only. Pheromone vents contribute zero range and zero box to this union.
  - Refresh `spawner_count` on the recruit scan tick that owns the network's anchor hive (cheap: piggy-back on the unified scan, see Performance section). Cache between refreshes; recompute on `on_configuration_changed`.
- Refill on each scan: `tokens = min(cap, tokens + R × dt)`, `dt = (tick - last_tick) / 60`. `cap = bucket_cap_factor × R`. When `R` changes (spawners added or removed), the cap shrinks/grows on the next refill; current `tokens` clamps to the new cap.
- Per candidate:
  - `is_group = unit.commandable and unit.commandable.group and unit.commandable.group.valid`.
  - `is_group` → recruit, no token cost.
  - else if `tokens >= 1` → decrement, recruit.
  - else → skip cleanly (no force flip, no command).
- Force flip + command issue stay atomic per unit.
- Stale keys pruned on `on_configuration_changed`. New networks start at full cap.

## Pheromone vent

| Player item | Built entity |
|---|---|
| `hm-pheromone-vent` | `hm-pheromone-vent` (recoloured hive-node prototype, deep-red tint) |

- Hive force. No creep growth. No recruitment range. No storage. No construction zone.
- No pollution charge at placement. No placement-zone check (buildable anywhere).
- Tracked: `state.pheromone_vents[unit_number] = { entity, placer_player_index, gather_count, seen_units, mode }`.

### Network membership via placer

- At placement, `placer_player_index` is captured from `event.player_index` and stored. The vent's runtime network is resolved on demand by looking up the placer's current hive: `state.hives_by_player[placer_player_index]` → first hive → its network_key.
- If the placer has no hive at placement time, the vent is destroyed on the same tick (`entity.destroy({ raise_destroy = true })` and a chat message to the player). No tracking entry is written.
- If the placer's hive is later destroyed without replacement, the vent is collected as part of the network-collapse pass (its resolved network has no surviving hive → orphaned → destroyed).
- If the placer repositions the hive (mine + place), the vent's resolved network follows the new hive automatically — no per-vent migration step needed because lookup is dynamic.

### Recruitment destination resolution

Priority when picking the destination of a recruited biter:

1. Pheromone player (existing rule).
2. Closest pheromone vent **to the recruited unit** on the recruiter's network with `gather_count < attack_group_size_for(vent)`.
3. Hive (existing rule — recruiter is a hive, target is the hive).
4. Hive node fallback (existing rule — recruiter is a hive node, target is the nearest hive on the surface).

### Gathering and dispatch

- On unit arrival within `arrival_radius` tiles of the vent: `seen_units[unit_number] = true`, `gather_count += 1`. Unit stays alive in-world.
- When `gather_count >= attack_group_size_for(vent)`:
  - `group = surface.create_unit_group{ position = vent.position, force = hive_force }`.
  - For each in-radius hive-force unit (re-scanned at dispatch time, `find_entities_filtered{ position, radius = arrival_radius, force = hive_force, type = "unit" }`): `group:add_member(unit)`.
  - `group:start_moving()` with no destination — engine routes via attack-group AI.
  - `gather_count = 0`; `seen_units = {}`.

### Modes

- `mode ∈ {small, default, large}`.
- `tech_adjusted_base = pheromone_vent.base_size + pheromone_vent.tech_increment × completed_levels` (matches the Tech table below: `5 + 2 × L`).
- `attack_group_size_for(vent) = round(tech_adjusted_base × mode_factor[vent.mode])`.
- `mode_factor = { small = 0.5, default = 1.0, large = 2.0 }`.
- Set via marker recipes `hm-pheromone-mode-{small,default,large}` consumed on the vent.

### Tech

| Name | Type | Effect | Prerequisite |
|---|---|---|---|
| `hm-pheromone-vent` | single | unlocks `hm-pheromone-vent` recipe | `hm-worms-small` |
| `hm-attack-group-size` | infinite | `base_size = 5 + 2 × completed_levels` | `hm-pheromone-vent` |

### Crafting menu placement

- `hm-pheromone-vent` recipe: `intermediate-product` subgroup (intermediate products tab) — matches the existing rule for hive buildings.
- `hm-pheromone-mode-{small,default,large}` marker recipes: `production-machine` subgroup (production tab) — matches the existing rule for pheromone toggle recipes.

## Performance — unified scan, work-spread

- Cadence target: `intervals.scan = 60` ticks (1s). **Replaces** today's `intervals.recruit = 120` and `intervals.absorb = 30` — recruit and absorb fire from the unified scan instead. Other intervals (`intervals.workers`, `intervals.creep`, `intervals.labels`, `intervals.loadout`, `intervals.supply`) are unchanged.
- Each tick processes `ceil(N / T)` **network members (hives + hive-nodes)** on a rotating index, sorted deterministically by `unit_number`. N = total hives + hive-nodes. Per-tick scan count constant relative to network size. No moloch supertick.
- Per processed member: one `find_entities_filtered` over its bbox; in-Lua dispatch to recruit / absorb / supremacy candidate registration / spawner counting (for the trickle rate of the member's network).
- **Pheromone-vent arrival scan** runs on the same cadence and work-spreading: each tick processes `ceil(V / T)` vents (V = total pheromone vents). Per processed vent: one `find_entities_filtered{ position = vent.position, radius = pheromone_vent.arrival_radius, force = hive_force, type = "unit" }`. For each unit not yet in `seen_units`: add it, `gather_count += 1`. Dispatch when `gather_count >= attack_group_size_for(vent)`.

### Cross-hive aggregation

- Pre-bucket hives by surface once per scan tick.
- For force=`{player, neutral}` scans (supremacy, vent intake), do one combined scan per surface; dispatch to hives in Lua. Reduces engine ↔ Lua boundary crossings.

## Performance — supremacy

- Damage cadence: `intervals.supremacy = 60` ticks.
- Candidate scan cadence: `supremacy.candidate_scan = 600` ticks per hive.
- Cache: `state.supremacy_candidates[hive_unit_number] = { [entity_unit_number] = { entity, lifetime_seconds, is_tree, pollution_burst } }`.
- Damage tick: walk cache, drop `not entity.valid`, chunk-bbox creep check (no `surface.get_tile`), apply per-tick damage. On kill: if tree, `surface.pollute(pos, pollution_burst)`.
- Candidate scan: rebuild cache from `find_entities_filtered{ area, force = {player, neutral} }`.

## Performance — node absorption

- `tick_absorption` iterates hives **and** hive nodes.
- Nodes insert into the network's primary chest (smallest `unit_number` hive in the network).
- Reuse existing `is_for_role` filter.

## Performance — workers from nodes

- `Workers.tick()` spawn entity = closest in-network hive **or** hive node to the ghost.
- Shared `find_non_colliding_position` helper for both.

## Performance — caching and lazy ticks

- `node_data.nearest_hive_unit_number`: cache. Invalidate on hive build/death + `on_configuration_changed`. Lazy recompute on stale.
- `Workers.tick()`: skip when `state.worker_jobs` empty AND no hive-force ghosts on any surface.

## Network collapse

- Trigger: `Death.on_removed` for a `hm-hive`.
- **Surviving-hive detection must use `Hive.all()`**, not just `s.hives_by_player`. `Hive.all()` queries the surface and picks up a just-placed-but-untracked replacement hive. Using only player-bucket state would falsely collapse the network on every legitimate repositioning (the new hive is in the world but not yet `Hive.track`'d at the moment `Death.on_removed` runs).
- **Connectivity walk starts from each surviving hive**, not from the destroyed hive's neighbours. Orphan set = `(all hive-force buildings on surface) − (union of network components of surviving hives)`. This handles every repositioning case: new hive close enough → old neighbours stay reachable, no orphans; new hive too far → old neighbours genuinely orphaned, collapse is correct; no replacement → all orphaned, full collapse.
- **Pheromone vents** are matched into the orphan set by resolving each vent's `placer_player_index` → placer's current hive → that hive's network. Vents whose placer has no surviving hive (or whose placer's hive is in an orphaned component) are orphaned.
- Orphan scope is **hive force only**. Player-placed spawners / worms live on the enemy force after the build-time swap and are not tracked back to a network; they survive the collapse as ordinary vanilla nests/turrets. No `placed_enemy_entities` map is needed.
- For each orphaned entity (all on hive force):
  - Hive nodes, pheromone vents, hive labs, hive storage chests: `entity.destroy({ raise_destroy = true })` so removal flows through the existing pipeline. Hive storage: release creature contents as live units first.
  - Hive workers (in flight or idle) on the orphaned network: `entity.die()` so worker-death cleanup runs.
- Drop `state.recruit_buckets[orphan_key]` and `state.pheromone_vents[orphan_unit_number]` for orphaned members.
- Re-resolve any other network keys that share a `network_key` with the orphan, in case the collapse changed the smallest-unit_number anchor.

## Telemetry

Both gated on existing Debug flag. Append to `script-output/hm-debug.txt`.

```
[recruit] tick=N networks=K tokens=[t1,t2,...] R=[r1,r2,...] spawners=[s1,s2,...] group=G trickle=T skipped=S
[perf]    tick=N scan_hives=H recruit_ms=… absorb_ms=… supremacy_ms=… workers_ms=… creep_ms=… total_ms=…
```

## Tunables (shared.lua)

| Name | Default | Notes |
|---|---|---|
| `recruit.per_spawner_per_second` | 0.05 | trickle rate per spawner in network range |
| `recruit.bucket_cap_factor` | 5 | bucket cap = 5 × R, where R = spawner_count × per_spawner_per_second |
| `recruit.gate_attack_groups` | false | attack-group biters bypass bucket |
| `intervals.scan` | 60 | unified scan cadence |
| `intervals.supremacy` | 60 | damage cadence |
| `supremacy.candidate_scan` | 600 | candidate rebuild cadence per hive |
| `pheromone_vent.base_size` | 5 | base attack-group size |
| `pheromone_vent.tech_increment` | 2 | per level |
| `pheromone_vent.mode_factor` | `{small=0.5, default=1.0, large=2.0}` | |
| `pheromone_vent.arrival_radius` | 3 | tiles |

## Implementation order

1. Telemetry log lines (`[recruit]`, `[perf]`).
2. Unified scan with work-spreading + surface aggregation.
3. Node absorption, nearest-hive cache, workers from nodes, lazy worker tick.
4. Supremacy candidate caching.
5. Recruitment buckets + attack-group bypass.
6. Pheromone vent (depends on recruitment destination logic).

## Edge cases

- Network split/merge: stale `recruit_buckets` keys dropped on next tick. New networks at full cap.
- Hiveless placement: pheromone vent placed by a player with no hive is destroyed on the same tick with a chat message.
- Placer leaves multiplayer game: vent's `placer_player_index` still resolves via `state.hives_by_player` if the player's hive entry persists across disconnect; if not, treat as hiveless and orphan the vent on the next collapse pass.
- Multiplayer: bucket per network, not per player. Two players whose hives share a network share the bucket.
- Recruitment ties: pheromone-vent-closest-non-full > hive > hive-node fallback. Pheromones beat all.
- Friendly fire on dispatch: hive force is friend with enemy. Test dispatch behaviour with debug recipe; tighten via `command.target_filter` if engine routes attack groups at vanilla nests.
- Mode-marker UX: marker-item-on-vent, no GUI.
