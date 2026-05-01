# tools/start-headless-server.ps1
#
# Spin up a headless Factorio server with the current built mod loaded, so a
# dev client on the same machine (or LAN) can join and reproduce MP-only
# behaviour. Uses its own dev profile under <repo-parent>\<repo>-dev-profile
# so it doesn't trample the regular dev profile state.
#
# First run (no saves yet): starts on the base/freeplay scenario. Save
# in-game once and subsequent runs auto-load the latest save unless -Fresh
# is passed.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\start-headless-server.ps1
#   .\tools\start-headless-server.ps1 -Fresh           # discard saves, fresh world
#   .\tools\start-headless-server.ps1 -Port 34198      # non-default port
#
# Connect from a dev client with: localhost or 127.0.0.1 and the port.

[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  [int]   $Port      = 34197,
  [switch]$Fresh,
  [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

# Dedicated "server" sub-profile so the dev client (default profile) and the
# server can run side-by-side without sharing config.ini or saves.
$profileName    = "server"
$profile        = Initialize-DevProfile -ProfileName $profileName

$configPath     = $profile.ConfigPath
$playerDataPath = $profile.PlayerDataPath

if (-not $ModsPath) {
  # Server reuses the same mods folder as the client dev profile so we only
  # have to deploy the zip once. Saves a copy round-trip.
  $ModsPath = Get-DefaultModsPath
}
if (-not (Test-Path -LiteralPath $ModsPath)) {
  New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
}

# Always test the actual zip artifact (same rule as start-factorio.ps1).
if (-not $NoDeploy) {
  & (Join-Path $PSScriptRoot "deploy-zip.ps1") -ModsPath $ModsPath
}

$factorioRoot = Get-FactorioRoot -RequestedPath $FactorioRoot
$factorioExe  = Get-FactorioExePath -FactorioRoot $factorioRoot

$savesDir = Join-Path $playerDataPath "saves"
New-Item -ItemType Directory -Path $savesDir -Force | Out-Null

# Pick a launch mode. A pre-existing save lets the host iterate on the same
# world; -Fresh wipes it and starts on freeplay so a clean run can be set up.
$existingSaves = Get-ChildItem -LiteralPath $savesDir -Filter "*.zip" -ErrorAction SilentlyContinue

$arguments = @(
  "--config",         $configPath,
  "--mod-directory",  $ModsPath,
  "--port",           "$Port"
)

if ($Fresh -or -not $existingSaves) {
  if ($Fresh -and $existingSaves) {
    foreach ($f in $existingSaves) {
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Cleared existing saves in $savesDir"
  }
  Write-Host "Starting headless server from base/freeplay scenario on port $Port"
  $arguments += @("--start-server-load-scenario", "base/freeplay")
} else {
  Write-Host "Starting headless server, loading latest save in $savesDir on port $Port"
  $arguments += @("--start-server-load-latest")
}

Write-Host "  factorio: $factorioExe"
Write-Host "  config:   $configPath"
Write-Host "  mods:     $ModsPath"
Write-Host "  saves:    $savesDir"
Write-Host ""
Write-Host "Connect from a client with: localhost:$Port (or 127.0.0.1:$Port)"
Write-Host ""

Start-Process -FilePath $factorioExe -ArgumentList $arguments -WorkingDirectory $factorioRoot
Write-Host "Headless server launched."
