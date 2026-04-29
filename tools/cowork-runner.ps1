# tools/cowork-runner.ps1
#
# A small approval-gated runner you keep open in a PowerShell window so Claude
# (sandboxed Linux, file-only access to this repo) can ask you to execute
# commands on your Windows host.
#
# Protocol -- all files live under <repo>/.cowork/ :
#
#   inbox/<id>.json   Claude writes here:  { id, description, command, cwd? }
#   outbox/<id>.log   runner streams stdout+stderr here as the command runs
#   outbox/<id>.exit  runner writes the exit code here when the command finishes
#                       0      success
#                       -1     you declined
#                       other  the command's actual exit code
#
# Workflow:
#   1. Claude writes a request file.
#   2. The runner prints the description + literal command and prompts y/N.
#   3. On y the command runs, output streams to this window AND to the log.
#   4. The .exit file appearing is Claude's signal that the run is complete;
#      Claude then reads outbox/<id>.log to see what happened.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\cowork-runner.ps1
#
# Press Ctrl+C to stop.

[CmdletBinding()]
param(
  [string]$RepoRoot,
  [int]$PollMs = 500
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot can be empty when the script is invoked in unusual ways
# (older PowerShell, dot-source from a host that doesn't set it, etc.).
# Resolve a script directory robustly, then default RepoRoot to its parent.
if (-not $RepoRoot) {
  $scriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
  } elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
  } else {
    (Get-Location).Path
  }
  $RepoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

$root   = Join-Path $RepoRoot ".cowork"
$inbox  = Join-Path $root "inbox"
$outbox = Join-Path $root "outbox"
New-Item -ItemType Directory -Path $inbox  -Force | Out-Null
New-Item -ItemType Directory -Path $outbox -Force | Out-Null

function Write-Banner {
  param([string]$Title, [ConsoleColor]$Color = "Cyan")
  Write-Host ""
  Write-Host ("-" * 72) -ForegroundColor DarkGray
  Write-Host $Title -ForegroundColor $Color
  Write-Host ("-" * 72) -ForegroundColor DarkGray
}

function Process-Request {
  param([System.IO.FileInfo]$File)

  $req = $null
  try {
    $req = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Host "[skip] malformed request: $($File.Name) - $($_.Exception.Message)" -ForegroundColor Yellow
    Remove-Item -LiteralPath $File.FullName -Force
    return
  }

  $id   = if ($req.id)          { $req.id }          else { [guid]::NewGuid().ToString("N").Substring(0,12) }
  $desc = if ($req.description) { $req.description } else { "(no description)" }
  $cmd  = $req.command
  $cwd  = if ($req.cwd)         { $req.cwd }         else { $RepoRoot }

  $log    = Join-Path $outbox "$id.log"
  $status = Join-Path $outbox "$id.exit"

  # Special action: runner restart. No prompt, exits with sentinel code 75
  # so the start-runner.ps1 wrapper re-launches us in place. Action-only
  # requests don't need a command field.
  if ($req.action -eq "restart") {
    Write-Banner "RESTART  $id" Magenta
    Write-Host "WHAT     " -NoNewline; Write-Host $desc
    Set-Content -LiteralPath $log    -Value "Runner restarted by request." -Encoding UTF8
    Set-Content -LiteralPath $status -Value "0"                            -Encoding UTF8
    Remove-Item -LiteralPath $File.FullName -Force
    Write-Host "[restarting]" -ForegroundColor Magenta
    exit 75
  }

  if (-not $cmd) {
    Write-Host "[skip] request has no command: $($File.Name)" -ForegroundColor Yellow
    Remove-Item -LiteralPath $File.FullName -Force
    return
  }

  # No interactive approval -- Claude is expected to ask in chat before
  # writing the inbox file. The runner just announces what it's about to do
  # and runs it. Stop with Ctrl+C if you need to abort mid-stream.
  Write-Banner "REQUEST  $id"
  Write-Host "WHAT     " -NoNewline; Write-Host $desc
  Write-Host "CWD      " -NoNewline; Write-Host $cwd
  Write-Host "COMMAND  " -NoNewline; Write-Host $cmd -ForegroundColor Yellow
  Write-Host "LOG      " -NoNewline; Write-Host $log -ForegroundColor DarkGray
  Write-Host ("-" * 72) -ForegroundColor DarkGray
  Write-Host ""

  # Wipe any stale log; write a header so the user sees what was actually run.
  $header = @(
    "# id:      $id",
    "# desc:    $desc",
    "# cwd:     $cwd",
    "# command: $cmd",
    "# started: $(Get-Date -Format o)",
    ("-" * 72)
  ) -join "`r`n"
  Set-Content -LiteralPath $log -Value $header -Encoding UTF8

  $exit = 0
  # StreamWriter so we control the file encoding (Tee-Object on PS5 always
  # writes UTF-16LE, which makes the log unreadable to most tools).
  $writer = [System.IO.StreamWriter]::new($log, $true, [System.Text.UTF8Encoding]::new($false))
  # Save and relax the error preference so a native command writing to stderr
  # (e.g. git's CRLF warning) doesn't abort the rest of the user's command
  # chain. We restore it in the finally block.
  $prevPref = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  Push-Location $cwd
  try {
    # Build a script block from the literal command string, then invoke it
    # with *>&1 so stdout, stderr, warning, verbose, info, debug all merge
    # into the success stream we can iterate.
    $sb = [scriptblock]::Create($cmd)
    & $sb *>&1 | ForEach-Object {
      $line = $_.ToString()
      Write-Host $line
      $writer.WriteLine($line)
    }
    if ($null -ne $LASTEXITCODE) { $exit = $LASTEXITCODE }
  } catch {
    $msg = $_ | Out-String
    Write-Host $msg -ForegroundColor Red
    $writer.WriteLine($msg)
    $exit = 1
  } finally {
    $writer.Close()
    Pop-Location
    $ErrorActionPreference = $prevPref
  }

  Add-Content -LiteralPath $log -Value (("-" * 72) + "`r`n# finished: $(Get-Date -Format o) exit=$exit") -Encoding UTF8
  Set-Content -LiteralPath $status -Value $exit.ToString() -Encoding UTF8

  Write-Host ""
  Write-Host "[done] exit=$exit  log=$log" -ForegroundColor Green
  Remove-Item -LiteralPath $File.FullName -Force
}

Write-Banner "Cowork runner ready" Green
Write-Host "  watching:  $inbox"
Write-Host "  outbox:    $outbox"
Write-Host "  cwd:       $RepoRoot"
Write-Host "  poll:      $PollMs ms"
Write-Host "  stop with  Ctrl+C"
Write-Host ""

while ($true) {
  $files = @()
  try {
    $files = Get-ChildItem -LiteralPath $inbox -Filter "*.json" -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime
  } catch {}
  foreach ($f in $files) { Process-Request $f }
  Start-Sleep -Milliseconds $PollMs
}
