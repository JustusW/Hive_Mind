# Hive Reboot Requirements

This document defines the new intended gameplay model for Hive Mind.

It intentionally replaces the old "converted nest + local pollution deployer economy" design with a more direct model:

- the hive player behaves more like an engineer,
- hive structures are real placeable buildings,
- construction is paid for by sacrificing living hive creatures,
- hives act as the construction and logistics backbone.

This is a pre-alpha reboot spec, not a backwards-compatibility document.

## Goal

The player should feel like a hive-skinned engineer with biological quirks:

- they join the hive and become the hive-side player,
- they place real buildings and ghosts,
- hive creatures are the true construction resource,
- hives absorb creatures, store them, and use them to execute build requests,
- science is produced by consuming living hive creatures rather than standard item packs.

## Core Player Flow

1. The player joins the hive.
2. The player has exactly one direct crafting recipe: `Hive`.
3. The player crafts and places a `Hive` to establish or move their active colony.
4. The hive attracts nearby and distant eligible hive creatures.
5. The hive absorbs those creatures into internal storage.
6. The player places building ghosts.
7. The hive fulfills those build orders by consuming stored or incoming creatures, manufacturing the requested building, and placing it through hive construction logistics.

## Functional Requirements

### R1. Join Hive

- The player can join the hive.
- Joining the hive changes the player into the hive-side role.
- The hive-side player is the only actor allowed to create and direct hive construction.

### R2. Player Crafting

- The hive player has exactly one craftable recipe: `Hive`.
- No other direct player crafting recipes are available unless explicitly added later.

### R3. Single Active Hive Per Player

- When a player crafts a `Hive`, any previously existing `Hive` entities owned by that same player are destroyed.
- This rule is per player, not global.
- Destroying the old hive is part of successful creation of the new hive.

### R4. Hive Attraction

- Once placed, a hive attracts eligible hive creatures from long range.
- The hive does not replace, convert, or otherwise rewrite vanilla biter/spitter spawners.
- Recruitment comes from eligible living creatures already present on the map.
- The attraction radius should be large enough that a meaningful surrounding hive population responds.
- Eligible creatures should path toward the hive automatically.
- Recruitment should be treated as effectively map-wide unless we later impose a deliberate gameplay or technical cap.

### R5. Hive Absorption And Storage

- A hive has an inventory.
- When an eligible hive creature reaches the hive, the creature is removed from the world and converted into stored hive inventory.
- Eligibility is not limited to vanilla biters and spitters.
- Any unit with the correct hive eligibility markers should be accepted, including modded units such as gleba biters or equivalent future additions.

### R6. Hive Destruction

- If a hive is destroyed, all creatures stored in that hive are released back into the world as living units.
- The release should preserve the creature types and counts represented by the stored hive inventory.

### R7. Hive Construction Logistics

- The hive acts like a roboport.
- Its construction agents are invisible, invincible, and effectively instantaneous within hive build reach.
- Buildings within hive construction range should be placed nearly instantly once their cost is satisfied.
- These construction agents are an implementation detail; the player should experience them as hive build logistics, not as standard robots.

### R8. Building Placement And Construction

- The hive player places normal building ghosts.
- A hive detects those building requests within its construction network.
- The hive determines the build cost by converting the target building's required pollution value into a required creature-sacrifice value.
- The hive consumes the appropriate number and type mix of stored or incoming creatures to satisfy that cost.
- Once paid, the hive creates the requested building as a buildable item or equivalent construction payload and its construction logistics place the building.
- `Q` pipette behavior must work for hive buildings and their ghosts.

### R9. Science Lab Inventory And Hive Supply

- A science lab has an inventory.
- The lab can request what it needs from the hive network.
- The player does not need to hand-feed labs manually once the hive network can supply them.

### R10. Technologies

- Research is represented as normal Factorio technologies.
- Hive progression unlocks should be implemented through proper technologies rather than ad hoc recipe toggles alone.

### R11. Science Production From Creatures

- Every science lab consumes living hive creatures.
- The consumption rate and value are derived from each creature's base pollution value.
- The lab converts those creatures into science used by the technology system.

## Derived System Requirements

These are not separate user stories, but they are required for the above behavior to be coherent.

### D1. Creature Value Model

- Every eligible hive creature must expose a construction/science value.
- The baseline value source is the creature's pollution cost.
- Modded creatures must be able to participate through the same value model.

### D2. Hive Ownership Model

- A hive must know which player owns it.
- "Destroy previous hives of the player" and "player places hive buildings" both depend on explicit hive ownership.

### D3. Hive Network Scope

- Building ghosts and requesting labs must belong to a specific hive network.
- The implementation must define how a ghost or lab chooses its serving hive:
  - nearest owned hive,
  - same force hive,
  - or another explicit ownership/network rule.

### D4. Storage Representation

- Hive inventory must represent creature types, not just abstract value.
- Stored contents must be sufficient to:
  - release real living units on hive death,
  - supply creature-consuming science labs,
  - optionally support UI inspection by the player.

### D5. Placement Semantics

- Hive buildings should be real placeable entities/items from the player perspective.
- The user interaction should match engineer expectations:
  - quickbar placement works,
  - `Q` picking works,
  - ghost placement works,
  - buildings reserve their final footprint.

### D6. Hive Logistics Network

- Hives and Hive Nodes participate in one shared hive construction/logistics network based on build range overlap.
- If a request is in reach of the network, it is a valid candidate for fulfillment by that network.
- Resource mixing across connected hives and nodes is allowed and preferred.

### D7. Hidden Pollution Resource

- A hive stores living creatures as its primary resource for as long as possible.
- A hive may also store hidden internal `Pollution` as overflow.
- This `Pollution` item must:
  - stack effectively infinitely,
  - be invisible to the player,
  - be usable by hive logistics and labs.
- Hives should only convert creatures into stored `Pollution` when necessary to fulfill downstream requests.

### D8. Hive Node

- The mod includes a `Hive Node` structure.
- A Hive Node acts as a secondary hive network anchor similar to a roboport/radar.
- A Hive Node has a build/logistics range of `500`.
- Hives have a build/logistics/recruitment range of `1000`.
- Hives and Hive Nodes spread creep rapidly across their effective build range.

## Explicit Non-Goals

For this reboot spec, the following old assumptions are not required unless reintroduced later:

- converted enemy nests as the core production base,
- replacing vanilla spawners with hive-specific deployers,
- deployers as the central unit factory loop,
- local ambient pollution as the direct construction fuel,
- manual ghost-sacrifice by nearby loose units at the build site,
- old-save compatibility.

## Resolved Design Decisions

### O1. Eligibility Markers

- Official Factorio docs do not expose a single universal built-in "biter" tag we can rely on across mods.
- The baseline built-in classifier should therefore use documented entity/prototype identity:
  - creature-like entities such as `unit`, `spider-unit`, and other creature-unit forms we explicitly support,
  - plus vanilla names/roles for biters, spitters, worms, and related hive fauna.
- Mod compatibility must be provided through an expandable hive role registry rather than a hardcoded vanilla-only list.
- That registry must support at least three independent roles:
  - attract,
  - store,
  - consume.
- A modded creature may opt into any subset of those roles.

### O2. Hive Range

- Hive range starts at `1000`.
- Hive Node range starts at `500`.
- Hives use the larger range as both recruitment and logistics baseline unless we later split those concepts deliberately.

### O3. Multi-Hive Behavior

- Hives and Hive Nodes form a network based on range overlap.
- Connected structures mix resources if possible.
- The network is force-based, and if a provider is in valid network reach it is a candidate to fulfill the request.

### O4. Lab Requests

- Labs request `Pollution Science Pack` through hive logistics.
- Hives keep creatures as living stored creatures by default.
- When needed, hives convert creatures into hidden stored `Pollution`.
- Hives then create the requested science resources from available stored value and deliver them to labs.

### O5. Pollution Role

- Pollution remains the root driver of the economy.
- Vanilla spawners remain untouched and continue absorbing pollution normally.
- Pollution causes the world to create more eligible creatures.
- Hives recruit those creatures from the map and turn them into the actual usable hive resource.
- Pollution therefore drives the whole system passively rather than being spent directly by the player on most actions.

## What The Original Mod Had That This Spec Does Not Yet Say

The original mod included several gameplay rules and assumptions that are not currently captured in the reboot requirements above.

### M1. Leave-Hive Restoration

- Unlike the old mod, the player cannot leave the hive once joined.

### M2. Hive Force Diplomacy

- All hive-eligible creatures are friendly regardless of origin.
- NPC biters, recruited creatures, and other hive players are all one shared family.

### M3. Player Body Progression

- The player is invisible and invincible.
- The player cannot directly interact with the world except:
  - placing the hive,
  - placing construction ghosts,
  - using directed pheromone behavior.
- The player has a recipe called `Pheromones`.
- `Pheromones` take `60` seconds to craft.
- `Pheromones` spoil after `60` seconds.
- While the player carries `Pheromones`, recruited and absorbed creatures should converge on the player instead of the hive.

### M4. Population Cap

- There is no population cap for now.

### M5. Creep Rules

- Hives spread creep rapidly across their build range.
- Hive Nodes also spread creep rapidly across their build range.

### M6. Deployer Role

- The old mod used converted spawners/deployers to create field units from local pollution.
- The reboot explicitly drops that idea.
- Vanilla spawners remain vanilla, and the hive instead recruits from the existing living map population.

### M7. Bootstrap Loop

- The old mod assumed an initial nest conversion and existing world biters/pollution nearby.
- The reboot now explicitly says the hive recruits existing map creatures at very large range instead of converting nests.
- If there are too few eligible creatures available, the hive is simply out of luck.

### M8. Research Unlock Mapping

- `Hive` is always buildable.
- Once the first Hive is placed, this unlocks Spawners.
- Once creep has spread, this unlocks Labs.
- Science unlocks include worm progression from smallest to biggest.
- Other original-mod buildings should become flat immediately available research rather than deep tier chains unless later revised.

### M9. Science Output Form

- Science output is a custom `Pollution Science Pack`.
- Labs request it through logistics.
- The hive fulfills those requests by converting available stored resources into the pack and delivering it.

### M10. Building Ownership And Logistics UX

- We prefer native Factorio-style logistics resolution where possible.
- The hive is one factional network, and any in-range hive provider is a valid candidate to satisfy the job.

### M11. Unit Classification API

- Vanilla creatures should be classified through built-in rules.
- Modded creatures should be classifiable through expandable optional hive-role tags/registrations.
- Attraction, storage, and consumption eligibility must be independently overridable.
