# Hive Mind Reworked — Working requirements (0.9.0)

Pending player-facing intent for 0.9.0. Merge into [requirements.md](requirements.md) on release. Implementation choices live in [working_design.md](working_design.md).

## Recruitment

- Without pollution: a steady trickle of biters wanders into the network. Trickle rate scales with the number of spawners (any `unit-spawner`, hive-placed or wild) inside the network's combined recruit range. Default `0.05/sec per spawner`. More spawners in range → more biters available; no spawners → no trickle.
- The trickle pool is shared across all hives, hive nodes, and pheromone vents in the network.
- With pollution: any biter the engine attached to an attack group is recruited immediately, no quota, on top of the trickle.
- Pheromones still override.

## Pheromone Vent

- Recoloured hive node sprite (deep red).
- Buildable anywhere. No network range requirement. No pollution cost.
- Belongs to the network of the placing player's hive. If the player has no hive when placing, the vent dies on placement. If the player's hive is later destroyed without replacement (network collapse), the vent dies with the network.
- No recruitment range of its own. Diverts the network's incoming biter stream to itself, the same way pheromones divert it to a player.
- Gathers biters until `attack_group_size` arrive, then forms an autonomous attack group via the engine. The hive does not target — the engine routes the group.
- Trade-off is opportunity cost: every biter diverted is one the hive doesn't absorb. Place too many and the network starves.
- Per-vent mode: `small` / `default` / `large`. Multiplies `attack_group_size` by `0.5×` / `1×` / `2×`. Set via marker-item recipe (same UX as pheromones).

## Crafting menu

- Pheromone Vent recipe — intermediate products tab (same place as the other hive buildings).
- Pheromone Vent mode markers (`small` / `default` / `large`) — production tab (same place as the existing pheromone on/off recipes).

## Tech

- `hm-pheromone-vent` — unlocks the pheromone vent recipe. Prerequisite `hm-worms-small`.
- `hm-attack-group-size` — infinite, `+2` size per level. Cost ramps like Attraction Reach. Prerequisite `hm-pheromone-vent`.

## Non-goals

- Custom targeting in any form. No pings, no markers, no aim.
- Group composition control.
- Group recall.

## Network collapse

- When the last hive in a network is destroyed, every other hive-side building in that network is destroyed too: hive nodes, pheromone vents, hive labs, hive storage chests.
- Hive workers belonging to the collapsed network die.
- Existing per-hive death rule still applies: storage chests release stored creatures as live units before destruction.
- Player-placed biter/spitter spawners and worm turrets are **not** destroyed. They live on the enemy force after the build-time swap and stay where they were. The hive can re-claim them by building a new hive within recruitment range — same as any wild nest.

## Performance

- Game stays smooth at large network sizes. Per-tick cost stays bounded regardless of hive count.
