[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  # Legacy aliases. -LinkFirst used to junction the repo into mods; -ZipFirst
  # is the explicit name for the current zip-deploy flow. Kept for backward
  # compatibility with older runner jobs; both now do the same thing
  # (deploy the built zip), and the deploy is the default even without a
  # flag, so callers don't need to remember which one to pass.
  [switch]$LinkFirst,
  [switch]$ZipFirst,
  # Escape hatch if you really want to start without redeploying (e.g. you
  # already have a stale-but-acceptable zip in mods and don't want to wait
  # for the file copy).
  [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Initialize-DevProfile | Out-Null

if (-not $ModsPath) {
  $ModsPath = Get-DefaultModsPath
}

if (-not (Test-Path -LiteralPath $ModsPath)) {
  New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
}

# Default deployment: drop the built zip from dist/ into the mods folder.
# We always test the actual release artifact, so what runs in the dev game
# is byte-identical to what would ship. The -NoDeploy escape skips this.
if (-not $NoDeploy) {
  & (Join-Path $PSScriptRoot "deploy-zip.ps1") -ModsPath $ModsPath
}

$factorioRoot = Get-FactorioRoot -RequestedPath $FactorioRoot
$factorioExe = Get-FactorioExePath -FactorioRoot $factorioRoot
$configPath = Get-DefaultDevConfigPath

$arguments = @(
  "--config",
  $configPath,
  "--mod-directory",
  $ModsPath
)

Start-Process -FilePath $factorioExe -ArgumentList $arguments -WorkingDirectory $factorioRoot
Write-Host "Started Factorio from $factorioExe"
