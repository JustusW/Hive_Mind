[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  [switch]$LinkFirst
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

if ($LinkFirst) {
  & (Join-Path $PSScriptRoot "link-mod.ps1") -ModsPath $ModsPath
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
