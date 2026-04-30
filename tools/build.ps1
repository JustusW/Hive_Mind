# tools/build.ps1
#
# Pack the mod into a release zip ready for upload to the Factorio mod portal.
#
# Reads info.json for the mod name and version, copies the mod-runtime files
# into a staging directory named "<name>_<version>", zips it, and writes the
# result to <repo>/dist/<name>_<version>.zip.
#
# Excluded from the package: dev tooling (tools/, .vscode/, .factorio-dev/,
# .git/, .cowork/, dist/, tmp/), internal design docs (HIVE_DESIGN.md,
# DEVELOPMENT.md, prompt_preferences.md), and the legacy reference port.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\build.ps1

[CmdletBinding()]
param(
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot = Get-RepoRoot
if (-not $OutputDir) {
  $OutputDir = Join-Path $repoRoot "dist"
}
$info        = Get-ModInfo
$packageName = "{0}_{1}" -f $info.name, $info.version

Write-Host "Building $packageName" -ForegroundColor Cyan
Write-Host "  source:  $repoRoot"
Write-Host "  output:  $OutputDir"

# Files / directories shipped in the release zip. Anything not listed here
# stays out of the package — keep this list explicit rather than relying on
# excludes, so the release can never accidentally pick up a dev artefact.
$includes = @(
  "info.json",
  "data.lua",
  "data-updates.lua",
  "control.lua",
  "shared.lua",
  "changelog.txt",
  "readme.md",
  "HIVE_REBOOT_REQUIREMENTS.md",
  "data",
  "script",
  "locale"
)

# Optional files: copied if present, ignored otherwise. Useful for assets
# (thumbnail.png) and graphics directories that might land later.
$optional = @(
  "thumbnail.png",
  "graphics"
)

$staging    = Join-Path $env:TEMP ("hm-build-" + [guid]::NewGuid().ToString("N"))
$packageDir = Join-Path $staging $packageName
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

try {
  foreach ($entry in $includes) {
    $source = Join-Path $repoRoot $entry
    if (-not (Test-Path -LiteralPath $source)) {
      throw "Required entry missing from package: $entry"
    }
    $dest = Join-Path $packageDir $entry
    if ((Get-Item -LiteralPath $source).PSIsContainer) {
      Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
    } else {
      Copy-Item -LiteralPath $source -Destination $dest -Force
    }
  }

  foreach ($entry in $optional) {
    $source = Join-Path $repoRoot $entry
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $dest = Join-Path $packageDir $entry
    if ((Get-Item -LiteralPath $source).PSIsContainer) {
      Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
    } else {
      Copy-Item -LiteralPath $source -Destination $dest -Force
    }
  }

  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
  $zipPath = Join-Path $OutputDir ("{0}.zip" -f $packageName)
  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }

  # Zip the wrapping folder so the resulting archive has
  # "<name>_<version>/info.json" at its root — Factorio's mod portal
  # validates that the top-level entry inside the zip is the mod folder.
  Compress-Archive `
    -Path $packageDir `
    -DestinationPath $zipPath `
    -CompressionLevel Optimal

  $size = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB, 1)
  Write-Host ("Built {0} ({1} KB)" -f $zipPath, $size) -ForegroundColor Green
}
finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
