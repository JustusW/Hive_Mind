[CmdletBinding()]
param(
  [string]$FactorioRoot = "",
  [string]$ModsPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$profileName = "check-{0}" -f ([guid]::NewGuid().ToString("N"))
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

# Use Start-Process -PassThru so we can read ExitCode reliably under
# Set-StrictMode -Version Latest, where touching an unset $LASTEXITCODE throws.
$proc = Start-Process `
  -FilePath $factorioExe `
  -ArgumentList @("--config", $configPath, "--mod-directory", $ModsPath, "--dump-data", "--disable-audio") `
  -NoNewWindow `
  -Wait `
  -PassThru
exit $proc.ExitCode
