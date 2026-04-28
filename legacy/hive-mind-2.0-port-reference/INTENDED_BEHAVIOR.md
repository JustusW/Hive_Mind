# Intended Behavior

This document describes the intended gameplay and mod behavior of Hive Mind based on the original `master` branch implementation, not the current in-progress Factorio 2.0 port.

Primary reference points used for this summary:
- `master:script/hive_mind.lua`
- `master:script/unit_deployment.lua`
- `master:script/pollution_lab.lua`
- `master:data/entities/biter_player.lua`
- `master:data_updates/adjust_biters.lua`
- `master:shared.lua`

## Core premise

Hive Mind lets a player leave their normal engineer life, join a special `hivemind` force, and take direct control of the biter side. The hive then uses pollution as its economy and nearby converted nests as its production base.

In singleplayer, the expected fantasy is not "start as biters on an empty map." It is closer to:

1. Start as a normal engineer.
2. Build up some infrastructure and generate pollution.
3. Join the hive.
4. Fight against your former engineer-side force using biter units and hive structures.

## Joining the hive

When a player presses `Join THE HIVE!`, the original mod is intended to:

- create or reuse a dedicated `hivemind` force,
- find a nearby enemy biter spawner cluster,
- move the player into the hive force,
- convert the chosen nest into hive infrastructure,
- swap the player into a custom biter character,
- replace the quickbar with hive buildings and tools,
- tint the player red and add the `HIVE` chat tag.

Important consequences from the original code:

- `hivemind` is set friendly with the vanilla `enemy` force, so wild biters are allies, not targets.
- nearby enemy units and worms around the converted nest switch to the hive side.
- biter and spitter spawners in that cluster are replaced with deployer buildings.

## Leaving the hive

When a player leaves the hive, the original mod is intended to restore:

- the previous force,
- the previous character or a replacement character if the old one is gone,
- the old quickbar,
- the old tag and player colors.

If the last player leaves the hive force, the hive is intended to disband back into the vanilla enemy side:

- deployers convert back into spawners,
- hive-only ghosts/labs/drills are destroyed,
- surviving hive units and turrets revert to `enemy`.

## Player state while in hive mode

The hive player is meant to feel like a biter, not a normal engineer.

From the original `master` code, the intended restrictions and traits are:

- your character form depends on evolution factor:
  - small biter
  - medium biter
  - big biter
  - behemoth biter
- you always carry a built-in biter attack and a firestarter weapon,
- your normal inventory is effectively removed,
- you cannot meaningfully hold arbitrary items,
- only a narrow set of held tools are allowed:
  - blueprints
  - copy/paste tool
  - selection tool
  - deconstruction planner
  - guns
  - ammo
- if you pick up something else, the mod drops it and warns that biters cannot hold it,
- only certain entity GUIs are intended to open for hive players:
  - assembling machines
  - labs

The original master branch also had `mining_speed = 0` and commented-out wood/coal/stone pollution conversion, which strongly suggests that hand-mining raw resources was not meant to be a core or reliable hive income source in the original design.

## Intended economy

The hive economy is based on pollution, not ore plates or conventional crafting ingredients.

### Pollution as currency

The mod uses pollution in three closely related ways:

- as local energy for deployers,
- as a stored research resource through `pollution-proxy`,
- as the cost to place hive buildings and units.

The important idea is that pollution is mostly environmental and local, not a clean global wallet UI.

### Deployer production

Converted spawners become deployers:

- `biter-deployer`
- `spitter-deployer`

These are assembling-machine style hive buildings. In the original logic:

- they craft unit items with no normal ingredients,
- recipe `energy_required` is treated as pollution cost,
- they absorb local surface pollution near the building,
- `1 pollution = 1 crafting energy`,
- once the crafted unit item is ready, the deployer spawns the actual live unit into the world.

So the intended loop is not "craft a biter into your inventory and place it later." It is "feed a deployer enough local pollution and it births the unit."

### Research

Hive research uses `pollution-proxy` items as science.

`pollution-lab` buildings are intended to:

- absorb local ambient pollution,
- convert that pollution into `pollution-proxy` items,
- let hive technologies consume those items.

This means research is still fundamentally paid for by map pollution, but the lab converts it into an internal item form for technology.

### Building placement and sacrifice

Placing hive ghosts is not free.

For structures such as worms, creep tumors, pollution labs, and pollution drills, the original code is intended to:

- allow the player to place a ghost,
- assign a required pollution cost,
- have nearby friendly hive units walk to the ghost,
- sacrifice those units,
- subtract their pollution value from the build cost,
- finally revive the structure once enough value has been paid.

This makes unit bodies part of the construction economy.

### Population cap

The hive is intended to be limited by a force-wide population cap.

The original code:

- counts all units owned by a force,
- shows a `Population: current/max` label,
- defaults the cap to `1000`,
- allows admins to change it with `/popcap`.

Deployers stop actively producing units when the cap is full.

## Intended structures and progression

The original `shared.lua` and `adjust_biters.lua` define these core hive buildables and baseline costs:

- `biter-deployer`: 100 pollution
- `spitter-deployer`: 200 pollution
- `creep-tumor`: 50 pollution
- `pollution-lab`: 150 pollution
- `pollution-drill`: 100 pollution
- `small-worm-turret`: 200 pollution
- `medium-worm-turret`: 400 pollution
- `big-worm-turret`: 800 pollution
- `behemoth-worm-turret`: 1600 pollution

Default unlocks are intended to be:

- `small-biter`
- `small-spitter`
- `small-worm-turret`

Other units and structures are intended to unlock through hive-only technologies that consume `pollution-proxy`.

## Creep rules

Some structures are intended to require creep. In the original code this includes:

- all worm turrets,
- creep tumors,
- pollution drills,
- pollution labs.

If placed off creep, the ghost is supposed to be rejected with a local warning.

## Combat and tools

The hive player is intended to participate directly in combat.

From the original code and prototypes:

- the player attacks using custom biter attack guns/ammo mapped from the current biter tier,
- the player also gets a `firestarter` weapon,
- the firestarter on `master` specifically creates fire-on-tree behavior, which implies a role in burning forests and influencing pollution locally,
- worms and other biter-side entities are reworked into player-usable versions with pollution-based costs.

## Singleplayer expectation

The original implementation does support singleplayer, but it is asymmetric:

- wild biters become your allies,
- the former engineer side becomes your practical enemy,
- the strongest solo use case is joining after an engineer phase has already created pollution, territory, and targets.

So if a fresh empty freeplay map feels weak or under-resourced at the start of hive mode, that is broadly consistent with how the original mod was structured.

## Important nuance about resource generation

One of the easiest misunderstandings is assuming the hive was meant to farm wood/stone/coal directly for its economy.

The original `master` branch does not really support that interpretation cleanly:

- hive mining was disabled,
- the raw-resource-to-pollution conversion table was commented out,
- the visible economy instead centers on ambient pollution, deployers, labs, creep, and unit sacrifice.

That suggests the intended economy was primarily:

1. exploit existing map pollution,
2. convert nests into deployers,
3. spread and defend creep territory,
4. use pollution labs for research,
5. spend pollution and sacrificed units to grow the hive.

If we choose to restore hand-mining as a bootstrap mechanic in the 2.0 port, that should be treated as a design decision, not simply "obviously what master already did."

## Practical tester guidance

When comparing the port to intended behavior, the best questions are:

- Does joining the hive convert a real enemy nest into a functioning hive foothold?
- Does the player become a restricted biter avatar rather than a normal engineer?
- Do deployers consume local pollution and spawn units?
- Do labs turn local pollution into research progress?
- Do creep-only placements and sacrifice-based construction still work?
- Does leaving the hive restore the old player state?
- Does the hive disband back into the enemy side when abandoned?

Those are the core behavioral promises from the original branch.
