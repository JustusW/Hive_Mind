# tools/restart-headless-server.ps1
#
# Stop the running headless Factorio server (if any) and start a fresh
# instance with the current built mod. Identifies the server by its
# command-line — only processes started with --start-server* are killed,
# so a connected dev client survives the restart and can immediately
# rejoin once the server is back up.
#
# Mirrors restart-factorio.ps1 but scoped to the server sub-profile.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\restart-headless-server.ps1
#   .\tools\restart-headless-server.ps1 -Fresh         # discard saves first
#   .\tools\restart-headless-server.ps1 -Port 34198    # non-default port

[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  [int]   $Port = 34197,
  [switch]$Fresh,
  [switch]$NoDeploy,
  [int]   $ShutdownTimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

# Find every factorio.exe process whose command line includes the server
# launch flag. We use Win32_Process so we can inspect CommandLine — plain
# Get-Process doesn't expose it.
$cimQuery = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'factorio.exe'" -ErrorAction SilentlyContinue
$serverProcs = @($cimQuery | Where-Object {
  $_.CommandLine -and $_.CommandLine -match '--start-server'
})

if ($serverProcs.Count -gt 0) {
  $processIds = @($serverProcs | ForEach-Object { [int]$_.ProcessId })
  Write-Host "Stopping headless server process(es): $($processIds -join ', ')"
  Stop-Process -Id $processIds -Force

  # Wait for shutdown so we don't race the new server against a half-dead
  # one still holding the UDP port.
  $deadline = (Get-Date).AddSeconds($ShutdownTimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $stillRunning = @(Get-Process -Id $processIds -ErrorAction SilentlyContinue)
  } while ($stillRunning.Count -gt 0 -and (Get-Date) -lt $deadline)

  if ($stillRunning.Count -gt 0) {
    throw "Timed out waiting for headless server to close (PIDs: $($processIds -join ', '))."
  }
} else {
  Write-Host "No running headless server found; starting fresh."
}

# Forward the relevant flags to start-headless-server.ps1.
$arguments = @{ Port = $Port }
if ($FactorioRoot) { $arguments.FactorioRoot = $FactorioRoot }
if ($ModsPath)     { $arguments.ModsPath     = $ModsPath }
if ($Fresh)        { $arguments.Fresh        = $true }
if ($NoDeploy)     { $arguments.NoDeploy     = $true }

& (Join-Path $PSScriptRoot "start-headless-server.ps1") @arguments
