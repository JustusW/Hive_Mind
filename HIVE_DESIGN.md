# Hive Mind Reloaded — Design Notes

Implementation choices and engine-level details that the requirements doc deliberately leaves out. Read [HIVE_REBOOT_REQUIREMENTS.md](HIVE_REBOOT_REQUIREMENTS.md) first.

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

## Director loadout

- A watchdog tick every `shared.intervals.loadout` ticks ensures every hive director has at least one of every currently-buildable item in their main inventory and pins them to the quickbar in a stable order.
- "Currently buildable" means the gating recipe is enabled on the hive force. New buildings unlocked by research therefore appear in the loadout within a watchdog tick (or immediately on join / respawn).
- After a successful placement the cursor is auto-refunded (cursor first, main inventory fallback) so the player can keep dropping buildings without re-crafting.

## Building map

| Player item | Built entity | Notes |
|---|---|---|
| `hm-hive` | `hm-hive` | Roboport prototype. Build / visibility: 100×100 box. 20 robot slots, 200 material slots, void-powered. |
| `hm-hive-node` | `hm-hive-node` | Roboport prototype. Build / visibility: 50×50 box. No robots or material of its own. |
| `hm-hive-lab` | `hm-hive-lab` | Lab prototype. Only accepts `hm-pollution-science-pack`. |
| `hm-biter-spawner` | vanilla `biter-spawner` | Player places a tinted proxy ghost (`hm-spawner-ghost`); `on_built_entity` swaps it for a real `biter-spawner` on the enemy force. |
| `hm-spitter-spawner` | vanilla `spitter-spawner` | Same proxy mechanic via `hm-spitter-spawner-ghost`. |
| `hm-{tier}-worm` | vanilla `{tier}-worm-turret` | Same proxy mechanic, one ghost per tier. |
| `hm-pollution-generator` | `hm-pollution-generator` | Debug pollution emitter, free to place. |

## Visual style

Every hive-side entity (hive, hive node, hive lab, hive storage chest, hive worker) is a colored variant of the biter spawner sprite. No roboport, lab, or chest sprites should appear. The underlying prototype stays whatever makes the mechanics work; only the rendered visuals are swapped.

Color anchors: hive = orange-red, hive node = teal, hive lab = purple, hive storage = orange-red, biter spawner proxy = orange-red, spitter spawner proxy = lime, worm proxies = purple shades by tier.

## Hive workers

- `hm-construction-robot` is a `construction-robot` prototype reskinned with small-biter sprites. Visible, fast, invincible.
- `tick_robots` tops every hive's robot inventory back to `shared.hive_robot_count` on a 3-second interval.
- When a worker delivers an item, `on_robot_built_entity` destroys it using the biter death animation rather than a silent removal.

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

## Recruitment

- `Creatures.tick_recruitment` runs every `shared.intervals.recruit` ticks. It scans for `type == "unit"` entities on the enemy and hive forces around every recruiter on the surface and reassigns matched units to the hive force, then commands them to walk somewhere.
- A "recruiter" is any hive or hive node. Recruit radius is `shared.ranges.hive * reach_factor` for hives and `shared.ranges.hive_node * reach_factor` for nodes, where `reach_factor = 1 + completed_attraction_reach_levels * shared.attraction_reach_step`.
- Targeting:
  - Pheromone player present → unit walks to the player's current position.
  - Recruited from a hive → unit walks to that hive.
  - Recruited from a node → unit walks to the nearest hive on the same surface (nodes have no chest, so absorption only happens at hives).

## Build cost

- `shared.build_costs[entity_name]` is an explicit override table for hive-tier entities.
- Anything else: `cost = sum(ingredient.amount * shared.item_pollution_factors[ingredient.name])` from the recipe that produces the entity's place-item.
- For spawners and worms, the cost is keyed on the proxy entity. The post-swap real entity does not re-charge.

## Cost charging

- `Cost.pollution_capacity(hives)` sums every chest's existing pollution plus the value of every stored creature. This is read-only and used as a pre-check.
- `Cost.consume(surface, position, amount)` resolves the network, computes capacity, and only mutates state on the success path. If capacity is short it returns `false, "insufficient", {need, have}` without converting any biters.
- `Cost.convert_creatures` consumes the minimum number of biters needed to reach the target — no surplus burn.
- **Direct path**: `on_built_entity` for a real entity → `charge_or_refund` runs the consume. Failure refunds the item to the player's cursor and destroys the entity. Success refunds the item too (the cursor is intentionally infinite — pollution is the real cost).
- **Ghost path**: `on_built_entity` for an `entity-ghost` → `fulfill_ghost` runs tech / obstruction / consume guards; any failure destroys the ghost so the world doesn't accumulate dead ghosts.
- Failure messages report the actual gap: `Insufficient pollution: __have__ / __need__ (have / need).`

## Obstruction guard

- The hive does not deconstruct trees, rocks, or cliffs.
- `placement_obstructed(entity)` runs `surface.find_entities_filtered{ area = entity.bounding_box, type = {"tree", "cliff", "simple-entity"} }` and returns true if anything other than the placed entity sits in the box. As a side effect it also calls `cancel_deconstruction` on any obstruction the engine had auto-marked for the hive force, otherwise a hive worker would dispatch to chop the tree we just declined to build over and then hover indefinitely (hive storage is a passive-provider chest and won't accept bot inserts).
- Direct placements are refused before charging (item refunded, entity destroyed, message printed). Ghost placements are refused inside `fulfill_ghost`.
- `Director.on_marked_for_deconstruction` cancels any deconstruction order keyed to the hive force regardless of whether a player triggered it (hive force never deconstructs).

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

## Debug fixtures

- **Pollution Vent** (`hm-pollution-generator`): an iron-chest reskin that emits world pollution at ~1000 active drills' worth per tick. Recipe is currently always available; gate behind a startup setting before shipping.
- **`script-output/hm-debug.txt`**: appended once per recruit tick. Should also be gated.
