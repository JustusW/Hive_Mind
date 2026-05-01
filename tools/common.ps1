Set-StrictMode -Version Latest

function Get-RepoRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Get-DefaultDevRoot {
  $override = $env:HIVE_MIND_FACTORIO_DEV_ROOT
  if ($override) {
    return $override
  }

  $repoRoot = Get-RepoRoot
  $workspaceRoot = Split-Path -Parent $repoRoot
  $repoName = Split-Path -Leaf $repoRoot
  return (Join-Path $workspaceRoot ("{0}-dev-profile" -f $repoName))
}

function Resolve-NormalizedPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (Resolve-Path -LiteralPath $Path).Path.TrimEnd("\")
}

function Get-DefaultDevModsPath {
  $devRoot = Get-DefaultDevRoot
  return (Join-Path $devRoot "mods")
}

function Get-DefaultDevPlayerDataPath {
  param(
    [string]$ProfileName = "gui"
  )

  $devRoot = Get-DefaultDevRoot
  if ($ProfileName -eq "gui") {
    return (Join-Path $devRoot "player-data")
  }
  return (Join-Path $devRoot ("{0}-player-data" -f $ProfileName))
}

function Get-DefaultDevConfigPath {
  param(
    [string]$ProfileName = "gui"
  )

  $devRoot = Get-DefaultDevRoot
  if ($ProfileName -eq "gui") {
    return (Join-Path $devRoot "config.ini")
  }
  return (Join-Path $devRoot ("{0}-config.ini" -f $ProfileName))
}

function Get-ModInfo {
  $repoRoot = Get-RepoRoot
  $infoPath = Join-Path $repoRoot "info.json"
  if (-not (Test-Path -LiteralPath $infoPath)) {
    throw "Missing info.json at $infoPath"
  }

  return (Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json)
}

function Get-DefaultModsPath {
  return (Get-DefaultDevModsPath)
}

# The mods folder Factorio uses when launched normally (Steam / standalone)
# without a custom --mod-directory. On Windows that's
# %APPDATA%\Factorio\mods. Returns $null if APPDATA isn't set (e.g. running
# under a service account); callers should treat the result as optional.
function Get-ProductionModsPath {
  $appdata = $env:APPDATA
  if (-not $appdata) { return $null }
  return (Join-Path $appdata "Factorio\mods")
}

function Initialize-DevProfile {
  param(
    [string]$ProfileName = "gui"
  )

  $modsPath = Get-DefaultDevModsPath
  $playerDataPath = Get-DefaultDevPlayerDataPath -ProfileName $ProfileName
  $configPath = Get-DefaultDevConfigPath -ProfileName $ProfileName
  $modInfo = Get-ModInfo
  $devRoot = Get-DefaultDevRoot

  New-Item -ItemType Directory -Path $devRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $modsPath -Force | Out-Null
  New-Item -ItemType Directory -Path $playerDataPath -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $playerDataPath "config") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $playerDataPath "script-output") -Force | Out-Null

  $configContent = @"
[path]
read-data=__PATH__system-read-data__
write-data=$playerDataPath

[general]
locale=auto
"@

  Set-Content -LiteralPath $configPath -Value $configContent -Encoding ASCII

  # Only seed mod-list.json on first run. After that the user (and the
  # in-game mod manager) own it — overwriting on every launch wipes any
  # other mods they enabled and causes ModsMismatch when the dev client
  # and dev server are launched in different orders or after enabling a
  # mod via the GUI.
  $modListPath = Join-Path $modsPath "mod-list.json"
  if (-not (Test-Path -LiteralPath $modListPath)) {
    $modList = @{
      mods = @(
        @{ name = "base"; enabled = $true },
        @{ name = "elevated-rails"; enabled = $false },
        @{ name = "quality"; enabled = $false },
        @{ name = "space-age"; enabled = $false },
        @{ name = $modInfo.name; enabled = $true }
      )
    } | ConvertTo-Json -Depth 4

    Set-Content -LiteralPath $modListPath -Value $modList -Encoding ASCII
  }

  return @{
    ConfigPath = $configPath
    ModsPath = $modsPath
    PlayerDataPath = $playerDataPath
  }
}

function Get-FactorioRoot {
  param(
    [string]$RequestedPath
  )

  if ($RequestedPath) {
    if (-not (Test-Path -LiteralPath $RequestedPath)) {
      throw "Factorio install path does not exist: $RequestedPath"
    }
    return $RequestedPath
  }

  $candidates = @(
    "E:\SteamLibrary\steamapps\common\Factorio",
    "C:\Program Files (x86)\Steam\steamapps\common\Factorio",
    "C:\Program Files\Factorio"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "Could not find a Factorio install. Pass -FactorioRoot explicitly."
}

function Get-FactorioExePath {
  param(
    [string]$FactorioRoot
  )

  $exePath = Join-Path $FactorioRoot "bin\x64\factorio.exe"
  if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find factorio.exe at $exePath"
  }

  return $exePath
}
