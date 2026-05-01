# Hive Mind Reworked — Design Notes

Implementation choices and engine-level details that the requirements doc deliberately leaves out. Read [requirements.md](requirements.md) first.

## Forces

- One `hivemind` force. All hive players, all recruited creatures, all script-spawned biters live here.
- Mutual cease-fire and friend with `enemy` and `spectator` forces.
- The friend flag is what lets recruited biters mingle with vanilla biters without fighting.

## Player controller

- `set_controller({type = defines.controllers.god})` on join.
- Inventory is cleared on join, on respawn, and on any change to gun / ammo / armor inventories.
- A custom permission group blocks mining, dropping, and inventory transfer actions.
- Mining attempts queue the entity for re-creation and print a chat message.
- Deconstruction marking is intercepted and cancelled.

## GUI

- Two sibling buttons live in a private `hm-button-flow` under `player.gui.top`: **Join the Hive** and **Reject the Hive**. We avoid `mod_gui`'s shared frame so destroying the flow on commit also destroys the bordered container — no empty box left behind.
- Rejection persists in `state.rejected_players[index]` and prints `gui.hm-hive-rejected` to that player.
- A floating text render-object hovers above each hive, refreshed every `shared.intervals.labels` ticks. It shows `[item=hm-pollution] N` where N is the network's current pollution capacity, recoloured green / amber / red by health. The render id is persisted on the hive's storage record.
- Clicking on a hive opens its hidden storage chest's inventory rather than the (empty) roboport GUI: `Director.on_gui_opened` intercepts `gui_type.entity` for `shared.entities.hive` and reassigns `player.opened` to the chest. The roboport prototype is kept for its construction-zone overlay and dashed connection lines, but the inventory the player cares about is the chest.

## Director loadout

- A watchdog tick every `shared.intervals.loadout` ticks ensures every hive director has at least one of every currently-buildable item in their main inventory and pins them to the quickbar in a stable order.
- "Currently buildable" means the gating recipe is enabled on the hive force. New buildings unlocked by research therefore appear in the loadout within a watchdog tick (or immediately on join / respawn).
- After a successful placement the cursor is auto-refunded (cursor first, main inventory fallback) so the player can keep dropping buildings without re-crafting.

## Building map

| Player item | Built entity | Notes |
|---|---|---|
| `hm-hive` | `hm-hive` | Roboport prototype, 0 robot / 0 material slots (kept for the build-zone overlay and dashed connection lines, not for bots). Storage lives in an adjacent passive-provider chest; clicking the hive routes to that chest's GUI. Visually: scaled-up vendored gleba-spawner ("egg raft") with its original Space Age coloration. Build / visibility: 100×100 box. |
| `hm-hive-node` | `hm-hive-node` | Roboport prototype, 0 robot / 0 material slots. Visual: vendored small gleba-spawner at original scale. Build / visibility: 50×50 box. |
| `hm-hive-lab` | `hm-hive-lab` | Lab prototype. Visual: vendored Biolab at original scale. Only accepts `hm-pollution-science-pack`. |
| `hm-biter-spawner` | vanilla `biter-spawner` | Player places a tinted proxy ghost (`hm-spawner-ghost`); `on_built_entity` swaps it for a real `biter-spawner` on the enemy force. |
| `hm-spitter-spawner` | vanilla `spitter-spawner` | Same proxy mechanic via `hm-spitter-spawner-ghost`. |
| `hm-{tier}-worm` | vanilla `{tier}-worm-turret` | Same proxy mechanic, one ghost per tier. |
| `hm-pollution-generator` | `hm-pollution-generator` | Debug pollution emitter, free to place. |
| `hm-pheromone-vent` | `hm-pheromone-vent` | Recoloured hive-node prototype (deep-red tint). Hive force, no creep growth, no recruitment range, no storage, no construction zone. Buildable anywhere; no placement-zone check. Free to place. See "Pheromone vent" section. |

## Visual style

Every hive-side entity is a sprite swap. The hive itself uses a vendored copy of the Space Age **gleba-spawner** ("egg raft") sprite, scaled up but left in its original colors, so it looks the same whether or not Space Age is enabled. Hive nodes use the vendored small gleba-spawner at original scale and original colors. Hive labs use the vendored Biolab at original scale and original colors. Storage chests, biter/spitter spawner proxies, and worm proxies use the biter-spawner sprite tinted in their respective hues. Hive workers use vendored Space Age small-wiggler run graphics and sounds. No roboport, vanilla lab, or chest sprites should appear.

The vendored helper only exposes `hm-*` prototypes and asset paths under `__Hive_Mind_Reworked__`; it does not register `gleba-spawner` or `small-wriggler-pentapod`, so enabling Space Age alongside the mod does not create duplicate prototype-name conflicts.

Color anchors: hive = orange-red, hive node = teal, hive lab = purple, hive storage = orange-red, biter spawner proxy = orange-red, spitter spawner proxy = lime, worm proxies = purple shades by tier, pheromone vent = deep red.

Hive tracking is backed by runtime state but treats actual `hm-hive` and `hm-hive-node` entities on the hive force as authoritative recovery data. On load/config changes and before network-sensitive scans, the runtime reconciles state from the world: missing hives are linked back to a player bucket, missing nodes are restored to `hive_nodes`, invalid references are removed, and hive storage records are recreated without discarding valid chests. This keeps construction range, recruitment, creep growth, and one-hive replacement working after save/load.

Crafting menu placement: the pheromone burst recipe, the Promote Node recipe (`hm-promote-node`), and the pheromone-vent mode markers (`hm-pheromone-mode-{small,default,large}`) live in the production tab via the `production-machine` subgroup. Every other hive recipe (including `hm-pheromone-vent`) lives in the intermediate products tab via the `intermediate-product` subgroup. Item subgroups (e.g. `hm-hive` item is `defensive-structure`) are not constrained to match their recipes; the director's quickbar is fixed and refilled by the loadout watchdog, so item subgroups affect nothing the player browses.

The `Release Pheromones` recipe (`hm-pheromones-on`) is the player-facing trigger for the single-shot pheromone burst (see "Player pheromone burst"). It still produces an `hm-pheromones` item as a craft result, but the item is consumed immediately on receipt and exists only because Factorio recipes need a result. There is no Withdraw recipe — the burst is bounded and re-crafting cancels.

## Hive workers

The hive worker is a `unit` (real Space Age small wriggler when available, base-game unit fallback otherwise, hive-force) commanded by a script-side dispatcher. There is no roboport-driven build pipeline: the hive prototype keeps `robot_slots_count = 0` and does no native auto-building. Every ghost is fulfilled by a worker that walks from the nearest hive to the build site, calls `surface.create_entity{raise_built = true}` to materialise it, and is removed on arrival. If Space Age is loaded, the matching wiggler corpse is spawned; otherwise the worker simply vanishes rather than showing a biter corpse.

- `hm-hive-worker` is based on `small-wriggler-pentapod` when Space Age is loaded, falling back to `small-biter` otherwise; vendored Space Age small-wiggler run graphics, icon, and sounds are applied in both cases. Visible, ground-bound, friendly with enemy/spectator/hivemind. Health is high but not invulnerable.
- `Workers.queue(ghost)` enqueues a pending materialisation. `fulfill_ghost` calls this after passing the tech / obstruction / consume guards — the chest insert + bot pickup hand-off is gone.
- `Workers.tick()` runs every `shared.intervals.workers` ticks. It validates each pending job (ghost still valid, worker still valid, target still in range), spawns a worker at the closest in-network hive when capacity allows, and checks each in-flight worker's distance to its target. Within `WORKERS_ARRIVAL_RADIUS` tiles of the ghost the worker calls `surface.create_entity` for the ghost's entity name (with `raise_built = true`), destroys the ghost, and removes the worker via `Hive.spawn_worker_corpse`.
- A worker that doesn't reach its target inside `WORKERS_TIMEOUT_TICKS` is abandoned (killed) and its job is requeued so a fresh worker can try.
- Capacity per hive: `shared.hive_workers_per_hive`. State lives at `state.worker_jobs[ghost_unit_number] = {ghost, worker, hive, deadline}`.
- Worker death (gameplay attack, hive destroyed, etc.) cleans up via the existing `on_entity_died` handler, which drops the job back on the queue.

## Storage

- Each hive owns an `hm-hive-storage` passive-provider chest, spawned adjacent on hive placement. Visually a tinted spawner — no chest sprite.
- The chest holds:
  - `hm-creature-<unit-name>` items — one per absorbed unit, hidden.
  - `hm-pollution` items — hidden currency, stack 10000.
- Chest is `not-blueprintable` and `not-deconstructable`. Inspectable but not meant to be managed.
- On hive death the chest's creature contents are first respawned as living units on the hive force, then the chest is destroyed. Any pollution overflow is discarded.
- On `on_configuration_changed`, missing chests are recreated.

## Network resolver

- A "network" is the set of hive + hive-node entities whose construction radii overlap, scoped to the hive force and the same surface.
- Cost reads and writes treat the union of all member chests as one virtual inventory.
- `Network.hives_for_position(surface, position, reach)` accepts an optional `reach` parameter: the seed check uses `s.range + reach` instead of `s.range`. With `reach = 0` (default), the position must be inside an existing structure's box. With `reach = shared.ranges.hive_node`, the position only has to be close enough that the new node's own range would overlap the network — used so the player can extend the network outward by chaining nodes without having to rebuild from inside the previous range. `Cost.placement_reach(entity_name)` returns this value: zero for everything except the hive node.

## Anchor placement

All anchor-binding behavior in this section is gated on the `hm-anchor-binding` startup boolean (default `false`). Read at runtime via `shared.feature_enabled("hm-anchor-binding")` in the few places that branch on it (Force.configure's always-enabled list, Build.on_built's hive branch, Director.join's grant call, Death.on_removed's re-grant). When the setting is **off** the legacy code path runs: hm-hive is in always_enabled_recipes, placement runs the original on_hive_placed (immediate setup, recipes unlock, item refunded, previous hive destroyed via Death.destroy_previous_player_hives). When **on**:

- The `hm-hive` recipe is removed from the always-enabled set and is not unlockable. Players can never craft a hive item. The only way to obtain one is via `Anchor.ensure_hive_available(player)`, called from `Director.join` and from the network-collapse pass. The function is idempotent: it inserts a single `hm-hive` item into the player's main inventory only if they currently have **no** hive item, **no** hive entity (anchor or promoted), and **no** pending construction. Re-joins, double-calls, or transient states can't produce a duplicate item.
- The hive force is endless. When all of a player's hives die (network collapse), `Anchor.ensure_hive_available(player)` is called from the collapse handler so the player gets a fresh hive item and can re-anchor. Losing the network still costs them everything else (chest contents, creep, position) — only the right to play continues.
- The `hm-hive` entity prototype is set `minable = nil` (or has its `minable.result` removed) once construction completes. While in construction it remains minable so the player can cancel and refund.
- Placement flow:
  - `Build.on_built` recognises `hm-hive` placements. The hive entity is created normally, its storage chest is created normally, and a record is appended to `state.pending_anchor_constructions[unit_number] = { entity, owner_player_index, deadline_tick = game.tick + shared.anchor.construction_ticks }`.
  - The hive is flagged in its storage record with `building_until_tick = deadline_tick`. While `game.tick < building_until_tick`, the hive is treated as inert: recruitment skips it (Scan.tick checks the flag), creep growth skips it (Creep.tick checks the flag), labels render "Constructing… Ns", and the lab recipe / pheromone-vent unlock auto-completes do not fire from this hive yet.
  - A chat message is printed to the placing player at on_built time: `{"message.hm-anchor-construction-started"}` ("Hive construction started. It is extremely hard to move and will permanently bind your hive to this position. Construction takes 30 seconds.").
  - There is no cancellation. The director permission group already blocks mining at the input layer, and we do not add an exception for in-progress hives. The 30-second window is purely a commitment timer; if the player picks the wrong spot, the only recovery path is to lose the hive in combat (which triggers network collapse + a fresh starter item via the endless-hive rule).
  - On each on_tick the runtime scans `state.pending_anchor_constructions` for entries whose `deadline_tick <= game.tick`. For each: clear `building_until_tick`, flip the hive prototype's minable status off for that entity (via `entity.minable_flag = false` or by relying on the prototype-level minable removal — TBD which API works at runtime; if neither, gate via the build pipeline's mine-handler), trigger creep auto-research (`hm-hive-spawners` if not already), and remove the entry.
- If the entity dies (combat, etc.) during construction, the pending record is dropped in the existing `on_entity_died` handler and the player gets nothing back — the same as losing a finished anchor (consistent with the "anchor-loss is catastrophic" design).
- `state.pending_anchor_constructions` lives in `storage`, so a 30-second placement survives save/load — the deadline_tick is absolute against `game.tick`.

## Hive promotion (multi-hive expansion)

- New recipe `hm-promote-node` produces an `hm-promote-node` marker item. Recipe is unlocked when the first hive finishes construction (auto-research alongside `hm-hive-spawners`). Pollution cost = `shared.promotion.cost` (initial 1000), charged from the network on craft (the recipe ingredient list reads `hm-pollution × cost`).
- The marker item is consumed via `on_player_used_capsule`-style handling (or the existing item-on-target pattern used by vent mode markers). When the player applies it on a `hm-hive-node` they own (in their network), the script:
  - Validates: target entity is an `hm-hive-node`, on the player's network (resolved via `Network.resolve_at`), not currently in a pending construction.
  - Records the target's position, network membership, and storage record ties (nodes have no storage of their own — promotion gives the new hive a fresh storage chest).
  - Destroys the node, creates an `hm-hive` at the same position, runs the standard chest-attach + storage-record path. Skips the 30-second construction; promoted hives are live immediately. (The 30s timer exists to make the anchor decision deliberate; a promotion is already deliberate by virtue of the pollution cost + targeting action.)
  - Marks the new hive's storage record with `is_promoted = true`. The flag distinguishes promoted hives from the anchor for future code paths (e.g. if demotion is added later) but currently has no behavioural effect — both anchor and promoted hives are non-minable through the director permission group, and storage-merge / collapse semantics treat them identically.
- Promotion is one-way. There is no demote-back-to-node action in the current spec. If the user wants demotion later it can be added as a separate marker recipe; the `is_promoted` flag is already in place to support it.
- Promoted hives **do not** count toward the evolution gate. The gate counts only `hm-hive-node` entities. Promoting a node removes one from the count and replaces it with a hive (which contributes its 100×100 recruit box to spawner_count math but does not occupy a node slot).
- Storage merge on hive death: when a hive dies and another hive on the same network survives, the dead hive's chest contents are transferred to a surviving hive's chest before destruction (existing `release_hive_contents` is replaced by a "merge into surviving network member" path). The network only collapses (orphans destroyed, creatures disgorged) when the **last** hive dies. This makes promoted hives genuine redundancy — the network's loss condition is `forall(hives_in_network).destroyed`, not `anchor.destroyed`.

## Evolution-gated node count

Gated on the `hm-evolution-gate` startup boolean (default `false`). The check lives in `Build.on_built`'s hive_node branch and is wrapped in `if shared.feature_enabled("hm-evolution-gate") then ... end`. When off, node placement runs without the evolution check.

- New tunable `shared.network.evolution_step` (default `0.05`). The Nth node-equivalent placement in a network requires `enemy_force.evolution_factor >= (N - 1) * evolution_step`.
- The count is **only** the number of `hm-hive-node` entities in the network. Hives (anchor and promoted) do not count. Promoting a node converts that node into a hive, removing one from the count.
- Enforcement lives in `Build.on_built` for both `hm-hive-node` placements and the `hm-promote-node` marker handler. When the gate fails:
  - Refund the placement (cancel and return the item to the player's cursor / main inventory).
  - Print `{"message.hm-node-evolution-gated", required_evolution, current_evolution, n}` to the placing player. Existing chat-error helpers in build.lua handle this.
- The cap reads the *post-placement* count (i.e. placing the 4th node requires the threshold for N=4), so the threshold for the 1st is 0 (always passes) and the maximum reachable count is `floor(1 + max_evolution / evolution_step) = 21` at evolution 1.0 with the default step.
- Existing nodes loaded from saves under the old rules: not retroactively destroyed. Only new placements are checked.
- The check is per-network, not per-surface or global — separate networks (e.g. an anchor + a far promoted hive that's no longer node-connected back to the anchor) each have their own count. (In practice the anchor permanence + reach rules keep the network connected, so this distinction rarely matters.)
- A "recruiter" is any hive or hive node. Recruit radius is `shared.ranges.hive * reach_factor` for hives and `shared.ranges.hive_node * reach_factor` for nodes, where `reach_factor = 1 + completed_attraction_reach_levels * shared.attraction_reach_step`.

### Token bucket

- `state.recruit_buckets[network_key] = { tokens, last_tick, spawner_count, spawner_count_tick }`. Network key = smallest `unit_number` among hive + hive-node entities in the network. Pheromone vents are members of the network (resolved via placer) but do not contribute to the key — they have no recruit range and their lifecycle is tied to the placer's hive.
- Trickle rate `R = spawner_count × recruit.per_spawner_per_second`.
  - `spawner_count` = number of `unit-spawner` entities (any force) inside the network's recruit-box union (hive 100×100 + hive-node 50×50 only; pheromone vents contribute zero box).
  - Refresh on the unified scan tick that owns the network's anchor hive. Cache between refreshes; recompute on `on_configuration_changed`.
- Refill on each scan tick: `tokens = min(cap, tokens + R × dt)`, `dt = (tick - last_tick) / 60`. `cap = recruit.bucket_cap_factor × R`. When `R` changes, `tokens` clamps to the new cap.
- Per candidate:
  - `is_group = unit.commandable and unit.commandable.group and unit.commandable.group.valid`.
  - `is_group` → recruit, no token cost.
  - else if `tokens >= 1` → decrement, recruit.
  - else → skip cleanly (no force flip, no command).
- Force flip + command issue stay atomic per unit.
- Stale keys pruned on `on_configuration_changed`. New networks start at full cap.

### Destination resolution

Priority when picking the destination of a recruited biter:

1. Active player pheromone burst (singleton position; see "Player pheromone burst"). Overrides every other destination on every surface.
2. Closest pheromone vent **to the recruited unit** on the recruiter's network with `gather_count < attack_group_size_for(vent)`.
3. Hive (recruiter is a hive, target is the hive).
4. Hive node fallback (recruiter is a hive node, target is the nearest hive on the surface — nodes have no chest, so absorption only happens at hives).

## Player pheromone burst

- Singleton state: `state.active_pheromone = { surface_index, position = {x,y}, target_size, gather_count, seen_units = {}, started_tick }` or `nil`. At most one instance is ever live.
- Trigger: the player crafts the `hm-pheromones-on` recipe. The recipe still produces an `hm-pheromones` item; on `on_player_crafted_item` (or the equivalent inventory-changed handler when the item appears) the script (a) clears any previous `state.active_pheromone`, then (b) writes a new instance with `surface_index = player.surface.index`, `position = player.position`, `target_size = pheromone_vent.base_size + tech_increment × completed_levels` (i.e. default-mode vent size, scaled by Attack Group Size tech), `gather_count = 0`, `seen_units = {}`, `started_tick = game.tick`. The crafted `hm-pheromones` item is consumed in the same tick — it has no in-world function beyond being the recipe's result.
- Re-crafting while an instance is live and `gather_count < target_size` simply overwrites the singleton with a fresh instance at the new position. Already-recruited biters still hold their previous attack_area command targeting the old position; on the next recruitment tick they get re-targeted to the new burst's position via the destination-resolution rule.
- Re-crafting after an instance has dispatched (gather_count reached target_size, see below) is unrelated to the dispersed group: that group is a real engine attack group and is not tracked further. The new craft starts a clean gather.
- Destination integration: when `state.active_pheromone` is set and the recruiter is on its surface, recruitment uses `command_unit_to_position(unit, active_pheromone.position)` (attack_area, radius 16, distraction.none) — the same call already used today for pheromone players. This naturally keeps biters engaging engineer stuff in the immediate area.
- Disgorge: on each recruitment tick where `state.active_pheromone` is set, every hive on the burst's surface disgorges its stored creature items as live units (existing `disgorge_hive_units` call) and commands them to the burst position. Pollution stays in storage.
- Arrival counting: on the same cadence as the vent arrival scan (unified scan), if `state.active_pheromone` is set the script does one `find_entities_filtered{ position, radius = pheromone_vent.arrival_radius, force = hive_force, type = "unit" }` at the burst position. New unit_numbers are added to `seen_units` and `gather_count` is incremented. When `gather_count >= target_size`:
  - `group = surface.create_unit_group{ position = burst.position, force = hive_force }`.
  - For each in-radius hive-force unit (re-scanned at dispatch time, excluding `hm-hive-worker`): `group:add_member(unit)`.
  - `group:start_moving()` — engine takes over; the burst entry is cleared.
- Persistence: `state.active_pheromone` lives in `storage`, so save/load preserves an in-progress gather. The `surface_index` is stored (not the LuaSurface) so it's reload-stable.

## Pheromone vent

- Tracked: `state.pheromone_vents[unit_number] = { entity, placer_player_index, gather_count, seen_units, mode }`.

### Network membership via placer

- At placement, `placer_player_index` is captured from `event.player_index` and stored. The vent's runtime network is resolved on demand by looking up the placer's current hive: `state.hives_by_player[placer_player_index]` → first hive → its `network_key`.
- If the placer has no hive at placement time, the vent is destroyed on the same tick (`entity.destroy({ raise_destroy = true })` and a chat message). No tracking entry is written.
- If the placer's hive is later destroyed without replacement, the vent is collected as part of the network-collapse pass (its resolved network has no surviving hive → orphaned → destroyed).
- If the placer repositions the hive (mine + place), the vent's resolved network follows the new hive automatically — no per-vent migration step needed because lookup is dynamic.

### Gathering and dispatch

- Arrival scan runs on the unified-scan cadence (see "Performance — unified scan"). Each tick processes a fraction of vents on a rotating index. Per processed vent: one `find_entities_filtered{ position = vent.position, radius = pheromone_vent.arrival_radius, force = hive_force, type = "unit" }`. For each unit not yet in `seen_units`: add it, `gather_count += 1`.
- When `gather_count >= attack_group_size_for(vent)`:
  - `group = surface.create_unit_group{ position = vent.position, force = hive_force }`.
  - For each in-radius hive-force unit (re-scanned at dispatch time): `group:add_member(unit)`.
  - `group:start_moving()` with no destination — engine routes via attack-group AI.
  - `gather_count = 0`; `seen_units = {}`.

### Modes

- `mode ∈ {small, default, large}`.
- `tech_adjusted_base = pheromone_vent.base_size + pheromone_vent.tech_increment × completed_levels`.
- `attack_group_size_for(vent) = round(tech_adjusted_base × pheromone_vent.mode_factor[vent.mode])`.
- `mode_factor = { small = 0.5, default = 1.0, large = 2.0 }`.
- Set via marker recipes `hm-pheromone-mode-{small,default,large}` consumed on the vent. No GUI.

### Pheromone vent risks

- **Friendly fire on dispatch**: hive force is friend with enemy. A group started with no destination defaults to attacking polluted chunks. Verify the engine doesn't path them at vanilla nests; if it does, tighten via `command.target_filter` or a force-friendship override. Test with a debug recipe before shipping.
- **Disconnect**: vent's `placer_player_index` resolves via `state.hives_by_player`; if the player's hive entry persists across disconnect the vent keeps working, otherwise it's orphaned on the next collapse pass.

## Build cost

- `shared.build_costs[entity_name]` is an explicit override table for hive-tier entities.
- `Cost.unit_pollution_value(unit_name)` is memoised by name. Prototype data doesn't change at runtime, so the lookup of `prototypes.entity[name].absorptions_to_join_attack.pollution` runs at most once per unit name per session. Called from `convert_creatures` and `pollution_capacity` — both hot paths during high-throughput recruitment.
- Anything else: `cost = sum(ingredient.amount * shared.item_pollution_factors[ingredient.name])` from the recipe that produces the entity's place-item.
- For spawners and worms, the cost is keyed on the proxy entity. The post-swap real entity does not re-charge.

## Cost charging

- `Cost.pollution_capacity(hives)` sums every chest's existing pollution plus the value of every stored creature. This is read-only and used as a pre-check.
- `Cost.consume(surface, position, amount)` resolves the network, computes capacity, and only mutates state on the success path. If capacity is short it returns `false, "insufficient", {need, have}` without converting any biters.
- `Cost.convert_creatures` consumes the minimum number of biters needed to reach the target — no surplus burn.
- **Direct path**: `on_built_entity` for a real entity → charge runs first; failure refunds the item and destroys the entity. On success the cursor item is refunded AND the just-placed entity is destroyed and replaced with an `entity-ghost` of the same name at the same position, then queued in `Workers`. The worker walks over and materialises it via `surface.create_entity{raise_built = true}`. This makes direct and ghost placements behave identically — every build is animated by a worker walking out of the nearest hive. The hive itself is the exception: it stays direct-placed because no workers exist before the first hive lands.
- **Ghost path**: `on_built_entity` for an `entity-ghost` → `fulfill_ghost` runs tech / obstruction / consume guards. On success the ghost is enqueued via `Workers.queue` for a hive worker to walk to and materialise. Any failure destroys the ghost so the world doesn't accumulate dead ghosts.
- Failure messages report the actual gap: `Insufficient pollution: __have__ / __need__ (have / need).`

## Obstruction guard

- The hive does not deconstruct trees, rocks, or cliffs.
- `placement_obstructed(entity)` runs `surface.find_entities_filtered{ area = entity.bounding_box, type = {"tree", "cliff", "simple-entity"} }` and returns true if anything other than the placed entity sits in the box. As a side effect it also calls `cancel_deconstruction` on any obstruction the engine had auto-marked for the hive force, otherwise a hive worker would dispatch to chop the tree we just declined to build over and then hover indefinitely (hive storage is a passive-provider chest and won't accept bot inserts).
- Direct placements are refused before charging (item refunded, entity destroyed, message printed). Ghost placements are refused inside `fulfill_ghost`.
- Hive-side entities carry the `"not-deconstructable"` prototype flag (data/prototypes/entities.lua → `lock_decon`), so the engine refuses any deconstruction mark up front. There is no `on_marked_for_deconstruction` handler — the prototype flag is the single mechanism. Earlier versions had a script-side cancel-on-mark loop; it was removed because Factorio 2.0 raises when `cancel_deconstruction(force)` is called for a force that isn't authorised to cancel the mark on that entity, and because the prototype flag is a simpler, race-free contract anyway.

## Recipes

- All player-facing recipes have zero ingredients and craft in ≤0.5s.
- Recipe enabling is gated on the matching technology.
- Trigger-flagged techs (`hm-hive-spawners`, `hm-hive-labs`) are flipped to researched by gameplay events; the same event explicitly enables the gated recipes (belt-and-braces).
- `Force.configure(force)` runs on `on_init`, `on_configuration_changed`, and any new hive force creation. It disables every recipe, then re-enables the always-available set plus anything whose tech is already researched. It also sets `tech.enabled = true` only for `hm-` techs and `false` for everything else, which hides the vanilla tree on the hive force (vanilla techs default to `visible_when_disabled = false`).

## Creep

- A single `hm-creep` tile (royal-purple sand-1 reskin) is placed by the script's `Creep.tick` loop.
- Growth is a deterministic Chebyshev ring fill: each hive/node walks rings outward from its centre, layer 0 (centre) → layer N (the 8N tiles at Chebyshev distance N). Layer order traces a prime-stride permutation (1009) so within-ring placement looks scattered rather than a clockwise sweep, but the bound is the exact axis-aligned box.
- Cursor (`creep_layer`, `creep_step`) lives on the hive's storage record and on each hive_node's record.
- Water and void terminate growth at that tile but do not stop the ring.
- Edge fuzzing: a deterministic per-tile hash (`tile_noise(tx, ty)` over world coordinates) gates placement on the outermost rings so the silhouette breaks free of a perfect square without producing fingers. Interior layers (layer ≤ max_radius − 2) always place. Layer max_radius − 1 places at ~90%, layer max_radius at ~65%, and a single extension ring at max_radius + 1 places at ~30%. The hash is pure over (tx, ty), so save/load reproduces the same edge pattern; growth stops one ring beyond max_radius.
- Once a hive or node's cursor passes the extension ring (`creep_layer > max_radius + 1`), `Creep.tick` short-circuits its iteration for that member — fully-grown rings cost nothing in the tick loop. Without this, the outer loop kept walking every hive on every 3-tick tick even though `place_organic_creep` itself returned immediately.

## Hive Supremacy

When `hm-hive-supremacy` is researched, a damage tick inflicts damage on anything standing on the hive's creep tile that isn't an approved inhabitant.

- Tech is a single-shot manual research; recipe-style gating only — no in-progress effect, no infinite scaling.
- An entity is **immune** if any of these hold: `entity.force == hive force`, or `entity.type` is in `{"unit","unit-spawner","turret"}` AND its name is a vanilla biter / spitter / spawner / worm-turret, or the entity's prototype is a hive prototype (`shared.entities.*`).
- Damage cadence: `intervals.supremacy = 60` ticks. Candidate scan cadence: `supremacy.candidate_scan = 600` ticks per hive.
- Cache: `state.supremacy_candidates[hive_unit_number] = { [entity_unit_number] = { entity, lifetime_seconds, is_tree, pollution_burst } }`.
- **Damage tick** walks the cached set, drops `not entity.valid`, runs a chunk-bbox creep check (no per-entity `surface.get_tile`), and applies `entity.damage(amount, hive_force, "physical")`. Amount is tuned so a default tree dies in ~`shared.supremacy.tree_lifetime` seconds (≈30s) and a default building in ~`shared.supremacy.building_lifetime` seconds (≈60s). Lifetime → per-tick damage uses each prototype's `max_health` and the cadence: `damage_per_tick = max_health / (lifetime_seconds × calls_per_second)`.
- **Candidate scan** rebuilds the cache from `find_entities_filtered{ area, force = {player, neutral} }` over each hive's bbox — entities outside the recruit-box union never appear. Piggy-backs on the unified scan when cadences align (every 10th unified scan).
- Trees: when supremacy kills a tree we read its prototype's `emissions_per_second` / `pollution` field if present, otherwise fall back to `shared.supremacy.tree_pollution_default`, and call `surface.pollute(position, amount)` so the world's vanilla pollution map absorbs it. The hive's resource pool is **not** directly credited; the burst feeds recruitment via vanilla pollution-driven spawner activity.
- The tech itself: `hm-hive-supremacy` lives in `data/prototypes/technologies.lua`, costs `shared.supremacy.research_packs` Pollution Science Packs, prerequisite `hm-hive-labs`, single `nothing` effect with the localised description.

## Eligibility registry

- `remote.add_interface("hive_reboot", { register_creature_role, unregister_creature_role, join_hive })`.
- Default classifier: any entity with `type == "unit"` is eligible for `attract` and `store`.
- Modded callers can register or unregister specific entity names against the `attract`, `store`, `consume` roles independently.

## Lab supply

- `Lab.tick_supply` runs every `shared.intervals.supply` ticks (1s).
- For each `hm-hive-lab` below the science-pack threshold, find its serving network, charge `shared.science.pollution_per_pack` from the pool, insert one pack into the lab.

## Research tree

- Hive Spawners (auto-researched on first hive) unlocks Hive Nodes, Biter Spawners, and Spitter Spawners.
- Hive Labs (auto-researched on first creep spread) unlocks Hive Labs.
- Worm tier techs are researched manually, gated in order.
- `hm-attraction-reach` is infinite: each completed level adds `shared.attraction_reach_step` (10%) to the recruitment radius. The effect is applied at runtime in `script/creatures.lua`; the `nothing` effect on the prototype is purely for the GUI description.
- `hm-pheromone-vent` is a single-shot tech, prerequisite `hm-worms-small`, that unlocks the `hm-pheromone-vent` recipe.
- `hm-attack-group-size` is infinite, prerequisite `hm-pheromone-vent`. Each completed level adds `pheromone_vent.tech_increment` (default 2) to `pheromone_vent.base_size`. Read at dispatch time as `tech_adjusted_base = base_size + tech_increment × completed_levels`. The `nothing` effect on the prototype is purely for the GUI description.

## Performance — unified scan, work-spread

- Cadence target: `intervals.scan = 60` ticks (1s). Replaces today's `intervals.recruit = 120` and `intervals.absorb = 30` — recruit and absorb fire from the unified scan instead. Other intervals (`intervals.workers`, `intervals.creep`, `intervals.labels`, `intervals.loadout`, `intervals.supply`) are unchanged.
- Each tick processes `ceil(N / T)` network members (hives + hive-nodes) on a rotating index, sorted deterministically by `unit_number`. N = total hives + hive-nodes. Per-tick scan count constant relative to network size — no moloch supertick.
- Per processed member: one `find_entities_filtered` over its bbox; in-Lua dispatch to recruit / absorb / supremacy candidate registration / spawner counting (for the trickle rate of the member's network).
- Pheromone-vent arrival scan runs on the same cadence and work-spreading: each tick processes `ceil(V / T)` vents (V = total pheromone vents). Per processed vent: one `find_entities_filtered{ position = vent.position, radius = pheromone_vent.arrival_radius, force = hive_force, type = "unit" }`.

### Cross-hive aggregation

- Pre-bucket hives by surface once per scan tick.
- For force=`{player, neutral}` scans (supremacy, vent intake), do one combined scan per surface; dispatch to hives in Lua. Reduces engine ↔ Lua boundary crossings.

## Performance — node absorption

- `tick_absorption` iterates hives **and** hive nodes.
- Nodes have no chest of their own; absorbed creatures are inserted into the network's primary chest (smallest `unit_number` hive in the network).
- Reuse existing `is_for_role` filter.

## Performance — workers from nodes

- `Workers.tick()` spawn entity = closest in-network hive **or** hive node to the ghost.
- Shared `find_non_colliding_position` helper for hive + node spawn points.

## Performance — caching and lazy ticks

- `node_data.nearest_hive_unit_number`: cache. Invalidate on hive build / death and on `on_configuration_changed`. Lazy recompute on stale.
- `Workers.tick()`: skip when `state.worker_jobs` is empty AND no hive-force ghosts exist on any surface.

## Network collapse

- Trigger: `Death.on_removed` for a `hm-hive`.
- Surviving-hive detection must use `Hive.all()`, not just `s.hives_by_player`. `Hive.all()` queries the surface and picks up a just-placed-but-untracked replacement hive. Using only player-bucket state would falsely collapse the network on every legitimate repositioning (the new hive is in the world but not yet `Hive.track`'d at the moment `Death.on_removed` runs).
- Connectivity walk starts from each surviving hive, not from the destroyed hive's neighbours. Orphan set = `(all hive-force buildings on surface) − (union of network components of surviving hives)`. New hive close enough → old neighbours stay reachable, no orphans. New hive too far → old neighbours genuinely orphaned. No replacement → all orphaned.
- Pheromone vents are matched into the orphan set by resolving each vent's `placer_player_index` → placer's current hive → that hive's network. Vents whose placer has no surviving hive (or whose placer's hive is in an orphaned component) are orphaned.
- Orphan scope is hive force only. Player-placed spawners / worms live on the enemy force after the build-time swap and survive the collapse as ordinary vanilla nests/turrets.
- For each orphaned entity (all on hive force):
  - Hive nodes, pheromone vents, hive labs, hive storage chests: `entity.destroy({ raise_destroy = true })` so removal flows through the existing pipeline. Hive storage: release creature contents as live units first.
  - Hive workers (in flight or idle) on the orphaned network: `entity.die()` so worker-death cleanup runs.
- Drop `state.recruit_buckets[orphan_key]` and `state.pheromone_vents[orphan_unit_number]` for orphaned members.
- Re-resolve any other network keys that share a `network_key` with the orphan, in case the collapse changed the smallest-unit_number anchor.

## Telemetry

Two log lines, both gated on the `hm-debug-telemetry` startup setting (default **off**), written to `script-output/hm-debug.txt`. The setting is read via `shared.feature_enabled("hm-debug-telemetry")` at flush time so end users get a quiet save folder by default; turn it on for tuning sessions.

```
[recruit] tick=N networks=K tokens=[t1,t2,...] R=[r1,r2,...] spawners=[s1,s2,...] group=G trickle=T skipped=S
[perf]    tick=N scanned=M recruit_ms=… absorb_ms=… supremacy_ms=… workers_ms=… creep_ms=… total_ms=…
```

`scanned` is how many network members (hives + hive-nodes) the unified scan processed this tick — work-spreading visibility.

## Tunables (shared.lua)

| Name | Default | Notes |
|---|---|---|
| `recruit.per_spawner_per_second` | 0.05 | trickle rate per spawner in network range |
| `recruit.bucket_cap_factor` | 5 | bucket cap = 5 × R, where R = spawner_count × per_spawner_per_second |
| `recruit.gate_attack_groups` | false | attack-group biters bypass bucket |
| `intervals.scan` | 60 | unified scan cadence |
| `intervals.supremacy` | 60 | damage cadence |
| `supremacy.candidate_scan` | 600 | candidate rebuild cadence per hive |
| `supremacy.tree_lifetime` | 30 | tree death time on creep, in seconds |
| `supremacy.building_lifetime` | 60 | building death time on creep, in seconds |
| `supremacy.research_packs` | 200 | hm-hive-supremacy science cost |
| `pheromone_vent.base_size` | 5 | base attack-group size |
| `pheromone_vent.tech_increment` | 2 | per level |
| `pheromone_vent.mode_factor` | `{small=0.5, default=1.0, large=2.0}` | |
| `pheromone_vent.arrival_radius` | 3 | tiles |

## Debug fixtures

- **Pollution Vent** (`hm-pollution-generator`): an iron-chest reskin that emits world pollution at ~1000 active drills' worth per tick. Recipe is currently always available; gate behind a startup setting before shipping.
- **`script-output/hm-debug.txt`**: appended once per scan tick. Should also be gated.
