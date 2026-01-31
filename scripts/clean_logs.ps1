#==============================================================================
# DSIM Log Cleanup Script (PowerShell)
# Usage: .\clean_logs.ps1 [options]
#
# Options:
#   -OlderThanDays N  Delete files older than N days (default: 7)
#   -DryRun           Show what would be deleted without deleting
#   -Force            Skip confirmation prompt
#   -IncludeWaves     Also delete waveform files (.mxd)
#==============================================================================

param(
    [int]$OlderThanDays = 7,

    [switch]$DryRun,

    [switch]$Force,

    [switch]$IncludeWaves,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Workspace = Split-Path -Parent $ScriptDir

# Directories to clean
$LogDir = Join-Path $Workspace "sim\exec\logs"
$WaveDir = Join-Path $Workspace "sim\exec\wave"

# Show help
if ($Help) {
    Write-Host @"
Usage: .\clean_logs.ps1 [options]

Options:
  -OlderThanDays N  Delete files older than N days (default: 7)
  -DryRun           Show what would be deleted without deleting
  -Force            Skip confirmation prompt
  -IncludeWaves     Also delete waveform files (.mxd)
  -Help             Show this help

Examples:
  .\clean_logs.ps1                     # Delete logs older than 7 days
  .\clean_logs.ps1 -OlderThanDays 3    # Delete logs older than 3 days
  .\clean_logs.ps1 -DryRun             # Preview without deleting
  .\clean_logs.ps1 -IncludeWaves       # Also delete old waveforms
"@
    exit 0
}

# Calculate cutoff date
$cutoffDate = (Get-Date).AddDays(-$OlderThanDays)

Write-Host "============================================================"
Write-Host "DSIM Log Cleanup"
Write-Host "============================================================"
Write-Host "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Delete files older than: $OlderThanDays days"
Write-Host "Dry run: $(if ($DryRun) { 'Yes' } else { 'No' })"
Write-Host "Include waves: $(if ($IncludeWaves) { 'Yes' } else { 'No' })"
Write-Host "============================================================"
Write-Host ""

# Collect files to delete
$filesToDelete = @()
$totalSize = 0

# Log files
if (Test-Path $LogDir) {
    $logFiles = Get-ChildItem -Path $LogDir -File -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }

    foreach ($file in $logFiles) {
        $filesToDelete += $file
        $totalSize += $file.Length
    }
}

# Wave files (optional)
if ($IncludeWaves -and (Test-Path $WaveDir)) {
    $waveFiles = Get-ChildItem -Path $WaveDir -File -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }

    foreach ($file in $waveFiles) {
        $filesToDelete += $file
        $totalSize += $file.Length
    }
}

# Display summary
Write-Host "Files to delete: $($filesToDelete.Count)"
Write-Host "Total size: $([math]::Round($totalSize / 1MB, 2)) MB"
Write-Host ""

if ($filesToDelete.Count -eq 0) {
    Write-Host "No files to delete."
    exit 0
}

# List files
Write-Host "Files:"
Write-Host "------------------------------------------------------------"
foreach ($file in $filesToDelete) {
    $relPath = $file.FullName.Replace($Workspace, "").TrimStart("\")
    $size = [math]::Round($file.Length / 1KB, 1)
    $date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-Host "  [$date] $relPath ($size KB)"
}
Write-Host "------------------------------------------------------------"
Write-Host ""

# Dry run - just show what would be deleted
if ($DryRun) {
    Write-Host "[DRY RUN] No files were deleted."
    exit 0
}

# Confirm deletion
if (-not $Force) {
    $confirm = Read-Host "Delete these files? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled."
        exit 0
    }
}

# Delete files
$deletedCount = 0
$errorCount = 0

foreach ($file in $filesToDelete) {
    try {
        Remove-Item -Path $file.FullName -Force
        $deletedCount++
    }
    catch {
        Write-Warning "Failed to delete: $($file.FullName)"
        $errorCount++
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "Cleanup Complete"
Write-Host "============================================================"
Write-Host "Deleted: $deletedCount files"
if ($errorCount -gt 0) {
    Write-Host "Errors: $errorCount"
}
Write-Host "Freed space: $([math]::Round($totalSize / 1MB, 2)) MB"
