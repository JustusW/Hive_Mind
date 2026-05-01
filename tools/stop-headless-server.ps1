# tools/stop-headless-server.ps1
#
# Stop the headless Factorio server without restarting it. Identifies the
# server by its command-line — only processes started with --start-server*
# are killed, so a connected dev client survives.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\stop-headless-server.ps1

[CmdletBinding()]
param(
  [int]$ShutdownTimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"

$cimQuery = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'factorio.exe'" -ErrorAction SilentlyContinue
$serverProcs = @($cimQuery | Where-Object {
  $_.CommandLine -and $_.CommandLine -match '--start-server'
})

if ($serverProcs.Count -eq 0) {
  Write-Host "No running headless server found."
  return
}

$processIds = @($serverProcs | ForEach-Object { [int]$_.ProcessId })
Write-Host "Stopping headless server process(es): $($processIds -join ', ')"
Stop-Process -Id $processIds -Force

$deadline = (Get-Date).AddSeconds($ShutdownTimeoutSeconds)
do {
  Start-Sleep -Milliseconds 250
  $stillRunning = @(Get-Process -Id $processIds -ErrorAction SilentlyContinue)
} while ($stillRunning.Count -gt 0 -and (Get-Date) -lt $deadline)

if ($stillRunning.Count -gt 0) {
  throw "Timed out waiting for headless server to close (PIDs: $($processIds -join ', '))."
}

Write-Host "Headless server stopped."
