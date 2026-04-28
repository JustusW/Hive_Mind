# Hive Mind Reloaded

This repository now has two clearly separated parts:

- the new reboot scaffold at the repo root
- the archived legacy 2.0 port in [legacy/hive-mind-2.0-port-reference](</E:/code/factorio/legacy/hive-mind-2.0-port-reference>)

The root mod is now a fresh scaffold for the new design in [HIVE_REBOOT_REQUIREMENTS.md](</E:/code/factorio/HIVE_REBOOT_REQUIREMENTS.md>):

- hive-directed play
- real placeable hive buildings
- creature-backed logistics and construction
- map-wide recruitment
- pollution as the passive upstream driver

## Current Scaffold

The new root mod currently includes:

- `Hive`
- `Hive Node`
- `Hive Lab`
- `Pheromones`
- `Pollution Science Pack`
- hidden internal `Pollution`
- placeholder technologies and runtime ownership scaffolding

It is intentionally minimal and meant to be the clean starting point for the reboot.

## Legacy Reference

The archived port remains available for reference, balancing ideas, and art/prototype reuse:

- [legacy/hive-mind-2.0-port-reference/README.md](</E:/code/factorio/legacy/hive-mind-2.0-port-reference/README.md>)
- [legacy/hive-mind-2.0-port-reference/INTENDED_BEHAVIOR.md](</E:/code/factorio/legacy/hive-mind-2.0-port-reference/INTENDED_BEHAVIOR.md>)

## Dev Notes

Use the existing helper scripts in [tools](</E:/code/factorio/tools>) to launch and validate the mod:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check-load.ps1
powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1 -UntilTick 600
```
