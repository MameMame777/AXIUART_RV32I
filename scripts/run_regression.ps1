#==============================================================================
# DSIM UVM Regression Test Runner Script (PowerShell)
# Usage: .\run_regression.ps1 [options]
#
# Options:
#   -Stage N          Run specific stage tests (1, 2, etc.)
#   -Tests NAME[]     Run specific tests (array)
#   -Waves            Enable waveform capture for all tests
#   -Verbosity LVL    UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
#   -StopOnFail       Stop regression on first failure
#   -ReportFile FILE  Output report file
#   -CleanupDays N    Auto-delete logs older than N days before run (0=disable, default=7)
#   -KeepRecent N     Keep only N most recent log sets per test (0=disable, default=5)
#==============================================================================

param(
    [int]$Stage = 0,

    [string[]]$Tests = @(),

    [switch]$Waves,

    [ValidateSet("UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_DEBUG")]
    [string]$Verbosity = "UVM_LOW",

    [switch]$StopOnFail,

    [string]$ReportFile = "",

    [int]$CleanupDays = 7,

    [int]$KeepRecent = 5,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Handle comma-separated tests passed as single string (from bash)
if ($Tests.Count -eq 1 -and $Tests[0] -match ",") {
    $Tests = $Tests[0] -split ","
}

# Script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Workspace = Split-Path -Parent $ScriptDir

# Stage 1 tests
$Stage1Tests = @(
    "vexriscv_regfile_test",
    "vexriscv_alu_test",
    "vexriscv_pipeline_flow_test",
    "vexriscv_ibus_fetch_test",
    "vexriscv_memory_access_test",
    "vexriscv_ex_bypass_test",
    "vexriscv_mem_bypass_test",
    "vexriscv_wb_bypass_test",
    "vexriscv_load_use_stall_test",
    "vexriscv_dbus_access_test"
)

# Stage 2 tests (ISA compliance via upstream hex files)
$Stage2Tests = @(
    "vexriscv_isa_add_test",
    "vexriscv_isa_addi_test"
)

# Show help
if ($Help) {
    Write-Host @"
Usage: .\run_regression.ps1 [options]

Options:
  -Stage N          Run specific stage tests (1, 2, etc.)
  -Tests NAME[]     Run specific tests (array)
  -Waves            Enable waveform capture
  -Verbosity LVL    UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
  -StopOnFail       Stop on first failure
  -ReportFile FILE  Output report file
  -CleanupDays N    Auto-delete logs older than N days (0=disable, default=7)
  -KeepRecent N     Keep only N most recent log sets per test (0=disable, default=5)
  -Help             Show this help

Available Stage 1 tests:
"@
    foreach ($t in $Stage1Tests) {
        Write-Host "  - $t"
    }
    Write-Host ""
    Write-Host "Available Stage 2 tests (ISA compliance):"
    foreach ($t in $Stage2Tests) {
        Write-Host "  - $t"
    }
    exit 0
}

# Determine which tests to run
$TestsToRun = @()

if ($Tests.Count -gt 0) {
    $TestsToRun = $Tests
} elseif ($Stage -gt 0) {
    switch ($Stage) {
        1 { $TestsToRun = $Stage1Tests }
        2 { $TestsToRun = $Stage2Tests }
        default {
            Write-Error "Unknown stage: $Stage (available: 1, 2)"
            exit 1
        }
    }
} else {
    # Default: run all Stage 1 tests
    $TestsToRun = $Stage1Tests
}

# Directories
$LogDir = Join-Path $Workspace "sim\exec\logs"
$WaveDir = Join-Path $Workspace "sim\exec\wave"

# Cleanup old log files
function Cleanup-OldLogs {
    param([int]$Days)

    $cutoffDate = (Get-Date).AddDays(-$Days)
    $deletedCount = 0
    $totalSize = 0

    # Cleanup log files
    if (Test-Path $LogDir) {
        $oldFiles = Get-ChildItem -Path $LogDir -File -Recurse |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        foreach ($file in $oldFiles) {
            $totalSize += $file.Length
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            $deletedCount++
        }
    }

    # Cleanup wave files
    if (Test-Path $WaveDir) {
        $oldWaves = Get-ChildItem -Path $WaveDir -File -Recurse |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        foreach ($file in $oldWaves) {
            $totalSize += $file.Length
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            $deletedCount++
        }
    }

    if ($deletedCount -gt 0) {
        $sizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Host "[Cleanup] Deleted $deletedCount files older than $Days days ($sizeMB MB)"
    }
}

# Cleanup per-test logs keeping only the N most recent sets
function Cleanup-PerTestLogs {
    param([int]$Keep)

    $deletedCount = 0
    $totalSize = 0

    foreach ($dir in @($LogDir, $WaveDir)) {
        if (-not (Test-Path $dir)) { continue }

        $files = Get-ChildItem -Path $dir -File
        # Group files by test name (strip timestamp suffix)
        $groups = $files | Group-Object {
            if ($_.BaseName -match '^(.+?)_\d{8}_\d{6}') {
                $Matches[1]
            } else {
                $_.BaseName
            }
        }

        foreach ($group in $groups) {
            if ($group.Count -le $Keep) { continue }

            # Sort by LastWriteTime descending, skip the newest $Keep
            $toDelete = $group.Group |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip $Keep

            foreach ($file in $toDelete) {
                $totalSize += $file.Length
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                $deletedCount++
            }
        }
    }

    if ($deletedCount -gt 0) {
        $sizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Host "[Cleanup] Deleted $deletedCount excess log files (keeping $Keep most recent per test, $sizeMB MB freed)"
    }
}

# Auto-cleanup if requested
if ($CleanupDays -gt 0) {
    Cleanup-OldLogs -Days $CleanupDays
}
if ($KeepRecent -gt 0) {
    Cleanup-PerTestLogs -Keep $KeepRecent
}

# Setup report file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (-not $ReportFile) {
    $ReportFile = Join-Path $LogDir "regression_${timestamp}.txt"
}

# Results tracking
$results = @{}
$passCount = 0
$failCount = 0
$skipCount = 0

# Run single test
function Run-SingleTest {
    param([string]$TestName)

    $testScript = Join-Path $ScriptDir "run_test.ps1"
    $argString = "-ExecutionPolicy Bypass -File `"$testScript`" `"$TestName`" -Verbosity $Verbosity"
    if ($Waves) {
        $argString += " -Waves"
    }

    Write-Host "Running: $TestName"

    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $argString `
        -Wait -PassThru -NoNewWindow

    return $process.ExitCode
}

# Print banner
Write-Host "============================================================"
Write-Host "DSIM UVM Regression Runner"
Write-Host "============================================================"
Write-Host "Timestamp: $timestamp"
Write-Host "Tests to run: $($TestsToRun.Count)"
Write-Host "Verbosity: $Verbosity"
Write-Host "Waves: $(if ($Waves) { 'Enabled' } else { 'Disabled' })"
Write-Host "Stop on fail: $(if ($StopOnFail) { 'Yes' } else { 'No' })"
Write-Host "Report: $ReportFile"
Write-Host "============================================================"
Write-Host ""

# Initialize report
$reportHeader = @"
================================================================================
DSIM UVM Regression Report
================================================================================
Timestamp: $timestamp
Tests: $($TestsToRun.Count)
Verbosity: $Verbosity

--------------------------------------------------------------------------------
TEST RESULTS
--------------------------------------------------------------------------------
"@
$reportHeader | Out-File -FilePath $ReportFile -Encoding UTF8

# Run tests
$testIndex = 0
foreach ($testName in $TestsToRun) {
    $testIndex++
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "[$testIndex/$($TestsToRun.Count)] $testName"
    Write-Host "------------------------------------------------------------"

    $startTime = Get-Date

    $exitCode = Run-SingleTest -TestName $testName

    # Prefer result JSON from run_test to determine status
    $resultJsonFile = Get-ChildItem -Path $LogDir -Filter "${testName}_*_result.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($resultJsonFile) {
        $resultJson = Get-Content $resultJsonFile.FullName | ConvertFrom-Json
        if ($null -ne $resultJson.exit_code) {
            $exitCode = [int]$resultJson.exit_code
        } elseif ($resultJson.status -eq "success") {
            $exitCode = 0
        } else {
            $exitCode = 1
        }
    }

    $endTime = Get-Date
    $duration = [int]($endTime - $startTime).TotalSeconds

    if ($exitCode -eq 0) {
        $results[$testName] = "PASS"
        $passCount++
        $result = "PASS"
    } else {
        $results[$testName] = "FAIL"
        $failCount++
        $result = "FAIL"

        if ($StopOnFail) {
            Write-Host ""
            Write-Host "STOPPING: Test failed and -StopOnFail is set"
            $skipCount = $TestsToRun.Count - $passCount - $failCount
            break
        }
    }

    # Append to report
    "{0,-40} {1} ({2}s)" -f $testName, $result, $duration | Out-File -FilePath $ReportFile -Append -Encoding UTF8
}

# Summary
Write-Host ""
Write-Host "============================================================"
Write-Host "REGRESSION SUMMARY"
Write-Host "============================================================"
Write-Host "Total:   $($TestsToRun.Count)"
Write-Host "Passed:  $passCount"
Write-Host "Failed:  $failCount"
Write-Host "Skipped: $skipCount"
Write-Host ""

if ($failCount -eq 0 -and $skipCount -eq 0) {
    Write-Host "Status: ALL TESTS PASSED"
    $overallStatus = "PASS"
} else {
    Write-Host "Status: REGRESSION FAILED"
    $overallStatus = "FAIL"
}

Write-Host "============================================================"
Write-Host "Report: $ReportFile"

# Finalize report
$reportSummary = @"

--------------------------------------------------------------------------------
SUMMARY
--------------------------------------------------------------------------------
Total:   $($TestsToRun.Count)
Passed:  $passCount
Failed:  $failCount
Skipped: $skipCount
Status:  $overallStatus
================================================================================
"@
$reportSummary | Out-File -FilePath $ReportFile -Append -Encoding UTF8

# Generate JSON report
$jsonReportFile = $ReportFile -replace "\.txt$", ".json"
$jsonReport = @{
    timestamp = $timestamp
    total_tests = $TestsToRun.Count
    passed = $passCount
    failed = $failCount
    skipped = $skipCount
    status = $overallStatus
    results = $results
} | ConvertTo-Json -Depth 3

$jsonReport | Out-File -FilePath $jsonReportFile -Encoding UTF8
Write-Host "JSON Report: $jsonReportFile"

# Exit with appropriate code
if ($overallStatus -eq "PASS") {
    exit 0
} else {
    exit 1
}
