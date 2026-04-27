# Hive Mind

Hive Mind lets you take control of the biters, convert nests, build hive structures, and run a pollution-based economy.

This branch is the current **Factorio 2.0 porting branch** for the mod, targeting **base game only** with **no Space Age requirement**.

## Tester status

What is already working on this branch:
- data stage loads cleanly on Factorio 2.0,
- runtime initializes cleanly,
- the mod passes a headless smoke test through 3600 ticks,
- joining the hive, opening converted nests, and deployer-based unit spawning are back in working shape,
- the hive UI now exposes local pollution and a dedicated build palette in hive mode.

What still needs real tester feedback:
- joining and leaving the hive,
- quickbar replacement and restoration,
- custom biter character behavior,
- creep spread and shrink behavior during normal play,
- pollution lab progression and sacrifice-based ghost construction,
- old save migration,
- multiplayer and optional `pvp` / `wave_defense` integration paths.

## Who should test this

This branch is useful for:
- players willing to try the 2.0 port and report gameplay regressions,
- modders who want to inspect the current porting work,
- contributors who want a working dev/test baseline instead of a broken startup state.

## How to test

### Option 1: Standard mod-folder install

1. Download this branch.
2. Put the mod folder into your Factorio `mods` directory.
3. Start Factorio 2.0 without Space Age enabled.
4. Create a new map and test the hive flow.

### Option 2: Use the included Windows helper scripts

This repo includes PowerShell helpers for an isolated local test profile.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start-factorio.ps1 -LinkFirst
```

That launches Factorio with a clean mod profile outside your normal shared mods folder.

To restart Factorio quickly after making changes:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\restart-factorio.ps1 -LinkFirst
```

## What to test first

1. Start a new freeplay map.
2. Use the Hive Mind UI button to join the hive.
3. Confirm you become a biter character and can interact with hive structures.
4. Convert a nest and verify nearby hive entities swap over correctly.
5. Use the left-side `Hive Builds` palette to place hive ghosts and watch whether nearby hive units begin paying their construction cost.
6. Build or use deployers, pollution lab, pollution drill, and creep structures.
7. Leave the hive and confirm your old force, character, and quickbar return correctly.

## Singleplayer note

This mode is intended to work in singleplayer, but it is not a traditional separate-campaign experience. The usual loop is:
- begin as a normal engineer,
- build some infrastructure,
- join the hive,
- then fight against your former engineer-side force using hive mechanics.

## Known risk areas

- quickbar handling may still have edge cases on join/leave,
- player character/controller transitions still need broader play coverage,
- ghost placement and sacrifice-based construction still need broader play coverage,
- older 1.1 saves have not been broadly migration-tested yet,
- optional integrations may still need follow-up fixes.

## Useful validation commands

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check-load.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1 -UntilTick 3600
```

## Reporting feedback

The most useful tester reports include:
- whether this was singleplayer or multiplayer,
- whether Space Age was enabled or disabled,
- exact steps to reproduce,
- whether the issue was a startup error, gameplay regression, visual issue, or save migration issue,
- the relevant `factorio-current.log` snippet if the game threw an error.

## Developer notes

If you want the deeper porting and workflow docs, see:
- [INTENDED_BEHAVIOR.md](INTENDED_BEHAVIOR.md)
- [DEVELOPMENT.md](DEVELOPMENT.md)
- [MODERN_FACTORIO_PORT_PLAN.md](MODERN_FACTORIO_PORT_PLAN.md)
