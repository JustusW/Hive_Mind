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

# Clean up stale junctions from previous versions of this mod so Factorio
# doesn't refuse to load with "directory name doesn't match expected".
$stalePattern = "{0}_*" -f $modInfo.name
$normalizedRepoRoot = Resolve-NormalizedPath -Path $repoRoot
foreach ($candidate in Get-ChildItem -Path $ModsPath -Directory -Filter $stalePattern -Force -ErrorAction SilentlyContinue) {
  if ($candidate.Name -eq $linkName) { continue }
  $isLink = ($candidate.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  if (-not $isLink) { continue }
  $candidateTarget = @($candidate.Target)[0]
  if (-not $candidateTarget) { continue }
  $normalizedCandidateTarget = Resolve-NormalizedPath -Path $candidateTarget
  if ($normalizedCandidateTarget -eq $normalizedRepoRoot) {
    # -Recurse is required because PowerShell sees the junction as a non-
    # empty directory and would otherwise prompt for confirmation; modern
    # PowerShell deletes only the junction, not the target.
    Remove-Item -LiteralPath $candidate.FullName -Force -Recurse
    Write-Host "Removed stale link $($candidate.FullName)"
  }
}

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

  # -Recurse: same junction-confirm-prompt issue as in the stale-link cleanup.
  Remove-Item -LiteralPath $linkPath -Force -Recurse
}

New-Item -ItemType Junction -Path $linkPath -Target $repoRoot | Out-Null
Write-Host "Linked $repoRoot -> $linkPath"
