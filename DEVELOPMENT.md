# Development workflow

This repository is set up for local Factorio mod development on Windows.

## What is already configured

- The repo includes PowerShell helpers for an isolated local Factorio dev workflow.
- The helpers auto-detect common Windows Factorio install locations or accept `-FactorioRoot`.
- The default isolated dev profile root is a sibling directory named `<repo-name>-dev-profile`.
- The default isolated dev mods directory is `<dev-profile>\mods`.
- The default isolated dev write-data directory is `<dev-profile>\player-data`.

## Core workflow

1. Create a junction from the repo into the isolated dev mods directory:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\link-mod.ps1
   ```

2. Launch Factorio with the isolated dev mods directory:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\start-factorio.ps1 -LinkFirst
   ```

3. Tail the current Factorio log while testing:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\tail-log.ps1
   ```

4. Run a headless load check against the isolated dev profile:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\check-load.ps1
   ```

5. Run a headless runtime smoke test that creates a save and advances it a few ticks:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\check-runtime.ps1
   ```

## Notes

- `link-mod.ps1` reads `info.json` and creates a junction named `Hive_Mind_0.4.3` in the mods directory.
- By default, the helpers use a sibling `factorio-dev-profile` directory outside the repo so test launches do not load your normal `%APPDATA%\Factorio\mods` collection and the repo does not contain a self-referential mod junction.
- `start-factorio.ps1` also generates a dedicated config file and routes Factorio write-data into the isolated profile, which keeps logs, saves, and lock files out of the shared profile.
- Set `HIVE_MIND_FACTORIO_DEV_ROOT` if you want these helpers to use a different isolated profile root.
- Pass `-ModsPath "$env:APPDATA\Factorio\mods"` explicitly if you want to target the shared mods directory instead.
- `start-factorio.ps1` auto-detects common Factorio install locations and can be pointed at a custom path with `-FactorioRoot`.
- The workspace includes `.editorconfig`, `.luarc.json`, and VS Code task recommendations to make Lua editing less noisy.
- The current branch already targets Factorio 2.0 in `info.json`; the next development work is the runtime/data-stage porting tracked in `MODERN_FACTORIO_PORT_PLAN.md`.
