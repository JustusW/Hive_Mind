# tools/start-runner.ps1
#
# Wrapper around cowork-runner.ps1 that re-launches it in place when the
# runner exits with sentinel code 75 (the "restart" action). Anything else
# (including Ctrl+C / 0) breaks out of the loop.
#
# Use this instead of running cowork-runner.ps1 directly:
#
#   powershell -ExecutionPolicy Bypass -File .\tools\start-runner.ps1

[CmdletBinding()]
param(
  [string]$RepoRoot,
  [int]$PollMs = 500
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$runner    = Join-Path $scriptDir "cowork-runner.ps1"

while ($true) {
  # Hashtable splat -> named parameter binding. Array splat would bind
  # positionally and pass "-PollMs" as a value to $RepoRoot.
  $splat = @{}
  if ($RepoRoot) { $splat.RepoRoot = $RepoRoot }
  if ($PollMs)   { $splat.PollMs   = $PollMs }

  & $runner @splat
  $code = $LASTEXITCODE

  if ($code -ne 75) {
    Write-Host ""
    Write-Host "[wrapper] runner exited with code $code, stopping." -ForegroundColor DarkGray
    break
  }

  Write-Host ""
  Write-Host "[wrapper] runner asked to restart, relaunching..." -ForegroundColor Magenta
  Start-Sleep -Milliseconds 250
}
