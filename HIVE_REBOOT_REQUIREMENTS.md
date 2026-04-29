# Hive Mind Reloaded — Requirements

You play a hive mind, not an engineer. You direct biters instead of crafting circuits.

## Player flow

1. Press **Join the Hive**. Your body disappears. You become a director with no inventory and no way to fight.
2. Craft and place a **Hive**. This is your foothold.
3. The Hive attracts biters from across the map. They walk in and get absorbed.
4. Ghost-place buildings. Hive workers (visible biters) build them, paying with absorbed creatures.
5. Place **Hive Labs** to do research. They consume creatures to make science.
6. Research worm tiers and other upgrades.

## Rules

- Joining the hive is permanent for the session.
- One Hive per player. Placing a new one destroys the old one.
- A destroyed Hive releases all its stored creatures back into the world as living units.
- All hive creatures, recruited biters, and vanilla biters are friendly to each other.
- The player can place buildings, place ghosts, and craft pheromones. Nothing else.

## Buildings

- **Hive** — always available. Your one starter.
- **Hive Node** — extends the network. Unlocks when the first Hive is placed.
- **Biter Spawner** — produces units. Unlocks when the first Hive is placed.
- **Hive Lab** — research. Unlocks when creep first spreads.
- **Worm turrets** (small → behemoth) — defenses. Each tier unlocks via research.
- **Anything else** — vanilla and modded buildings can also be ghost-placed; the hive pays for them.

## Pheromones

- Two recipes: **Release Pheromones** (gives you a pheromone item) and **Withdraw Pheromones** (consumes the item).
- While you carry a pheromone item, biters converge on you instead of the Hive.
- Crafting the off recipe is the only way to stop attracting them.

## Network

- Each Hive recruits creatures from across the map.
- Each Hive and Hive Node has a local construction zone where it builds. Connected zones extend the network.
- Connected hives and nodes share one resource pool.
- Both grow purple **creep** organically out from their footprint. Biters walk faster on creep.

## Cost

- Every absorbed creature is worth some pollution.
- Every build and every science pack costs pollution.
- The hive spends creatures to pay. The player never handles pollution directly.

## Research

- All research uses **Pollution Science Packs**.
- Hive Spawners and Hive Labs unlock from gameplay events (placing a hive, spreading creep) rather than manual research.
- Worm tiers are researched manually in order.

## Non-goals

- No old-save compatibility.
- No converting vanilla nests.
- No replacing vanilla spawners.
- No population cap.
- No leaving the hive.

---

Implementation choices, internal entity names, and engine-level details live in [HIVE_DESIGN.md](HIVE_DESIGN.md).
