# tools/deploy-zip.ps1
#
# Drop the most recently built zip from dist/ into the dev profile's mods
# folder, removing any prior copies (zips OR junctions) for the same mod
# first. This is the canonical deployment for the dev game — Factorio loads
# the actual release artifact, so the in-game build is identical to what
# would ship to the mod portal.
#
# Run tools/build.ps1 first; this script does not rebuild. It fails loudly
# if the expected zip is missing rather than silently using a stale copy.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\deploy-zip.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\deploy-zip.ps1 -ModsPath "...\mods"

[CmdletBinding()]
param(
  [string]$ModsPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$modInfo  = Get-ModInfo
$repoRoot = Get-RepoRoot

if (-not $ModsPath) {
  $ModsPath = Get-DefaultModsPath
}
if (-not (Test-Path -LiteralPath $ModsPath)) {
  New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
}

$packageName = "{0}_{1}" -f $modInfo.name, $modInfo.version
$zipSource   = Join-Path $repoRoot ("dist\{0}.zip" -f $packageName)

if (-not (Test-Path -LiteralPath $zipSource)) {
  throw "Built zip not found: $zipSource. Run tools/build.ps1 first."
}

# Sweep every prior copy of this mod from the mods folder — any zip, any
# junction directory, any stray extracted directory — so the new zip is
# the only entry Factorio sees. -Recurse on Remove-Item is required for
# junction directories (PowerShell sees them as non-empty and otherwise
# prompts for confirmation; the recurse only deletes the junction itself,
# not the target).
$pattern = "{0}_*" -f $modInfo.name
foreach ($candidate in Get-ChildItem -Path $ModsPath -Force -Filter $pattern -ErrorAction SilentlyContinue) {
  Remove-Item -LiteralPath $candidate.FullName -Force -Recurse -ErrorAction SilentlyContinue
  Write-Host "Removed prior $($candidate.FullName)"
}

$zipDest = Join-Path $ModsPath ("{0}.zip" -f $packageName)
Copy-Item -LiteralPath $zipSource -Destination $zipDest -Force
Write-Host "Deployed $zipSource -> $zipDest"
