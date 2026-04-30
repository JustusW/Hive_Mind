# tools/build.ps1
#
# Pack the mod into a release zip ready for upload to the Factorio mod portal.
#
# Reads info.json for the mod name and version, copies the mod-runtime files
# into a staging directory named "<name>_<version>", zips it, and writes the
# result to <repo>/dist/<name>_<version>.zip.
#
# Excluded from the package: dev tooling (tools/, .vscode/, .factorio-dev/,
# .git/, .cowork/, dist/, tmp/), internal design docs (design.md,
# DEVELOPMENT.md, prompt_preferences.md, working_requirements.md), and the
# legacy reference port.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\build.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\build.ps1 -WinRarPath "C:\Program Files\WinRAR\WinRAR.exe"

[CmdletBinding()]
param(
  [string]$OutputDir = "",
  [string]$WinRarPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Get-WinRarPath {
  param(
    [string]$RequestedPath
  )

  if ($RequestedPath) {
    if (-not (Test-Path -LiteralPath $RequestedPath)) {
      throw "WinRAR path does not exist: $RequestedPath"
    }
    return (Resolve-Path -LiteralPath $RequestedPath).Path
  }

  $command = Get-Command "WinRAR.exe" -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    "C:\Program Files\WinRAR\WinRAR.exe",
    "C:\Program Files (x86)\WinRAR\WinRAR.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "Could not find WinRAR.exe. Install WinRAR or pass -WinRarPath explicitly."
}

function Quote-ProcessArgument {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Argument
  )

  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  return '"' + ($Argument -replace '"', '\"') + '"'
}

function Copy-FileReplacingContent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $sourceStream = [System.IO.File]::Open(
    $SourcePath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::Read
  )
  try {
    $destinationStream = [System.IO.File]::Open(
      $DestinationPath,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    try {
      $destinationStream.SetLength(0)
      $sourceStream.CopyTo($destinationStream)
    }
    finally {
      $destinationStream.Dispose()
    }
  }
  finally {
    $sourceStream.Dispose()
  }
}

$repoRoot = Get-RepoRoot
if (-not $OutputDir) {
  $OutputDir = Join-Path $repoRoot "dist"
}
$info        = Get-ModInfo
$packageName = "{0}_{1}" -f $info.name, $info.version
$winRarPath  = Get-WinRarPath -RequestedPath $WinRarPath

Write-Host "Building $packageName" -ForegroundColor Cyan
Write-Host "  source:  $repoRoot"
Write-Host "  output:  $OutputDir"
Write-Host "  archiver: $winRarPath"

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
  "requirements.md",
  "data",
  "script",
  "locale"
)

# Optional files: copied if present, ignored otherwise. Useful for assets
# (thumbnail.png) and graphics directories that might land later.
$optional = @(
  "thumbnail.png",
  "graphics",
  "sound"
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
  $zipPath       = Join-Path $OutputDir ("{0}.zip" -f $packageName)
  $stagedZipPath = Join-Path $staging ("{0}.zip" -f $packageName)

  # Zip the wrapping folder so the resulting archive has
  # "<name>_<version>/info.json" at its root — Factorio's mod portal
  # validates that the top-level entry inside the zip is the mod folder.
  # PowerShell Compress-Archive can store Windows backslashes in entry names,
  # which the mod portal rejects for Linux/macOS compatibility.
  $arguments = @(
    "a",
    "-afzip",
    "-ibck",
    "-y",
    "-r",
    $stagedZipPath,
    $packageName
  ) | ForEach-Object { Quote-ProcessArgument -Argument $_ }

  $process = Start-Process `
    -FilePath $winRarPath `
    -ArgumentList $arguments `
    -WorkingDirectory $staging `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

  if ($process.ExitCode -ne 0) {
    throw "WinRAR failed with exit code $($process.ExitCode)."
  }

  Copy-FileReplacingContent -SourcePath $stagedZipPath -DestinationPath $zipPath

  $size = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB, 1)
  Write-Host ("Built {0} ({1} KB)" -f $zipPath, $size) -ForegroundColor Green
}
finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
