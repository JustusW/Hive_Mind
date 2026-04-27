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

& $factorioExe --config $configPath --mod-directory $ModsPath --create $savePath --disable-audio
$createExitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
if ($createExitCode -ne 0) {
  exit $createExitCode
}

$saveReady = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
  if (Test-Path -LiteralPath $savePath) {
    $saveReady = $true
    break
  }
  Start-Sleep -Milliseconds 250
}

if (-not $saveReady) {
  throw "Runtime smoke test could not find the generated save: $savePath"
}

& $factorioExe --config $configPath --mod-directory $ModsPath --load-game $savePath --until-tick $UntilTick --disable-audio
