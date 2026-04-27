[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  [switch]$LinkFirst,
  [int]$ShutdownTimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$factorioRoot = Get-FactorioRoot -RequestedPath $FactorioRoot
$factorioExe = Get-FactorioExePath -FactorioRoot $factorioRoot

$runningProcesses = @(Get-Process -Name "factorio" -ErrorAction SilentlyContinue)
if ($runningProcesses.Count -gt 0) {
  $processIds = @($runningProcesses | ForEach-Object { $_.Id })
  Stop-Process -Id $processIds -Force

  $deadline = (Get-Date).AddSeconds($ShutdownTimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $stillRunning = @(Get-Process -Id $processIds -ErrorAction SilentlyContinue)
  } while ($stillRunning.Count -gt 0 -and (Get-Date) -lt $deadline)

  if ($stillRunning.Count -gt 0) {
    throw "Timed out waiting for Factorio to close."
  }
}

$arguments = @{}
if ($FactorioRoot) {
  $arguments.FactorioRoot = $FactorioRoot
}
if ($ModsPath) {
  $arguments.ModsPath = $ModsPath
}
if ($LinkFirst) {
  $arguments.LinkFirst = $true
}

& (Join-Path $PSScriptRoot "start-factorio.ps1") @arguments
