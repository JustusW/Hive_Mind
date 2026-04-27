# Hive Mind port plan for modern Factorio (2.0+, no Space Age)

## Goal and target
- Port this mod from **Factorio 1.1** to current **Factorio 2.0** API/runtime.
- Keep scope to **base game only** (no Space Age content requirements).
- Preserve the core gameplay loop: join hive force, convert nests, spend pollution, spread creep, deploy units, and research through hive buildings.

## Current progress (2026-04-27)
- `info.json` now targets **Factorio 2.0** and depends only on `base >= 2.0.0`.
- `changelog.txt` already includes a `0.5.0` entry for the 2.0 port branch.
- The old `Unit_Control` dependency is gone; the remaining internal assumptions are now owned directly inside this repo.
- The development environment now uses an isolated sibling profile outside the repo instead of the shared `%APPDATA%\Factorio\mods` folder.
- Headless validation currently passes:
  - `powershell -ExecutionPolicy Bypass -File .\tools\check-load.ps1`
  - `powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1 -UntilTick 3600`

## What was fixed in this pass
- Prototype migration work:
  - removed legacy `hr_version` assumptions,
  - updated deployer graphics extraction for 2.0 spawner prototype shapes,
  - converted multiple old collision-mask lists to 2.0 mask structures,
  - updated recipe/result definitions and pollution-related prototype fields,
  - fixed several 2.0 data-stage schema mismatches.
- Runtime migration work:
  - updated pollution statistics access to `game.get_pollution_statistics(surface)`,
  - updated force evolution accessors to `get_evolution_factor()` / `set_evolution_factor(...)`,
  - fixed hive-force recipe reset to write explicit booleans,
  - migrated creep spreading off the old `ground-tile` runtime collision-layer name.
- Tooling/workflow:
  - added isolated dev scripts under `tools/`,
  - made headless checks auto-link the mod into the isolated mods folder,
  - fixed runtime smoke-test save detection,
  - moved the default dev profile outside the repo to avoid recursive junctions.

## Remaining high-risk areas
- Join/leave hive quickbar handling in `script/hive_mind.lua`.
- Player controller and character handoff flows in `script/hive_mind.lua`.
- Save upgrade behavior for existing 1.1 saves.
- Multiplayer/PvP and `wave_defense` integration paths.
- Late-game performance of creep spreading and deployment scans.

## Port strategy (remaining)

### Phase 1 - Runtime gameplay validation
1. Exercise join-hive flow manually in game.
2. Exercise leave-hive flow and verify quickbar/inventory restoration.
3. Verify custom biter character creation, death, and respawn behavior.
4. Re-check GUI restrictions, mining restrictions, and forced equipment logic.

### Phase 2 - Save migration and compatibility
1. Extend `on_configuration_changed` as needed for older persistent data layouts.
2. Verify older `global`/`storage` state upgrades cleanly.
3. Test force reset and force merging safety on migrated saves.

### Phase 3 - Multiplayer and integration hardening
1. Validate optional `pvp` integration paths.
2. Validate optional `wave_defense` integration paths.
3. Re-test force switching with multiple players.

### Phase 4 - Release preparation
1. Run a final data-stage check.
2. Run a final extended runtime smoke test.
3. Complete manual scenario checklist.
4. Align `info.json` versioning with the intended release tag if needed.

## Manual test checklist
- New map:
  - join hive,
  - convert a nest,
  - spawn units,
  - place creep structures,
  - run pollution lab/drill progression.
- Leave and rejoin the hive repeatedly.
- Multiplayer with 2+ players changing force.
- Optional integration scenarios with `pvp` and `wave_defense`.
- Upgrade an older 1.1 save with prior hive activity.

## Validation commands
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check-load.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1 -UntilTick 3600
powershell -ExecutionPolicy Bypass -File .\tools\start-factorio.ps1 -LinkFirst
```

## Deliverables
- 2.0-compatible release branch.
- Updated changelog notes.
- Repeatable isolated dev workflow.
- Pass/fail validation checklist for the manual scenarios above.
