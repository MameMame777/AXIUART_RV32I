# VexRiscv Build Environment Setup Script
# Sets up Java JDK 11+ and sbt for SpinalHDL compilation

param(
    [switch]$CheckOnly,
    [switch]$InstallIfMissing
)

$ErrorActionPreference = "Stop"

Write-Host "=== VexRiscv Build Environment Checker ===" -ForegroundColor Cyan

# Check Java JDK
Write-Host "`nChecking Java JDK..." -ForegroundColor Yellow
try {
    $javaVersion = java -version 2>&1 | Select-String "version" | Out-String
    if ($javaVersion -match '(\d+)\.(\d+)') {
        $majorVersion = [int]$matches[1]
        if ($majorVersion -ge 11 -or ($majorVersion -eq 1 -and [int]$matches[2] -ge 8)) {
            Write-Host "✓ Java JDK found: $javaVersion" -ForegroundColor Green
            $javaOk = $true
        } else {
            Write-Host "✗ Java version too old (need 11+): $javaVersion" -ForegroundColor Red
            $javaOk = $false
        }
    } else {
        Write-Host "✗ Cannot parse Java version" -ForegroundColor Red
        $javaOk = $false
    }
} catch {
    Write-Host "✗ Java JDK not found" -ForegroundColor Red
    $javaOk = $false
}

# Check sbt
Write-Host "`nChecking sbt (Scala Build Tool)..." -ForegroundColor Yellow
try {
    $sbtVersion = sbt --version 2>&1 | Select-String "sbt version" | Out-String
    Write-Host "✓ sbt found: $sbtVersion" -ForegroundColor Green
    $sbtOk = $true
} catch {
    Write-Host "✗ sbt not found" -ForegroundColor Red
    $sbtOk = $false
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($javaOk -and $sbtOk) {
    Write-Host "✓ All requirements met. VexRiscv can be built." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Missing requirements:" -ForegroundColor Red
    if (-not $javaOk) {
        Write-Host "  - Java JDK 11+ (Download: https://adoptium.net/)" -ForegroundColor Yellow
    }
    if (-not $sbtOk) {
        Write-Host "  - sbt (Download: https://www.scala-sbt.org/download.html)" -ForegroundColor Yellow
    }
    
    if ($InstallIfMissing) {
        Write-Host "`nAttempting automatic installation..." -ForegroundColor Yellow
        
        # Check if winget is available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            if (-not $javaOk) {
                Write-Host "Installing OpenJDK 11..." -ForegroundColor Cyan
                winget install Microsoft.OpenJDK.11
            }
            if (-not $sbtOk) {
                Write-Host "Installing sbt..." -ForegroundColor Cyan
                winget install sbt.sbt
            }
            Write-Host "Installation complete. Please restart PowerShell and run this script again." -ForegroundColor Green
        } else {
            Write-Host "winget not available. Please install manually." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nRun with -InstallIfMissing to attempt automatic installation" -ForegroundColor Cyan
    }
    
    exit 1
}
