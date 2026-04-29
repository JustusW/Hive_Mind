# Hive Mind Reloaded — Design Notes

Implementation choices and engine-level details that the requirements doc deliberately leaves out. Read [HIVE_REBOOT_REQUIREMENTS.md](HIVE_REBOOT_REQUIREMENTS.md) first.

## Forces

- One `hivemind` force. All hive players, all recruited creatures, all script-spawned biters live here.
- Mutual cease-fire and friend with `enemy` and `spectator` forces.
- The friend flag is what lets recruited biters mingle with vanilla biters without fighting.

## Player controller

- `set_controller({type = defines.controllers.god})` on join.
- Inventory is cleared on join and on any change to gun / ammo / armor inventories.
- A custom permission group blocks mining, dropping, and inventory transfer actions.
- Mining attempts queue the entity for re-creation and print a chat message.
- Deconstruction marking is intercepted and cancelled.

## Building map

| Player item | Real entity placed | Notes |
|---|---|---|
| `hm-hive` | `hm-hive` | Roboport prototype. Ghost-build / map visibility: 100×100 tile box. Recruitment scan: 1000 tiles. 20 robot slots, 200 material slots, void-powered. |
| `hm-hive-node` | `hm-hive-node` | Roboport prototype. Ghost-build / map visibility: 50×50 tile box. No robots or material of its own. |
| `hm-hive-lab` | `hm-hive-lab` | Lab prototype. Only accepts `hm-pollution-science-pack`. |
| `hm-biter-spawner` | `biter-spawner` | Player places the item; script ends up with a real `biter-spawner` on the enemy force. Use whichever proxy / placement trick makes this work. |
| `hm-{tier}-worm` | `{tier}-worm-turret` | Same outcome as the spawner. Use whichever proxy / placement trick makes this work. |

## Visual style

Every hive-side entity (hive, hive node, hive lab, hive storage chest, hive worker) is a colored variant of the biter spawner sprite. No roboport, lab, or chest sprites should appear. The underlying prototype stays whatever makes the mechanics work; only the rendered visuals are swapped.

Color suggestions: hive = orange-red, hive node = teal, hive lab = purple, hive storage = orange-red.

## Hive workers

- `hm-construction-robot` is a `construction-robot` prototype reskinned with small-biter sprites. Visible, fast, invincible.
- `tick_robots` tops every hive's robot inventory back to `shared.hive_robot_count` on a 3-second interval.
- When a worker delivers an item, `on_robot_built_entity` destroys it using the biter death animation rather than a silent removal.
- Aspirational: long-term the worker should behave like a wiggler (movement / animation). Sprite swap is sufficient for now; this is a low-priority follow-up.

## Storage

- Each hive owns an `hm-hive-storage` passive-provider chest, spawned adjacent on hive placement. Visually, a colored spawner (see Visual Style above) — no chest sprite.
- The chest holds:
  - `hm-creature-<unit-name>` items — one per absorbed unit, hidden.
  - `hm-pollution` items — hidden currency, stack 10000.
- Chest is `not-blueprintable` and `not-deconstructable`. Inspectable but not meant to be managed.
- On hive death the chest's creature contents are first respawned as living units on the hive force, then the chest is destroyed. Any pollution overflow is discarded.
- On `on_configuration_changed`, missing chests are recreated.

## Network resolver

- A "network" is the set of hive + hive-node entities whose construction radii overlap, scoped to the hive force and the same surface.
- Cost reads and writes treat the union of all member chests as one virtual inventory.
- Cost satisfaction tries `hm-pollution` first; if short, converts `hm-creature-X` items to pollution on demand using each creature's `absorptions_to_join_attack.pollution` value (default 1).

## Build cost

- `shared.build_costs[entity_name]` is an explicit override table for hive-tier entities.
- Anything else: `cost = sum(ingredient.amount * shared.item_pollution_factors[ingredient.name])`.
- `shared.item_pollution_factors` defaults: `iron-plate=1`, `copper-plate=1`, `gear=2`, `electronic-circuit=5`, `advanced-circuit=15`. Unknown items get a configurable fallback.
- For spawners and worms, the cost is keyed on the proxy entity. The post-swap real entity does not re-charge.

## Cost charging

- **Ghost path**: `on_built_entity` for `entity-ghost` → `fulfill_ghost` looks up cost, charges the network, inserts a fulfillment item into the chest.
- **Direct path**: `on_built_entity` for hive-tier entities → same `consume_hive_pollution` call. If unpayable, destroy the entity and refund one item to the player's main inventory.
- Insufficient funds at ghost time leaves the ghost up for a later attempt.

## Recipes

- All player-facing recipes have zero ingredients and craft in ≤0.5s.
- Recipe enabling is gated on the matching technology.
- Trigger-flagged techs (`hm-hive-spawners`, `hm-hive-labs`) are flipped to researched by gameplay events; the same event also explicitly enables the gated recipes (belt-and-braces).
- `configure_hive_force` runs on `on_init`, `on_configuration_changed`, and any new hive force creation. It disables every recipe and tech, then re-enables the always-available set plus anything whose tech is already researched.

## Creep tile

- `creep` is a custom tile (tinted sand-1) with vanilla biter walking speed bonus and zero pollution absorption.
- Multiple variants in different shades of purple, placed at random across creep'd ground for visual texture.
- `tick_creep` runs every 3 game ticks. Growth is randomized rather than a clean square ring — pick a handful of random angles from the source structure each tick and advance the creep front along each ray. Skips water and existing creep. The result should look organic and uneven.

## Eligibility registry

- `remote.add_interface("hive_reboot", { register_creature_role, unregister_creature_role, join_hive })`.
- Default classifier: any entity with `type == "unit"` is eligible for `attract` and `store`.
- Modded callers can register or unregister specific entity names against the `attract`, `store`, `consume` roles independently.

## Lab supply

- `supply_labs` runs every `shared.intervals.supply` ticks (1s).
- For each `hm-hive-lab` below the science-pack threshold, find its serving network, charge `shared.science.pollution_per_pack` from the pool, insert one pack into the lab.

## Debug fixtures

- **Pollution Vent** (`hm-pollution-generator`): an iron-chest reskin that emits world pollution at ~1000 active drills' worth per tick. Recipe is currently always available; gate behind a startup setting before shipping.
- **`script-output/hm-debug.txt`**: appended once per recruit tick. Should also be gated.
