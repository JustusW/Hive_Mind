[CmdletBinding()]
param(
  [string]$ModsPath = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$modInfo = Get-ModInfo
$repoRoot = Get-RepoRoot

if (-not $ModsPath) {
  $ModsPath = Get-DefaultModsPath
}

if (-not (Test-Path -LiteralPath $ModsPath)) {
  New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
}

$linkName = "{0}_{1}" -f $modInfo.name, $modInfo.version
$linkPath = Join-Path $ModsPath $linkName

if (Test-Path -LiteralPath $linkPath) {
  $existingItem = Get-Item -LiteralPath $linkPath -Force
  $isLink = ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  if ($isLink) {
    $existingTarget = @($existingItem.Target)[0]
    if ($existingTarget) {
      $normalizedExistingTarget = Resolve-NormalizedPath -Path $existingTarget
      $normalizedRepoRoot = Resolve-NormalizedPath -Path $repoRoot
      if ($normalizedExistingTarget -eq $normalizedRepoRoot) {
        Write-Host "Link already points to $repoRoot"
        exit 0
      }
    }
  }

  if (-not $Force) {
    $message = "Target already exists: $linkPath"
    if ($isLink -and $existingTarget) {
      $message += "`nCurrent link target: $existingTarget"
    }
    $message += "`nRe-run with -Force if you want to replace it."
    throw $message
  }

  if (-not $isLink) {
    throw "Refusing to remove a non-link path: $linkPath"
  }

  Remove-Item -LiteralPath $linkPath -Force
}

New-Item -ItemType Junction -Path $linkPath -Target $repoRoot | Out-Null
Write-Host "Linked $repoRoot -> $linkPath"
