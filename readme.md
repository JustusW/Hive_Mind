# Hive Mind Reloaded

A Factorio mod where you leave your engineer life behind and direct a biter hive.

## How it works

1. Press **Join THE HIVE** to become the hive director (god-mode, no physical body).
2. Craft and place a **Hive** — your construction and logistics backbone.
3. The hive recruits nearby and distant biters automatically; they walk to it and are absorbed as stored creatures.
4. Place building ghosts. The hive consumes stored creatures to pay for construction and dispatches biter-robots to build them.
5. Place a **Hive Lab** and research through hive technologies using Pollution Science Packs, which the hive supplies from its creature stores.
6. Place **Hive Nodes** to extend your construction and logistics network.

## Economy in brief

- Vanilla pollution drives vanilla spawners → biters populate the map.
- The hive recruits those biters (switches them to hivemind force, commands them to walk in).
- Absorbed biters become `hm-creature-*` items visible in the hive's material inventory.
- Building ghosts and science packs consume those creature items (converted to a pollution value).

## Structures

| Structure | Build / visibility | Recruitment | Purpose |
|---|---|---|---|
| Hive | 100×100 tile box | 1000 tiles | Recruits creatures, stores them, funds construction and science |
| Hive Node | 50×50 tile box | — | Extends the construction/logistics network |
| Hive Lab | — | — | Researches hive technologies using Pollution Science Packs |

Connected hives and hive nodes share one resource pool — the hive that pays for a build can be any in-network hive, not necessarily the closest.

## Dev workflow

See [DEVELOPMENT.md](DEVELOPMENT.md) for helper scripts and the isolated dev profile setup.

## Spec

- [HIVE_REBOOT_REQUIREMENTS.md](HIVE_REBOOT_REQUIREMENTS.md) — player-facing intent.
- [HIVE_DESIGN.md](HIVE_DESIGN.md) — implementation choices and engine details.

## Legacy reference

The original Hive Mind 2.0 port is archived under [legacy/hive-mind-2.0-port-reference](legacy/hive-mind-2.0-port-reference) for art/balance reference only.
