[CmdletBinding()]
param(
  [string]$ProfileName = "gui",
  [string]$LogPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Initialize-DevProfile -ProfileName $ProfileName | Out-Null

if (-not $LogPath) {
  $LogPath = Join-Path (Get-DefaultDevPlayerDataPath -ProfileName $ProfileName) "factorio-current.log"
}

if (-not (Test-Path -LiteralPath $LogPath)) {
  throw "Factorio log was not found: $LogPath"
}

Get-Content -LiteralPath $LogPath -Wait -Tail 50
