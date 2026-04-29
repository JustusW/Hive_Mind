# Hive Mind Reloaded

A Factorio mod where you leave your engineer life behind and direct a biter hive.

## How it works

1. Press **Join the Hive** to become the hive director (god-mode, no physical body). Or **Reject the Hive** to opt out permanently — both buttons live next to each other and disappear once you commit.
2. Place a **Hive** — your construction and logistics backbone. The cursor auto-refills after each placement, and currently-buildable items are pinned to your quickbar.
3. The hive draws nearby biters in; absorbed units become stored creatures and a floating label above each hive shows the network's available pollution.
4. Place hive structures (Nodes, Labs, Spawners, Worms). The hive pre-checks the network's pollution pool and only consumes biters/pollution when the build can actually be paid for.
5. Place a **Hive Lab** and research through the hive-only tech tree using Pollution Science Packs that the lab supplies itself.
6. Place **Hive Nodes** to extend the construction/logistics box outward.

## Buildings

| Item | Built entity | Footprint | Cost (pollution) | Notes |
|---|---|---|---|---|
| Hive | `hm-hive` | 100×100 box | free | Roboport mechanics, recruits creatures, stores them, funds the network |
| Hive Node | `hm-hive-node` | 50×50 box | 100 | Extends construction / logistics |
| Hive Lab | `hm-hive-lab` | — | 150 | Researches hive techs |
| Biter Spawner | vanilla `biter-spawner` | — | 500 | Hive-friendly biter spawner on the enemy force |
| Spitter Spawner | vanilla `spitter-spawner` | — | 500 | Hive-friendly spitter spawner on the enemy force |
| Small / Medium / Big / Behemoth Worm | vanilla worm turrets | — | 200 / 350 / 600 / 1000 | Tier-gated defences |
| Pollution Vent (debug) | `hm-pollution-generator` | — | free | Vents 1000 drills' worth of pollution per tick |

Connected hives and hive nodes share one resource pool — the hive that pays for a build can be any in-network hive, not necessarily the closest.

## Creep

A single purple creep tile fills outward from each hive (100×100 box) and node (50×50 box) as Chebyshev rings, growing from the centre rather than as random rays. Biters move faster on creep.

## Pheromones

Two recipes: **Release Pheromones** gives you a lure item; **Withdraw Pheromones** consumes it. While you carry a pheromone item, recruited creatures converge on you instead of the hive.

## Research

The tech tree shows hive research only — vanilla research is hidden on the hive force. The available branches:

- **Hive Spawners** (auto-researched on first hive) unlocks Hive Nodes, Biter Spawners, and Spitter Spawners.
- **Hive Labs** (auto-researched on first creep spread) unlocks Hive Labs.
- **Worm tiers** — manual research, one tech per tier.
- **Attraction Reach** — infinite tech, +10% recruitment radius per level.

## Build flow

- Successful placements auto-refund the cursor so a long row of nodes never ends with you accidentally placing a ghost.
- Tooltips on every placeable item show the pollution cost.
- If the network can't pay, the placement is refused with `Insufficient pollution: 30 / 100 (have / need).` — biters are not consumed on a failed build.
- Placements on top of trees, rocks, or cliffs are refused — the hive does not deconstruct.
- Ghosts that cannot be fulfilled (tech missing, obstruction, insufficient pollution) are destroyed instead of left lingering.

## Dev workflow

See [DEVELOPMENT.md](DEVELOPMENT.md) for helper scripts and the isolated dev profile setup.

## Spec

- [HIVE_REBOOT_REQUIREMENTS.md](HIVE_REBOOT_REQUIREMENTS.md) — player-facing intent.
- [HIVE_DESIGN.md](HIVE_DESIGN.md) — implementation choices and engine details.

## Legacy reference

The original Hive Mind 2.0 port is archived under [legacy/hive-mind-2.0-port-reference](legacy/hive-mind-2.0-port-reference) for art/balance reference only.
