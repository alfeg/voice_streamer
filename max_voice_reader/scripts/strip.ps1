# Replayable strip (PowerShell): delete every path in scripts/strip.manifest.
# Idempotent — re-runnable after a fresh `git checkout upstream-mirror` to reproduce
# the lean tree. See scripts/strip.manifest for the PREREQUISITE (de-shell refactor).
#
# Usage: pwsh scripts/strip.ps1 [-DryRun]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $PSScriptRoot 'strip.manifest'
if (-not (Test-Path $manifest)) { Write-Error "manifest not found: $manifest"; exit 1 }

$removed = 0
foreach ($raw in Get-Content $manifest) {
    $line = ($raw -replace '#.*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $target = Join-Path $root $line
    if (-not (Test-Path $target)) { Write-Host "skip (absent): $line"; continue }
    if ($DryRun) { Write-Host "would remove: $line"; continue }

    $tracked = $false
    try { git -C $root ls-files --error-unmatch $line 2>$null | Out-Null; $tracked = ($LASTEXITCODE -eq 0) } catch {}
    if ($tracked) { git -C $root rm -r --quiet $line } else { Remove-Item -Recurse -Force $target }
    Write-Host "removed: $line"
    $removed++
}

Write-Host '---'
if ($DryRun) { Write-Host 'dry-run complete' } else { Write-Host "stripped $removed path(s)" }
Write-Host "Next: prune the pubspec deps noted at the bottom of strip.manifest, then 'flutter pub get' and 'flutter analyze'."
