[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = "",
  [int]$UntilTick = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$profileName = "runtime-{0}" -f ([guid]::NewGuid().ToString("N"))
Initialize-DevProfile -ProfileName $profileName | Out-Null

if (-not $ModsPath) {
  $ModsPath = Get-DefaultModsPath
}

if (-not (Test-Path -LiteralPath $ModsPath)) {
  New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
}

& (Join-Path $PSScriptRoot "link-mod.ps1") -ModsPath $ModsPath

$factorioRoot = Get-FactorioRoot -RequestedPath $FactorioRoot
$factorioExe = Get-FactorioExePath -FactorioRoot $factorioRoot
$configPath = Get-DefaultDevConfigPath -ProfileName $profileName
$playerDataPath = Get-DefaultDevPlayerDataPath -ProfileName $profileName
$savePath = Join-Path $playerDataPath "hive-mind-runtime-check.zip"
$lockPath = Join-Path $playerDataPath ".lock"

& $factorioExe --config $configPath --mod-directory $ModsPath --create $savePath --disable-audio
$createExitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
if ($createExitCode -ne 0) {
  exit $createExitCode
}

$saveReady = $false
# Factorio writes the save asynchronously after the --create process exits.
# Allow up to 30 seconds before failing.
for ($attempt = 0; $attempt -lt 120; $attempt++) {
  if (Test-Path -LiteralPath $savePath) {
    $saveReady = $true
    break
  }
  Start-Sleep -Milliseconds 250
}

if (-not $saveReady) {
  throw "Runtime smoke test could not find the generated save: $savePath"
}

# Wait for the profile lock to clear (Factorio holds it briefly post-write).
for ($attempt = 0; $attempt -lt 120; $attempt++) {
  if (-not (Test-Path -LiteralPath $lockPath)) {
    break
  }
  Start-Sleep -Milliseconds 250
}

if (Test-Path -LiteralPath $lockPath) {
  throw "Runtime smoke test profile lock did not clear after map creation: $lockPath"
}

& $factorioExe --config $configPath --mod-directory $ModsPath --load-game $savePath --until-tick $UntilTick --disable-audio
