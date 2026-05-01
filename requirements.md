# Hive Mind Reworked — Requirements

You play a hive mind, not an engineer. You direct biters instead of crafting circuits.

## Player flow

1. Press **Join the Hive** to commit, or **Reject the Hive** to opt out permanently. Either choice removes both buttons from the GUI; rejection prints a one-line obituary and leaves you alone.
2. After joining you become a director with no physical body — the only items you carry are the buildings the hive has unlocked. Those items are pinned to your quickbar and refilled on a watchdog tick.
3. Place a **Hive**. This is your foothold; recruitment and the construction network are anchored here.
4. The hive draws biters in. They walk in and get absorbed; a floating label above each hive shows the network's available pollution.
5. Place buildings directly (the cursor refills after each placement) or ghost-place them. Either way the hive turns the placement into a ghost and dispatches a **hive worker** — a ground-bound wiggler-shaped unit — to walk from the nearest hive and materialise it on arrival. The hive is the one exception: it is built directly by the player because no workers exist before the first hive lands.
6. Place **Hive Labs** to research. They consume creatures to make Pollution Science Packs.
7. Research worm tiers, the infinite Attraction Reach, and other upgrades. Vanilla research is hidden — only the hive tree is visible.
8. When **Pheromones** are active, hives disgorge stored creatures back into the world and send them toward the pheromone carrier instead of absorbing them.

## Rules

- Joining the hive is permanent for the session. Rejecting is also permanent — buttons never return.
- **Hive Anchor Binding** (startup setting, default **off**) — when enabled the hive is anchored: every player gets one Hive item on join, places it once, and that hive cannot be mined after construction. There is no recipe to craft another. Additional hives only exist via the Promote Node action (see "Promotion"). When the setting is **off** the legacy behavior applies: the Hive recipe is freely available, placing a new hive destroys the previous one, and the player can re-place the hive at will.
- A destroyed Hive releases all its stored creatures back into the world as living units. With Anchor Binding on, if all your hives are destroyed the network collapses but you receive a fresh Hive item — the hive force is endless (see "Anchor placement"). With Anchor Binding off, the player just crafts another from the recipe.
- All hive creatures, recruited biters, and vanilla biters are friendly to each other.
- The director can place hive buildings, place ghosts of any buildable hive item, and craft pheromones. Nothing else.
- Placements on top of trees, rocks, or cliffs are refused — the hive does not deconstruct terrain.
- Ghosts that can't be fulfilled (missing tech, obstruction, insufficient pollution) are destroyed rather than left lingering.

## Anchor placement

This section describes behavior when the **Hive Anchor Binding** startup setting is enabled. When the setting is off the section does not apply: the Hive recipe is always available, placement is instant, the hive is freely minable, and re-placing destroys the previous hive (legacy 0.9.16 behavior).

- On join you receive a single Hive item. Scout the map (you're on the god controller — fly anywhere, no time pressure) and pick your spot carefully.
- Placing the Hive starts a **30-second construction**. A chat message warns you: "Hive construction started. It is extremely hard to move and will permanently bind your hive to this position." The construction is firm — there is no cancellation. The 30 seconds exist as a commitment window: enough time to think "wait, this is the wrong spot" before the engineer can react, but not enough time to relocate cheaply.
- Once the 30 seconds elapse the hive becomes live: recruitment starts, creep starts spreading, the storage chest activates, and the hive can no longer be mined. The placement is permanent.
- The network only collapses when **every** hive in it is destroyed. Losing one hive (anchor or promoted) while another survives keeps the network alive: the dead hive's storage merges into the surviving hives' shared pool, the network continues operating from whoever remains. Storage is shared across every hive in the network — there is one effective resource pool, not one per hive.
- The hive is endless: if all your hives are destroyed, the network collapses (existing rule) and you receive a fresh Hive item to plant a new anchor wherever you choose. Losing the network is painful — pollution and creature stockpile are gone, the standing creep is now useless terrain, and the new anchor's 30-second construction restarts the commitment cycle — but it is not run-ending.

## Buildings

- **Hive** — your anchor, rendered as a Gleba egg raft even when Space Age is not loaded. One per player, given on join, placed once, non-minable after construction. See "Anchor placement".
- **Hive Node** — extends the network. Unlocks when the first Hive is placed. Rendered as a small Gleba egg raft. Subject to the **evolution-gated node count** (see "Network").
- **Biter Spawner** — produces biters. Unlocks when the first Hive is placed.
- **Spitter Spawner** — produces spitters. Unlocks when the first Hive is placed.
- **Hive Lab** — research. Unlocks when creep first spreads. Rendered as a Biolab.
- **Worm turrets** (small → behemoth) — defenses. Each tier unlocks via research.
- **Pheromone Vent** — diverts the network's incoming biter stream and dispatches it as an autonomous attack group. Buildable anywhere, free to place. Unlocks via research after Small Worms. Rendered as a recoloured Hive Node (deep red).
- **Promote Node** — a single-use marker recipe. Crafting it converts the closest Hive Node within range of the player into a second (or third, etc.) Hive in place. Costs significant pollution. See "Promotion".

Each placeable item lists its pollution cost in its tooltip.

## Crafting menu

These rules describe **recipe** placement (where the recipe shows in the crafting menu) — distinct from the item subgroup, which the director never browses because their quickbar is fixed and refilled by the loadout watchdog.

- Hive building recipes, including Pheromone Vent — intermediate products tab.
- Release Pheromones, Promote Node, and Pheromone Vent mode markers (small / default / large) — production tab.

## Pheromones

- One recipe: **Release Pheromones**. Crafting it triggers a single-shot pheromone burst at the player's position at craft completion. No item to carry around, no withdraw recipe — the burst is bounded.
- The burst behaves like a temporary, building-less Pheromone Vent. The network's incoming biter stream (recruited and disgorged) is diverted to that position. Biters arriving at the spot attack engineer-aligned stuff there (vehicles, structures within the immediate area).
- The disgorge releases enough stored creatures to feed the burst — a small multiple of X — not the whole stockpile. Triggering pheromones on a network with thousands of stored creatures does not dump them all in one freeze; the rest stay in storage for future bursts.
- Once **X biters** have arrived (X = the same `attack_group_size` a default-mode Pheromone Vent uses, scaled by Attack Group Size tech), they form an autonomous attack group and disperse — the engine routes them onward toward player infrastructure.
- Only one active pheromone burst exists at a time. Crafting **Release Pheromones** again before X have arrived **cancels** the previous gather (no group is dispatched). Crafting it after the group has already dispatched is fine — the new gather starts; the dispersed group runs its course independently.

## Pheromone Vent

- Buildable anywhere. No network range requirement. No pollution cost.
- Belongs to the network of the placing player's hive. If the player has no hive when placing, the vent dies on placement. If the player's hive is later destroyed without replacement, the vent dies with the network.
- No recruitment range of its own. Diverts the network's incoming biter stream to itself, the same way Pheromones divert it to a player.
- Gathers biters until the vent's `attack_group_size` arrive, then forms an autonomous attack group via the engine. The hive does not target — the engine routes the group toward polluted chunks and enemy structures of its own accord.
- Trade-off is opportunity cost: every biter diverted is one the hive doesn't absorb. Place too many and the network starves.
- Per-vent mode: `small` / `default` / `large`. Multiplies `attack_group_size` by `0.5×` / `1×` / `2×`. Set via marker-item recipe (same UX as Pheromones).

### Pheromone Vent — non-goals

- Custom targeting in any form. No pings, no markers, no per-vent aim.
- Group composition control.
- Group recall.

## Promotion

- The anchor is permanent and cannot be relocated. To gain a second recruit pole — to push the network's centre of mass toward a far cluster, for example — you craft **Promote Node** and apply it to an existing Hive Node in your network.
- The targeted node is destroyed and replaced by a Hive entity at the same position. The new hive participates in the same shared storage as every other hive in the network. Like the anchor, it is non-minable — promotion is a one-way action.
- Promotion costs significant pollution (initial value 1000, tunable). The source must be a Hive Node in the network. Promoted hives do not count toward the evolution-gated node limit.
- Promoted hives can themselves be the source for further node chains, so the network grows organically — anchor → nodes → promoted hive → more nodes → etc. — as evolution allows.

## Network

- Each Hive recruits creatures inside its 100×100 box. Each Hive Node also recruits, inside its own 50×50 box. Both are scaled by the infinite **Attraction Reach** tech (+10% per level), so dropping nodes is the way to spread recruitment outward across the map.
- Units recruited from a hive walk to that hive. Units recruited from a node walk to the nearest hive on the same surface (nodes have no storage of their own). Pheromone vents on the network divert nearby recruited units to themselves instead.
- Each Hive and Hive Node has a 100×100 / 50×50 construction zone where it builds. Connected zones extend the network.
- Connected hives and nodes share one resource pool.
- Loading a save must preserve or recover hive/node connections; existing hives and nodes in the world remain connected to the construction, recruitment, and storage network.
- **Node placement exception**: a Hive Node can be placed as long as it would connect to the network — i.e., the new node's own 50×50 box would overlap an existing hive or node — even if the placement position itself sits just outside the current network's build zone. All other buildings still require the placement position to be inside the network's build zone. Pheromone Vents are exempt — they are buildable anywhere.
- **Evolution-gated node count** (startup setting **Hive Evolution Gate**, default **off**): when enabled, each network's Nth node placement requires the surface's enemy evolution factor to be at or above a threshold. The first node is free; each subsequent node demands more evolution. The engineer's pollution and nest kills drive evolution, so node growth self-paces against engineer progress — you can't node-spam at minute zero, and a runaway engineer unlocks a runaway hive. **Hives do not count toward the node limit** — only Hive Node entities do. A promoted hive removes a node from the count and adds an unlimited hive in its place; you can keep growing nodes around it.
- A single purple **creep** tile fills the same box outward in Chebyshev rings. Biters move faster on creep. The outermost ~2 rings are progressively patchy, and a single sparse ring extends just past the box, so the silhouette has a slightly irregular, organic edge instead of a perfect square. The fuzzed pattern is stable across save/load.

## Recruitment

- Without pollution: a steady trickle of biters wanders into the network. Trickle rate scales with the number of spawners (any `unit-spawner`, hive-placed or wild) inside the network's combined recruit range. Default 0.05 biters per second per spawner. More spawners in range → more biters available; no spawners → no trickle.
- The trickle pool is shared across all hives, hive nodes, and pheromone vents in the network.
- With pollution: any biter the engine attached to an attack group is recruited immediately, no quota, on top of the trickle.
- Pheromones still override.

## Network collapse

- When the last hive in a network is destroyed, every other hive-side building in that network is destroyed too: hive nodes, pheromone vents, hive labs, hive storage chests.
- Hive workers belonging to the collapsed network die.
- Existing per-hive death rule still applies: storage chests release stored creatures as live units before destruction.
- Player-placed biter/spitter spawners and worm turrets are **not** destroyed. They live on the enemy force after the build-time swap and stay where they were. The hive can re-claim them by building a new hive within recruitment range — same as any wild nest.

## Hive Supremacy

Once **Hive Supremacy** is researched, anything on creep that isn't part of the hive ecosystem withers and dies.

- Hive structures, hive workers, recruited creatures, and vanilla biters / spitters / spawners / worm turrets are unaffected — they belong on creep.
- Trees on creep wither slowly (~30 seconds end-to-end). When a tree dies it releases its full vanilla pollution burst into the air, feeding back into recruitment pressure.
- Player-built structures, vehicles, and any other non-hive non-biter entity on creep take continuous damage and are destroyed in roughly 60 seconds.
- The effect only applies on hive-created creep, not on natural terrain.
- Hive Supremacy is a single-shot tech (no tier list, no infinite scaling).

## Cost

- Every absorbed creature is worth some pollution.
- Every build and every science pack costs pollution.
- The network's capacity is pre-checked before any spend: if the pool is short, the build is refused outright and no biters are consumed. The error message reports the gap as `Insufficient pollution: 30 / 100 (have / need).`
- Successful placements auto-refund the cursor, so a long row of buildings doesn't end with the cursor empty.
- The hive spends creatures to pay. The player never handles pollution items directly.

## Research

- All research uses **Pollution Science Packs**.
- Hive Spawners and Hive Labs unlock from gameplay events (placing a hive, spreading creep) rather than manual research.
- Worm tiers are researched manually in order.
- Attraction Reach is infinite (+10% per level, cost ramps with level).
- Hive Supremacy is a manual single-shot tech that turns creep hostile to non-hive entities.
- Pheromone Vent is a single-shot tech, prerequisite Small Worms, that unlocks the Pheromone Vent recipe.
- Attack Group Size is an infinite tech (+2 per level, cost ramps), prerequisite Pheromone Vent, that increases the dispatch threshold of every Pheromone Vent.
- The vanilla tech tree is hidden on the hive force.

## Non-goals

- No old-save compatibility.
- No converting vanilla nests.
- No replacing vanilla spawners.
- No population cap.
- No leaving the hive.

---

Implementation choices, internal entity names, and engine-level details live in [design.md](design.md).
