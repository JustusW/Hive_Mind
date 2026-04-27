# Hive Mind port plan for modern Factorio (2.0+, no Space Age)

## Goal and target
- Port this mod from **Factorio 1.1** to current **Factorio 2.0** API/runtime.
- Keep scope to **base game only** (no Space Age content requirements).
- Preserve current gameplay loop (join hive force, convert nests, pollution economy, creep spreading, deployers, pollution lab/drill).

## Current-state findings (from this repo)
- `info.json` currently pins `factorio_version` to `1.1` and depends on external mod `Unit_Control >= 0.3.0`.【F:info.json†L1-L10】
- Runtime control logic is split across `script/*` libs and dynamically registers events from each library in `control.lua`.【F:control.lua†L1-L75】
- Main gameplay force-join/leave and quickbar logic are in `script/hive_mind.lua` (notably hardcoded 100-slot quickbar operations and remote integrations with `pvp`/`wave_defense`).【F:script/hive_mind.lua†L264-L345】【F:script/hive_mind.lua†L636-L707】
- Unit spawning / ghost sacrifice / pollution accounting core loop is in `script/unit_deployment.lua`.【F:script/unit_deployment.lua†L49-L73】【F:script/unit_deployment.lua†L245-L293】
- Prototype/content definitions are in `data/*`, loaded from `data.lua` and `data-updates.lua`.【F:data.lua†L1-L5】【F:data-updates.lua†L1】

## Port strategy (phased)

### Phase 1 — Baseline compatibility setup
1. **Branch + metadata update**
   - Bump `info.json.factorio_version` to `2.0`.
   - Re-check dependency strategy for `Unit_Control`:
     - either update to a 2.0-compatible release,
     - or make it optional / replace integrated functionality if it is not maintained.
2. **Create a migration changelog entry** in `changelog.txt` with explicit 2.0 port notes.
3. **Define support matrix**:
   - Dedicated server + singleplayer.
   - New saves + upgrade from existing 1.1 saves.

### Phase 2 — Runtime API audit and fix
1. **Player inventory/quickbar migration**
   - Audit quickbar APIs used in join/leave flow (`get_quick_bar_slot`, `set_quick_bar_slot`, active page calls).【F:script/hive_mind.lua†L313-L323】【F:script/hive_mind.lua†L430-L434】
   - Replace with 2.0-safe equivalents if removed/changed.
2. **Character/controller transitions**
   - Validate `player.character=nil`, forced respawn/teleport flow, and custom biter character creation paths still behave correctly in 2.0.【F:script/hive_mind.lua†L309-L347】【F:script/hive_mind.lua†L394-L440】
3. **Event payload/API consistency**
   - Validate each subscribed event still exists with expected payload fields (e.g. deconstruction, gui_opened, forces_merging, mined entity buffer semantics).【F:script/hive_mind.lua†L636-L653】
4. **Rendering API checks**
   - Verify `rendering.draw_text/draw_light` options and lifetime behavior in 2.0 remain valid.【F:script/hive_mind.lua†L85-L96】【F:script/unit_deployment.lua†L172-L188】
5. **Map settings mutability**
   - Confirm pollution map settings writes remain valid in init/config changed contexts in 2.0.【F:script/hive_mind.lua†L595-L601】

### Phase 3 — Data/prototype stage audit
1. **Prototype schema validation** for all entities/tiles/tech recipes under `data/`.
   - Focus on fields that changed between 1.1 and 2.0 (icon requirements, collision masks, trigger/effect fields, resistances, sounds/animations, recipe prototype format).
2. **Data updates order + compatibility**
   - Re-run through `data_updates/*` scripts to catch assumptions about base prototype names/fields that shifted in 2.0.
3. **No-Space-Age policy**
   - Ensure no references to expansion-only prototypes/technologies are introduced.

### Phase 4 — External integration hardening
1. **Remote interface guards**
   - Keep integrations with `pvp`/`wave_defense` optional and resilient when absent (already partially guarded).【F:script/hive_mind.lua†L664-L674】
2. **Unit_Control replacement (required)**
   - `Unit_Control` is not available for 2.0, so treat this as a hard migration requirement.
   - Identify every runtime assumption coupled to `Unit_Control` behavior and re-implement directly inside Hive Mind (or via a new maintained dependency).
   - Add explicit migration test cases for unit commanding/idle detection and spawn/deploy behavior after this rewrite.

### Phase 5 — Save migration and compatibility
1. **on_configuration_changed migration hooks**
   - Extend current migration path to normalize any changed global state structures and player records on upgrade.【F:script/hive_mind.lua†L697-L707】
2. **Backward data cleanup**
   - Remove/convert obsolete fields in `global.hive_mind` as needed.
3. **Force/technology reset safety**
   - Verify resets do not wipe or corrupt state during in-progress multiplayer rounds.

### Phase 6 — Test plan
1. **Automated/static checks**
   - Run luacheck/stylua (if introduced) and Factorio startup validation logs.
2. **Manual scenario tests (must pass)**
   - New map: join hive, convert nest, spawn units, build creep, research pollution lab chain.
   - Leave/rejoin hive repeatedly.
   - Multiplayer with 2+ players changing force.
   - Upgrade test: load a 1.1 save with prior hive activity and migrate to 2.0 build.
3. **Performance checks**
   - Verify on_tick-adjacent loops and entity scans are acceptable in late game.

## Recommended execution order (practical)
1. Metadata/dependency updates.
2. Runtime API breakages (quickbar/controller/event payload).
3. Data stage prototype fixes.
4. Migration scripts.
5. Multiplayer + performance hardening.
6. Release candidate and beta test on mod portal.


## Cross-comparison against similar-sized mods (4k-8k Lua LOC)

### Reference size for Hive Mind
- Approximate code size in this repository: **31 Lua files / ~4.5k LOC**.
- Practical implication: this is a **medium-size** port (not trivial metadata-only, not a massive overhaul).

### Direct comparison to real 1.1 -> 2.0 mod ports
| Example mod | 2.0 port notes visible in changelog | What that implies for effort | Comparison to Hive Mind |
|---|---|---|---|
| **Concretexture (updated for 2.0)** | Port mentions mainly 2.0 update + removing `hr_version` assets. | Mostly prototype/asset cleanup; low runtime risk. | Hive Mind is **substantially more work** because it has heavy runtime control logic and force/player transitions. |
| **Outpost Planner for 2.0** | 2.0 port plus post-port bugfixes (e.g. reconfig crash, big drill behavior quirks). | Runtime behavior regressions can appear after first successful load. | Hive Mind should expect similar post-port runtime fixes, likely in join/leave and spawning loops. |
| **Long Range Turret Redone** | 2.0 updates included `hr_version` removal and migration cleanup in follow-up versions. | Data-stage conversion is not always enough; migration correctness matters. | Hive Mind also needs migration hardening, but with extra complexity due to force/global-state transitions. |
| **Brim Stuff Legacy** | 2.0.0 notes explicitly call out many fixes/migrations, with multiple follow-up compatibility bugfixes. | Medium-size content mods often need iterative stabilization after initial 2.0 release. | Hive Mind is likely in this stabilization pattern, plus extra runtime complexity from combat/unit mechanics. |

### Concrete comparison result
- Compared with these real ports, Hive Mind is **not** a “simple direct port” class.
- It maps closest to mods that required **initial 2.0 conversion + several follow-up fixes**, but with **higher runtime risk** because of:
  - force switching and character replacement,
  - custom spawning/deployment behavior,
  - pollution-driven control loops,
  - and removal/replacement of the unavailable `Unit_Control` dependency.

### Workload estimate for this mod specifically
| Area | Relative effort | Notes |
|---|---:|---|
| Metadata/dependency updates (`info.json`, changelog, dependency pinning) | 5% | Small on its own, but dependency maintenance status can become a blocker. |
| Runtime script API migration (`script/hive_mind.lua`, `script/unit_deployment.lua`) | 45% | Quickbar/inventory transitions, force switching, event payload validation, rendering behavior. |
| Data/prototype migration (`data/*`, `data_updates/*`) | 25% | Prototype field/schema validation and load-order assumptions against 2.0 base. |
| Save migration + compatibility hardening (`on_configuration_changed`) | 15% | Required to avoid corrupting old saves and force/player state. |
| Multiplayer/regression/perf validation | 10% | Join/leave hive flows and high-entity scenarios must be re-tested. |

**Projected total implementation effort (single maintainer):**
- **Best case:** 4-6 days (if `Unit_Control` replacement is straightforward and no deep save-migration issues appear).
- **Likely case:** 1-2 weeks (runtime rewrites + migration bugs found during MP testing).
- **Worst case:** 2-3 weeks (deeper dependency rewrite + iterative stabilization after first 2.0 release).

## Risks to watch
- Quickbar/control behavior changes causing player inventory loss on join/leave.
- Replacing `Unit_Control` with an internal 2.0-compatible control path without feature regressions.
- Prototype field changes that only fail during data stage load.
- Save migration edge cases with stale `global` fields.

## Deliverables
- 2.0-compatible release branch.
- Porting migration notes in changelog.
- Validation checklist (pass/fail) for all manual scenarios above.
