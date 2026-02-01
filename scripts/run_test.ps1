#==============================================================================
# DSIM UVM Test Runner Script (PowerShell)
# Usage: .\run_test.ps1 <test_name> [options]
#
# Options:
#   -Waves            Enable waveform capture (MXD format)
#   -Verbosity LVL    UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
#   -Seed N           Random seed (default: 1)
#   -CompileOnly      Compile only, do not run
#   -RunOnly          Run only (use existing compiled image)
#   -CleanupDays N    Auto-delete logs older than N days before run (0=disable)
#==============================================================================

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$TestName,

    [switch]$Waves,

    [ValidateSet("UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_DEBUG")]
    [string]$Verbosity = "UVM_LOW",

    [int]$Seed = 1,

    [switch]$CompileOnly,

    [switch]$RunOnly,

    [int]$CleanupDays = 0,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Workspace = Split-Path -Parent $ScriptDir

# Show help
if ($Help) {
    Write-Host @"
Usage: .\run_test.ps1 <test_name> [options]

Options:
  -Waves            Enable waveform capture
  -Verbosity LVL    UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
  -Seed N           Random seed (default: 1)
  -CompileOnly      Compile only
  -RunOnly          Run only
  -CleanupDays N    Auto-delete logs older than N days (0=disable)
  -Help             Show this help
"@
    exit 0
}

# DSIM Configuration
$DsimHome = if ($env:DSIM_HOME) { $env:DSIM_HOME } else { "C:\Program Files\Altair\DSim\2025.1" }
$TbDir = Join-Path $Workspace "sim\uvm\tb"
$LogDir = Join-Path $Workspace "sim\exec\logs"
$WaveDir = Join-Path $Workspace "sim\exec\wave"
$ConfigFile = "dsim_config.f"
$TopModule = "rv32i_tb_top"

# Setup environment
function Setup-Environment {
    $env:DSIM_HOME = $DsimHome
    $env:DSIM_ROOT = $DsimHome
    $env:DSIM_LIB_PATH = Join-Path $DsimHome "lib"

    # Add to PATH
    $paths = @(
        (Join-Path $DsimHome "bin"),
        (Join-Path $DsimHome "mingw\bin"),
        (Join-Path $DsimHome "dsim_deps\bin"),
        (Join-Path $DsimHome "lib")
    )
    $env:PATH = ($paths -join ";") + ";" + $env:PATH

    # License
    if (-not $env:DSIM_LICENSE) {
        $licPaths = @(
            (Join-Path (Split-Path $DsimHome) "dsim-license.json"),
            (Join-Path $DsimHome "dsim-license.json"),
            (Join-Path $env:LOCALAPPDATA "metrics-ca\dsim-license.json")
        )
        foreach ($lic in $licPaths) {
            if (Test-Path $lic) {
                $env:DSIM_LICENSE = $lic
                break
            }
        }
    }

    # Create directories
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    New-Item -ItemType Directory -Force -Path $WaveDir | Out-Null

    # Auto-cleanup old files if requested
    if ($CleanupDays -gt 0) {
        Cleanup-OldLogs -Days $CleanupDays
    }
}

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

# Run DSIM
function Run-Dsim {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogDir "${TestName}_${timestamp}.log"
    $waveFile = Join-Path $WaveDir "${TestName}_${timestamp}.mxd"
    $imageName = "compiled_image_${TestName}"

    # Build command arguments
    $dsimExe = Join-Path $DsimHome "bin\dsim.exe"
    $args = @(
        "-uvm", "1.2",
        "-timescale", "1ns/1ps",
        "-f", $ConfigFile,
        "-top", $TopModule,
        "+UVM_TESTNAME=$TestName",
        "+UVM_VERBOSITY=$Verbosity",
        "-sv_seed", $Seed,
        "-l", $logFile,
        "+UVM_PHASE_TRACE",
        "+UVM_OBJECTION_TRACE"
    )

    if ($Waves) {
        $args += @("-waves", $waveFile)
    }

    if ($CompileOnly) {
        $args += @("-genimage", $imageName)
    } elseif ($RunOnly) {
        $args += @("-image", $imageName)
    }

    # Display info
    Write-Host "============================================================"
    Write-Host "DSIM UVM Test: $TestName"
    Write-Host "============================================================"
    Write-Host "Working Dir: $TbDir"
    Write-Host "Log File: $logFile"
    if ($Waves) {
        Write-Host "Waveform: $waveFile"
    }
    Write-Host "------------------------------------------------------------"
    Write-Host "Command: $dsimExe $($args -join ' ')"
    Write-Host "============================================================"

    # Change to TB directory and execute
    Push-Location $TbDir
    try {
        $process = Start-Process -FilePath $dsimExe -ArgumentList $args -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode
    }
    finally {
        Pop-Location
    }

    # Parse results
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "RESULTS"
    Write-Host "============================================================"

    $uvmErrors = 0
    $uvmFatals = 0
    $testPass = $false

    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile

        # Parse UVM Report Summary section for accurate counts
        foreach ($line in $logContent) {
            if ($line -match "^\s*UVM_ERROR\s*:\s*(\d+)") {
                $uvmErrors = [int]$Matches[1]
            }
            if ($line -match "^\s*UVM_FATAL\s*:\s*(\d+)") {
                $uvmFatals = [int]$Matches[1]
            }
            if ($line -match "TEST PASSED|PASS:\s") {
                $testPass = $true
            }
        }

        Write-Host "UVM Errors: $uvmErrors"
        Write-Host "UVM Fatals: $uvmFatals"

        if ($uvmErrors -eq 0 -and $uvmFatals -eq 0 -and $exitCode -eq 0) {
            Write-Host "Status: PASS"
            $testPass = $true
        } else {
            Write-Host "Status: FAIL"
            Write-Host ""
            Write-Host "--- Error Summary ---"
            $logContent | Select-String -Pattern "^\s*UVM_ERROR|^\s*UVM_FATAL|\bFAIL\b" | Select-Object -First 20
            $testPass = $false
        }
    }

    Write-Host ""
    Write-Host "Log: $logFile"
    if ($Waves) {
        Write-Host "Wave: $waveFile"
    }
    Write-Host "Exit Code: $exitCode"

    # Output JSON for script consumers
    $resultCode = if ($testPass) { 0 } else { 1 }

    $resultJson = @{
        test_name = $TestName
        status = if ($testPass) { "success" } else { "failure" }
        exit_code = $resultCode
        log_file = $logFile
        wave_file = if ($Waves) { $waveFile } else { "" }
        timestamp = $timestamp
    } | ConvertTo-Json

    $jsonFile = Join-Path $LogDir "${TestName}_${timestamp}_result.json"
    $resultJson | Out-File -FilePath $jsonFile -Encoding UTF8

    return $resultCode
}

# Main
Setup-Environment
$result = Run-Dsim
exit $result
