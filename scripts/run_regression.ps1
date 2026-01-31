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
#==============================================================================

param(
    [int]$Stage = 0,

    [string[]]$Tests = @(),

    [switch]$Waves,

    [ValidateSet("UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_DEBUG")]
    [string]$Verbosity = "UVM_LOW",

    [switch]$StopOnFail,

    [string]$ReportFile = "",

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
  -Help             Show this help

Available Stage 1 tests:
"@
    foreach ($t in $Stage1Tests) {
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
        default {
            Write-Error "Unknown stage: $Stage"
            exit 1
        }
    }
} else {
    # Default: run all Stage 1 tests
    $TestsToRun = $Stage1Tests
}

# Setup report file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = Join-Path $Workspace "sim\exec\logs"
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
