# tools/deploy-zip.ps1
#
# Drop the most recently built zip from dist/ into the mods folder(s),
# removing any prior copies (zips OR junctions) for the same mod first.
# This is the canonical deployment for the dev game — Factorio loads the
# actual release artifact, so the in-game build is identical to what would
# ship to the mod portal.
#
# By default the zip is deployed to BOTH:
#   * the dev profile mods folder (factorio-dev-profile\mods\), used by
#     start-factorio.ps1 and start-headless-server.ps1
#   * the production mods folder (%APPDATA%\Factorio\mods\), used by
#     Factorio when launched normally without --mod-directory
#
# Pass -NoProd to skip the production copy (e.g. when you don't want to
# clobber whatever the actual game has loaded). Pass -ModsPath to override
# the dev target.
#
# Run tools/build.ps1 first; this script does not rebuild. It fails loudly
# if the expected zip is missing rather than silently using a stale copy.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\deploy-zip.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\deploy-zip.ps1 -ModsPath "...\mods"
#   powershell -ExecutionPolicy Bypass -File .\tools\deploy-zip.ps1 -NoProd

[CmdletBinding()]
param(
  [string]$ModsPath = "",
  [switch]$NoProd
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$modInfo  = Get-ModInfo
$repoRoot = Get-RepoRoot

$packageName = "{0}_{1}" -f $modInfo.name, $modInfo.version
$zipSource   = Join-Path $repoRoot ("dist\{0}.zip" -f $packageName)

if (-not (Test-Path -LiteralPath $zipSource)) {
  throw "Built zip not found: $zipSource. Run tools/build.ps1 first."
}

# Resolve every target. Dev path is required (created if missing). Prod
# path is optional — included by default but only deployed if the parent
# folder already exists (i.e. Factorio has been launched normally at least
# once on this machine). Skipping rather than creating means we never
# pollute %APPDATA% on a machine that doesn't have Factorio installed.
$devModsPath = $ModsPath
if (-not $devModsPath) { $devModsPath = Get-DefaultModsPath }
if (-not (Test-Path -LiteralPath $devModsPath)) {
  New-Item -ItemType Directory -Path $devModsPath -Force | Out-Null
}

$targets = @($devModsPath)
if (-not $NoProd) {
  $prodModsPath = Get-ProductionModsPath
  if ($prodModsPath -and (Test-Path -LiteralPath $prodModsPath)) {
    $targets += $prodModsPath
  } elseif ($prodModsPath) {
    Write-Host "Skipping production mods folder (does not exist): $prodModsPath"
  }
}

$pattern = "{0}_*" -f $modInfo.name

foreach ($target in $targets) {
  # Sweep every prior copy of this mod from the target — any zip, any
  # junction directory, any stray extracted directory — so the new zip is
  # the only entry Factorio sees. -Recurse on Remove-Item is required for
  # junction directories (PowerShell sees them as non-empty and otherwise
  # prompts for confirmation; the recurse only deletes the junction itself,
  # not the target).
  foreach ($candidate in Get-ChildItem -Path $target -Force -Filter $pattern -ErrorAction SilentlyContinue) {
    Remove-Item -LiteralPath $candidate.FullName -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "Removed prior $($candidate.FullName)"
  }

  $zipDest = Join-Path $target ("{0}.zip" -f $packageName)
  Copy-Item -LiteralPath $zipSource -Destination $zipDest -Force
  Write-Host "Deployed $zipSource -> $zipDest"
}
